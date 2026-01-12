#include "network/udp_discovery_backend.hpp"

#include "crypto/keys.hpp"

#include <QByteArray>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUdpSocket>
#include <QTimer>

namespace zinc::network {
namespace {

constexpr quint16 kDiscoveryPort = 47777;
const QHostAddress kMulticastGroup(QStringLiteral("239.255.77.77"));
constexpr int kAdvertiseIntervalMs = 1500;
constexpr int kPruneIntervalMs = 1000;
constexpr int64_t kPeerTtlMs = 6000;

constexpr const char* kMsgType = "zinc-sync";

QJsonObject toJson(const ServiceInfo& info) {
    QJsonObject obj;
    obj["t"] = QString::fromLatin1(kMsgType);
    obj["v"] = info.protocol_version;
    obj["id"] = QString::fromStdString(info.device_id.to_string());
    obj["ws"] = QString::fromStdString(info.workspace_id.to_string());
    obj["name"] = info.device_name;
    obj["port"] = static_cast<int>(info.port);
    obj["pk"] = QString::fromStdString(crypto::to_base64(info.public_key_fingerprint));
    obj["ts"] = QDateTime::currentMSecsSinceEpoch();
    return obj;
}

Result<PeerInfo, Error> fromJson(const QJsonObject& obj, const QHostAddress& sender) {
    if (obj["t"].toString() != QString::fromLatin1(kMsgType)) {
        return Result<PeerInfo, Error>::err(Error{"wrong message type"});
    }
    if (!obj.contains("id") || !obj.contains("ws") || !obj.contains("port") || !obj.contains("v")) {
        return Result<PeerInfo, Error>::err(Error{"missing fields"});
    }

    auto id = Uuid::parse(obj["id"].toString().toStdString());
    if (!id) {
        return Result<PeerInfo, Error>::err(Error{"invalid device id"});
    }

    auto ws = Uuid::parse(obj["ws"].toString().toStdString());
    if (!ws) {
        return Result<PeerInfo, Error>::err(Error{"invalid workspace id"});
    }

    int port_int = obj["port"].toInt();
    if (port_int <= 0 || port_int > 65535) {
        return Result<PeerInfo, Error>::err(Error{"invalid port"});
    }

    PeerInfo peer;
    peer.device_id = *id;
    peer.workspace_id = *ws;
    peer.device_name = obj["name"].toString();
    peer.host = sender;
    peer.port = static_cast<uint16_t>(port_int);
    peer.protocol_version = obj["v"].toInt();
    peer.last_seen = Timestamp::now();

    auto pk_b64 = obj["pk"].toString().toStdString();
    if (!pk_b64.empty()) {
        auto decoded = crypto::from_base64(pk_b64);
        if (decoded.is_ok()) {
            peer.public_key_fingerprint = decoded.unwrap();
        }
    }

    return Result<PeerInfo, Error>::ok(std::move(peer));
}

} // namespace

UdpDiscoveryBackend::UdpDiscoveryBackend(QObject* parent)
    : QObject(parent)
    , advertise_timer_(std::make_unique<QTimer>(this))
    , prune_timer_(std::make_unique<QTimer>(this))
{
    advertise_timer_->setInterval(kAdvertiseIntervalMs);
    prune_timer_->setInterval(kPruneIntervalMs);

    connect(advertise_timer_.get(), &QTimer::timeout, this, &UdpDiscoveryBackend::onAdvertiseTick);
    connect(prune_timer_.get(), &QTimer::timeout, this, &UdpDiscoveryBackend::onPruneTick);
}

UdpDiscoveryBackend::~UdpDiscoveryBackend() {
    stop_advertising();
    stop_browsing();
}

Result<void, Error> UdpDiscoveryBackend::ensureSockets() {
    if (socket_) {
        return Result<void, Error>::ok();
    }

    socket_ = std::make_unique<QUdpSocket>(this);
    socket_->setSocketOption(QAbstractSocket::MulticastTtlOption, 1);

    if (!socket_->bind(QHostAddress::AnyIPv4,
                       kDiscoveryPort,
                       QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        auto msg = socket_->errorString().toStdString();
        socket_.reset();
        return Result<void, Error>::err(Error{msg});
    }

    socket_->joinMulticastGroup(kMulticastGroup);
    connect(socket_.get(), &QUdpSocket::readyRead, this, &UdpDiscoveryBackend::onReadyRead);

    return Result<void, Error>::ok();
}

void UdpDiscoveryBackend::closeSockets() {
    if (!socket_) return;
    socket_->leaveMulticastGroup(kMulticastGroup);
    socket_.reset();
}

Result<void, Error> UdpDiscoveryBackend::start_advertising(const ServiceInfo& info) {
    advertised_ = info;
    advertising_ = true;

    auto sockets = ensureSockets();
    if (sockets.is_err()) return sockets;

    advertise_timer_->start();
    announceOnce();
    return Result<void, Error>::ok();
}

void UdpDiscoveryBackend::stop_advertising() {
    advertising_ = false;
    advertise_timer_->stop();
    if (!browsing_) {
        closeSockets();
    }
}

Result<void, Error> UdpDiscoveryBackend::start_browsing() {
    browsing_ = true;

    auto sockets = ensureSockets();
    if (sockets.is_err()) return sockets;

    prune_timer_->start();
    return Result<void, Error>::ok();
}

void UdpDiscoveryBackend::stop_browsing() {
    browsing_ = false;
    prune_timer_->stop();

    // Emit lost for all peers.
    if (on_peer_lost) {
        for (const auto& [id, entry] : peers_) {
            on_peer_lost(id);
        }
    }
    peers_.clear();

    if (!advertising_) {
        closeSockets();
    }
}

void UdpDiscoveryBackend::onReadyRead() {
    if (!socket_ || !browsing_) return;

    while (socket_->hasPendingDatagrams()) {
        QByteArray datagram;
        datagram.resize(static_cast<int>(socket_->pendingDatagramSize()));

        QHostAddress sender;
        quint16 sender_port = 0;
        socket_->readDatagram(datagram.data(), datagram.size(), &sender, &sender_port);
        Q_UNUSED(sender_port)

        QJsonParseError err{};
        auto doc = QJsonDocument::fromJson(datagram, &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            continue;
        }

        auto peer = fromJson(doc.object(), sender);
        if (peer.is_err()) {
            continue;
        }

        auto info = peer.unwrap();
        auto now = Timestamp::now();

        auto it = peers_.find(info.device_id);
        if (it == peers_.end()) {
            peers_.emplace(info.device_id, PeerEntry{info, now});
            if (on_peer_discovered) on_peer_discovered(info);
        } else {
            it->second.last_seen = now;
            bool changed = (it->second.info.host != info.host) ||
                           (it->second.info.port != info.port) ||
                           (it->second.info.workspace_id != info.workspace_id) ||
                           (it->second.info.device_name != info.device_name);
            it->second.info = info;
            // Emit updates even when the endpoint hasn't changed, so consumers can
            // treat it as a presence heartbeat.
            if (on_peer_updated) {
                on_peer_updated(info);
            }
        }
    }
}

void UdpDiscoveryBackend::announceOnce() {
    if (!socket_ || !advertising_) return;

    auto obj = toJson(advertised_);
    auto bytes = QJsonDocument(obj).toJson(QJsonDocument::Compact);

    // Multicast (preferred)
    socket_->writeDatagram(bytes, kMulticastGroup, kDiscoveryPort);

    // Broadcast (helps on networks without multicast)
    socket_->writeDatagram(bytes, QHostAddress::Broadcast, kDiscoveryPort);
}

void UdpDiscoveryBackend::onAdvertiseTick() {
    announceOnce();
}

void UdpDiscoveryBackend::onPruneTick() {
    if (!browsing_) return;

    const auto now = Timestamp::now();
    std::vector<Uuid> to_remove;
    to_remove.reserve(peers_.size());

    for (const auto& [id, entry] : peers_) {
        if ((now - entry.last_seen).count() > kPeerTtlMs) {
            to_remove.push_back(id);
        }
    }

    for (const auto& id : to_remove) {
        peers_.erase(id);
        if (on_peer_lost) on_peer_lost(id);
    }
}

} // namespace zinc::network
