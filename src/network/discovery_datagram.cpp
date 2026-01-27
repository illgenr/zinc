#include "network/discovery_datagram.hpp"

#include "crypto/keys.hpp"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>

namespace zinc::network {
namespace {

constexpr const char* kMsgType = "zinc-sync";

QJsonObject to_json(const ServiceInfo& info) {
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

} // namespace

QByteArray encode_discovery_datagram(const ServiceInfo& info) {
    return QJsonDocument(to_json(info)).toJson(QJsonDocument::Compact);
}

Result<PeerInfo, Error> decode_discovery_datagram(const QByteArray& datagram,
                                                  const QHostAddress& sender) {
    const auto doc = QJsonDocument::fromJson(datagram);
    if (doc.isNull() || !doc.isObject()) {
        return Result<PeerInfo, Error>::err(Error{"invalid json"});
    }

    const auto obj = doc.object();
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

    const int port_int = obj["port"].toInt();
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

    const auto pk_b64 = obj["pk"].toString().toStdString();
    if (!pk_b64.empty()) {
        auto decoded = crypto::from_base64(pk_b64);
        if (decoded.is_ok()) {
            peer.public_key_fingerprint = decoded.unwrap();
        }
    }

    return Result<PeerInfo, Error>::ok(std::move(peer));
}

} // namespace zinc::network

