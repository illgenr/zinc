#include "network/udp_discovery_backend.hpp"

#include "network/discovery_datagram.hpp"

#include <QByteArray>
#include <QUdpSocket>
#include <QTimer>
#include <QVariant>

namespace zinc::network {
namespace {

constexpr quint16 kDiscoveryPort = 47777;
const QHostAddress kMulticastGroup(QStringLiteral("239.255.77.77"));
constexpr int kAdvertiseIntervalMs = 1500;
constexpr int kPruneIntervalMs = 1000;
constexpr int64_t kPeerTtlMs = 6000;

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
    socket_->setSocketOption(QAbstractSocket::MulticastTtlOption, QVariant(1));

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
        // Some platforms/drivers can transiently report -1 for pendingDatagramSize().
        // Avoid resizing to a negative value (which can crash/oom) by reading into a fixed buffer.
        static constexpr int kMaxDatagramBytes = 64 * 1024;
        QByteArray datagram;
        datagram.resize(kMaxDatagramBytes);

        QHostAddress sender;
        quint16 sender_port = 0;
        const auto read = socket_->readDatagram(datagram.data(), datagram.size(), &sender, &sender_port);
        Q_UNUSED(sender_port)
        if (read <= 0) {
            continue;
        }
        datagram.truncate(static_cast<int>(read));

        auto peer = decode_discovery_datagram(datagram, sender);
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

    const auto bytes = encode_discovery_datagram(advertised_);

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
