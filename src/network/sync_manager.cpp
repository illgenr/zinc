#include "network/sync_manager.hpp"
#include "network/hello_policy.hpp"
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QPointer>
#include <algorithm>

namespace zinc::network {

namespace {
bool sync_debug_enabled() {
    return qEnvironmentVariableIsSet("ZINC_DEBUG_SYNC");
}

bool sync_discovery_disabled() {
    return qEnvironmentVariableIsSet("ZINC_SYNC_DISABLE_DISCOVERY");
}

QByteArray to_bytes(const QJsonObject& obj) {
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

std::optional<QJsonObject> parse_object(const std::vector<uint8_t>& payload, QJsonParseError* outErr) {
    const QByteArray bytes(reinterpret_cast<const char*>(payload.data()),
                           static_cast<int>(payload.size()));
    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(bytes, &err);
    if (outErr) *outErr = err;
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        return std::nullopt;
    }
    return doc.object();
}

QString debug_peer_name(const PeerConnection* peer) {
    if (!peer) {
        return QStringLiteral("<unknown>");
    }
    const auto name = peer->device_name.trimmed();
    if (!name.isEmpty()) {
        return name;
    }
    return QString::fromStdString(peer->device_id.to_string());
}
} // namespace

SyncManager::SyncManager(QObject* parent)
    : QObject(parent)
    , discovery_(std::make_unique<DiscoveryService>(this))
    , server_(std::make_unique<TransportServer>(this))
{
    connect(discovery_.get(), &DiscoveryService::peerDiscovered,
            this, &SyncManager::onPeerDiscovered);
    // Treat periodic "peer updated" events as presence refresh so that
    // higher layers can update "last seen" and endpoints.
    connect(discovery_.get(), &DiscoveryService::peerUpdated,
            this, &SyncManager::onPeerDiscovered);
    connect(discovery_.get(), &DiscoveryService::peerLost,
            this, &SyncManager::onPeerLost);
    
    connect(server_.get(), &TransportServer::newConnection,
            this, &SyncManager::onNewConnection);
}

SyncManager::~SyncManager() {
    stop();
}

void SyncManager::initialize(const crypto::KeyPair& identity,
                             const Uuid& workspace_id,
                             const QString& device_name,
                             const Uuid& device_id) {
    identity_ = identity;
    workspace_id_ = workspace_id;
    device_name_ = device_name;
    device_id_ = device_id.is_nil() ? Uuid::generate() : device_id;
}

bool SyncManager::start(uint16_t port) {
    if (started_) return true;
    
    // Start listening for incoming connections
    auto listen_result = server_->listen(port);
    if (listen_result.is_err() && port != 0) {
        // Fall back to ephemeral port (e.g., if preferred port is in use).
        listen_result = server_->listen(0);
    }
    if (listen_result.is_err()) {
        emit error(QString::fromStdString(listen_result.unwrap_err().message));
        return false;
    }
    
    uint16_t actual_port = listen_result.unwrap();
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: listen port=" << actual_port
                << "device_id=" << QString::fromStdString(device_id_.to_string())
                << "workspace_id=" << QString::fromStdString(workspace_id_.to_string());
    }

    if (sync_discovery_disabled() || workspace_id_.is_nil()) {
        started_ = true;
        syncing_ = true;
        emit syncingChanged();
        return true;
    }
    
    // Start advertising our service
    ServiceInfo info{
        .device_id = device_id_,
        .device_name = device_name_,
        .port = actual_port,
        .public_key_fingerprint = crypto::fingerprint(identity_.public_key),
        .workspace_id = workspace_id_,
        .protocol_version = DiscoveryService::PROTOCOL_VERSION
    };
    
    if (!discovery_->startAdvertising(info)) {
        server_->close();
        return false;
    }
    
    // Start browsing for peers
    if (!discovery_->startBrowsing()) {
        discovery_->stopAdvertising();
        server_->close();
        return false;
    }
    
    started_ = true;
    syncing_ = true;
    emit syncingChanged();
    
    return true;
}

void SyncManager::stop() {
    if (!started_) return;
    
    stopping_ = true;
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: stop";
    }
    // Disconnect all peers
    for (auto& [id, peer] : peers_) {
        if (peer->connection) {
            peer->connection->disconnect();
        }
    }
    peers_.clear();
    autoconnect_attempted_.clear();
    
    discovery_->stopBrowsing();
    discovery_->stopAdvertising();
    server_->close();
    
    started_ = false;
    syncing_ = false;
    stopping_ = false;
    emit syncingChanged();
    emit peersChanged();
}

void SyncManager::connectToPeer(const Uuid& device_id) {
    auto peer_info = discovery_->peer(device_id);
    if (!peer_info) {
        emit error("Peer not found");
        return;
    }
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: connectToPeer device_id=" << QString::fromStdString(device_id.to_string())
                << "host=" << peer_info->host.toString()
                << "port=" << peer_info->port;
    }
    
    // Check if already connected
    auto it = peers_.find(device_id);
    if (it != peers_.end() && it->second->connection) {
        const auto state = it->second->connection->state();
        if (state == Connection::State::Connected ||
            state == Connection::State::Connecting ||
            state == Connection::State::Handshaking) {
            return;
        }
    }
    
    // Create new connection
    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = device_id;
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    peer->initiated_by_us = true;
    peer->allow_rekey_on_hello = false;
    
    setupConnection(*peer);
    peer->connection->connectToPeer(peer_info->host, peer_info->port, identity_);
    
    peers_[device_id] = std::move(peer);
}

void SyncManager::connectToEndpoint(const Uuid& device_id,
                                    const QHostAddress& host,
                                    uint16_t port,
                                    bool allow_rekey_on_hello) {
    if (device_id.is_nil()) {
        emit error("Invalid peer device ID");
        return;
    }
    if (device_id == device_id_) {
        return;
    }
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: connectToEndpoint device_id=" << QString::fromStdString(device_id.to_string())
                << "host=" << host.toString()
                << "port=" << port;
    }
    
    // Check if already connected
    auto it = peers_.find(device_id);
    if (it != peers_.end() && it->second->connection) {
        const auto state = it->second->connection->state();
        if (state == Connection::State::Connected ||
            state == Connection::State::Connecting ||
            state == Connection::State::Handshaking) {
            return;
        }
    }
    
    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = device_id;
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    peer->initiated_by_us = true;
    peer->approved = true;
    peer->allow_rekey_on_hello = allow_rekey_on_hello;
    
    setupConnection(*peer);
    peer->connection->connectToPeer(host, port, identity_);
    
    peers_[device_id] = std::move(peer);
}

void SyncManager::connectToEndpoint(const Uuid& device_id,
                                    const QString& host,
                                    uint16_t port,
                                    bool allow_rekey_on_hello) {
    if (device_id.is_nil()) {
        emit error("Invalid peer device ID");
        return;
    }
    if (device_id == device_id_) {
        return;
    }
    if (host.trimmed().isEmpty()) {
        emit error("Invalid peer host");
        return;
    }
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: connectToEndpoint(hostname) device_id=" << QString::fromStdString(device_id.to_string())
                << "host=" << host
                << "port=" << port;
    }

    // Check if already connected
    auto it = peers_.find(device_id);
    if (it != peers_.end() && it->second->connection) {
        const auto state = it->second->connection->state();
        if (state == Connection::State::Connected ||
            state == Connection::State::Connecting ||
            state == Connection::State::Handshaking) {
            return;
        }
    }

    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = device_id;
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    peer->initiated_by_us = true;
    peer->approved = true;
    peer->allow_rekey_on_hello = allow_rekey_on_hello;

    setupConnection(*peer);
    peer->connection->connectToPeer(host.trimmed(), port, identity_);

    peers_[device_id] = std::move(peer);
}

void SyncManager::approvePeer(const Uuid& device_id, bool approved) {
    auto it = peers_.find(device_id);
    if (it == peers_.end() || !it->second) {
        return;
    }
    auto& peer = *it->second;
    if (approved) {
        if (peer.approved) {
            return;
        }
        if (!peer.connection || !peer.connection->isConnected() || !peer.hello_received) {
            return;
        }
        if (sync_debug_enabled()) {
            qInfo() << "SYNC: peer approved device_id=" << QString::fromStdString(device_id.to_string());
        }
        peer.approved = true;
        emit peerConnected(device_id);
        emit peersChanged();
        return;
    }

    if (sync_debug_enabled()) {
        qInfo() << "SYNC: peer rejected device_id=" << QString::fromStdString(device_id.to_string());
    }
    disconnectFromPeer(device_id);
}

void SyncManager::sendPairingRequest(const Uuid& device_id,
                                     const Uuid& workspace_id) {
    auto it = peers_.find(device_id);
    if (it == peers_.end() || !it->second || !it->second->connection || !it->second->connection->isConnected()) {
        emit error("Pairing failed: peer not connected");
        return;
    }

    QJsonObject obj;
    obj["v"] = 1;
    obj["ws"] = QString::fromStdString(workspace_id.to_string());
    obj["name"] = device_name_;
    obj["id"] = QString::fromStdString(device_id_.to_string());

    const auto bytes = to_bytes(obj);
    const std::vector<uint8_t> payload(bytes.begin(), bytes.end());
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: send PairingRequest to" << QString::fromStdString(device_id.to_string())
                << "ws=" << QString::fromStdString(workspace_id.to_string());
    }
    it->second->connection->send(MessageType::PairingRequest, payload);
}

void SyncManager::sendPairingResponse(const Uuid& device_id,
                                      bool accepted,
                                      const QString& reason,
                                      const Uuid& workspace_id) {
    auto it = peers_.find(device_id);
    if (it == peers_.end() || !it->second || !it->second->connection || !it->second->connection->isConnected()) {
        return;
    }

    QJsonObject obj;
    obj["v"] = 1;
    obj["ok"] = accepted;
    obj["reason"] = reason;
    obj["ws"] = QString::fromStdString(workspace_id.to_string());

    const auto bytes = to_bytes(obj);
    const std::vector<uint8_t> payload(bytes.begin(), bytes.end());
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: send PairingResponse to" << QString::fromStdString(device_id.to_string())
                << "ok=" << accepted
                << "ws=" << QString::fromStdString(workspace_id.to_string())
                << "reason=" << reason;
    }
    it->second->connection->send(MessageType::PairingResponse, payload);
}

void SyncManager::disconnectFromPeer(const Uuid& device_id) {
    auto it = peers_.find(device_id);
    if (it == peers_.end()) {
        autoconnect_attempted_.erase(device_id);
        return;
    }

    if (sync_debug_enabled()) {
        qInfo() << "SYNC: disconnectFromPeer device_id=" << QString::fromStdString(device_id.to_string());
    }

    // Important: remove from the map before calling Connection::disconnect(), because that may
    // synchronously emit signals that would otherwise re-enter and erase the same map entry.
    auto peer = std::move(it->second);
    peers_.erase(it);
    autoconnect_attempted_.erase(device_id);

    if (peer && peer->connection) {
        peer->connection->disconnect();
        auto* raw = peer->connection.release();
        if (raw) raw->deleteLater();
    }

    emit peerDisconnected(device_id);
    emit peersChanged();
}

void SyncManager::broadcastChange(const std::string& doc_id,
                                  const std::vector<uint8_t>& change_bytes) {
    // Create payload: doc_id length (4 bytes) + doc_id + change_bytes
    std::vector<uint8_t> payload;
    uint32_t doc_id_len = static_cast<uint32_t>(doc_id.size());
    payload.push_back((doc_id_len >> 24) & 0xFF);
    payload.push_back((doc_id_len >> 16) & 0xFF);
    payload.push_back((doc_id_len >> 8) & 0xFF);
    payload.push_back(doc_id_len & 0xFF);
    payload.insert(payload.end(), doc_id.begin(), doc_id.end());
    payload.insert(payload.end(), change_bytes.begin(), change_bytes.end());
    
    std::vector<QPointer<Connection>> targets;
    targets.reserve(peers_.size());
    for (const auto& [id, peer] : peers_) {
        if (peer && peer->connection && peer->connection->isConnected()) {
            targets.push_back(peer->connection.get());
        }
    }
    for (const auto& conn : targets) {
        if (conn && conn->isConnected()) {
            conn->send(MessageType::ChangeNotify, payload);
        }
    }
}

void SyncManager::requestSync(const Uuid& device_id, const std::string& doc_id) {
    auto it = peers_.find(device_id);
    if (it == peers_.end() || !it->second->connection ||
        !it->second->connection->isConnected()) {
        return;
    }
    
    std::vector<uint8_t> payload(doc_id.begin(), doc_id.end());
    it->second->connection->send(MessageType::SyncRequest, payload);
    it->second->sync_state = SyncState::Syncing;
}

int SyncManager::connectedPeerCount() const {
    int count = 0;
    for (const auto& [id, peer] : peers_) {
        if (peer && peer->approved && peer->connection && peer->connection->isConnected()) {
            ++count;
        }
    }
    return count;
}

bool SyncManager::isPeerConnected(const Uuid& device_id) const {
    const auto it = peers_.find(device_id);
    if (it == peers_.end() || !it->second) {
        return false;
    }
    const auto& peer = *it->second;
    return peer.approved && peer.connection && peer.connection->isConnected();
}

uint16_t SyncManager::listeningPort() const {
    return server_ ? server_->port() : 0;
}

void SyncManager::setupConnection(PeerConnection& peer) {
    connect(peer.connection.get(), &Connection::connected, 
            this, &SyncManager::onConnectionConnected);
    connect(peer.connection.get(), &Connection::disconnected,
            this, &SyncManager::onConnectionDisconnected);
    connect(peer.connection.get(), &Connection::stateChanged,
            this, &SyncManager::onConnectionStateChanged);
    connect(peer.connection.get(), &Connection::messageReceived,
            this, &SyncManager::onMessageReceived);
    connect(peer.connection.get(), &Connection::error,
            this, &SyncManager::error);
}

void SyncManager::onPeerDiscovered(const PeerInfo& peer) {
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: peerDiscovered device_id=" << QString::fromStdString(peer.device_id.to_string())
                << "workspace_id=" << QString::fromStdString(peer.workspace_id.to_string())
                << "host=" << peer.host.toString()
                << "port=" << peer.port
                << "protocol=" << peer.protocol_version;
    }
    if (peer.device_id == device_id_) {
        return;
    }
    // Auto-connect to peers in same workspace
    if (peer.workspace_id == workspace_id_) {
        if (autoconnect_attempted_.insert(peer.device_id).second) {
            connectToPeer(peer.device_id);
        }
    }
    emit peerDiscovered(peer);
}

void SyncManager::onPeerLost(const Uuid& device_id) {
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: peerLost device_id=" << QString::fromStdString(device_id.to_string());
    }
    disconnectFromPeer(device_id);
}

void SyncManager::onNewConnection(QTcpSocket* socket) {
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: incoming connection from"
                << (socket ? socket->peerAddress().toString() : QStringLiteral("<null>"))
                << (socket ? socket->peerPort() : 0);
    }
    // Accept incoming connection
    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = Uuid::generate();  // Will be updated after handshake
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    peer->initiated_by_us = false;
    peer->approved = false;
    peer->allow_rekey_on_hello = true;
    
    setupConnection(*peer);
    peer->connection->acceptConnection(socket, identity_);
    
    Uuid temp_id = peer->device_id;
    peers_[temp_id] = std::move(peer);
}

void SyncManager::onConnectionConnected() {
    auto* conn = qobject_cast<Connection*>(sender());
    if (!conn) return;
    
    // Find the peer
    for (auto& [id, peer] : peers_) {
        if (peer->connection.get() == conn) {
            peer->sync_state = SyncState::Streaming;
            sendHello(*conn);
            qInfo() << "SYNC: connection established"
                    << "peer_id=" << QString::fromStdString(id.to_string())
                    << "peer_name=" << debug_peer_name(peer.get())
                    << "endpoint=" << conn->peerAddress().toString()
                    << "port=" << conn->peerPort();
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: connected peer_id=" << QString::fromStdString(id.to_string());
            }
            break;
        }
    }
}

void SyncManager::onConnectionDisconnected() {
    auto* conn = qobject_cast<Connection*>(sender());
    if (!conn) return;
    if (stopping_) return;
    
    // Find and remove the peer.
    // Important: do not delete `conn` synchronously while handling its signal.
    for (auto it = peers_.begin(); it != peers_.end(); ++it) {
        if (it->second->connection.get() == conn) {
            Uuid id = it->first;
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: disconnected peer_id=" << QString::fromStdString(id.to_string());
            }
            if (it->second->connection) {
                auto* raw = it->second->connection.release();
                if (raw) raw->deleteLater();
            }
            peers_.erase(it);
            autoconnect_attempted_.erase(id);
            emit peerDisconnected(id);
            emit peersChanged();
            break;
        }
    }
}

void SyncManager::onConnectionStateChanged(Connection::State state) {
    if (state != Connection::State::Failed) {
        return;
    }

    auto* conn = qobject_cast<Connection*>(sender());
    if (!conn) return;
    if (stopping_) return;

    // Remove failed connections so that future presence updates can trigger retries.
    // Important: do not delete `conn` synchronously while handling its signal.
    for (auto it = peers_.begin(); it != peers_.end(); ++it) {
        if (it->second->connection.get() == conn) {
            const auto id = it->first;
            const auto endpoint = conn->peerAddress().toString();
            const auto port = conn->peerPort();
            emit error(QStringLiteral("Failed to connect to %1:%2")
                           .arg(endpoint)
                           .arg(port));
            if (it->second->connection) {
                auto* raw = it->second->connection.release();
                if (raw) raw->deleteLater();
            }
            peers_.erase(it);
            autoconnect_attempted_.erase(id);
            emit peerDisconnected(id);
            emit peersChanged();
            break;
        }
    }
}

void SyncManager::onMessageReceived(MessageType type, 
                                    const std::vector<uint8_t>& payload) {
    auto* conn = qobject_cast<Connection*>(sender());
    if (!conn) return;
    
    // Find the peer
    Uuid peer_id;
    PeerConnection* peer_ptr = nullptr;
    for (const auto& [id, peer] : peers_) {
        if (peer->connection.get() == conn) {
            peer_id = id;
            peer_ptr = peer.get();
            break;
        }
    }

    if (peer_ptr && !peer_ptr->approved &&
        type != MessageType::Hello &&
        type != MessageType::PairingRequest &&
        type != MessageType::PairingResponse &&
        type != MessageType::PairingComplete &&
        type != MessageType::PairingReject) {
        // Ignore all non-Hello traffic until the user confirms the pairing.
        return;
    }
    
    switch (type) {
        case MessageType::Hello:
            handleHello(*conn, payload);
            break;
        case MessageType::PairingRequest: {
            QJsonParseError err{};
            const auto objOpt = parse_object(payload, &err);
            if (!objOpt) {
                if (sync_debug_enabled()) {
                    qInfo() << "SYNC: PairingRequest parse failed:" << err.errorString();
                }
                return;
            }
            const auto obj = *objOpt;
            const auto wsStr = obj.value("ws").toString();
            const auto name = obj.value("name").toString();
            const auto wsParsed = Uuid::parse(wsStr.toStdString());
            if (!wsParsed) {
                return;
            }

            // Find peer id by connection pointer.
            Uuid pid;
            PeerConnection* peer = nullptr;
            for (auto& [id, p] : peers_) {
                if (p && p->connection.get() == conn) {
                    pid = id;
                    peer = p.get();
                    break;
                }
            }
            if (peer == nullptr || pid.is_nil()) {
                return;
            }

            const auto requestedWs = *wsParsed;
            if (!workspace_id_.is_nil() && requestedWs != workspace_id_) {
                qInfo() << "SYNC: PairingRequest rejected (already configured for different workspace)"
                        << "remote_id=" << QString::fromStdString(pid.to_string())
                        << "requested_ws=" << QString::fromStdString(requestedWs.to_string())
                        << "local_ws=" << QString::fromStdString(workspace_id_.to_string());
                sendPairingResponse(pid, false, QStringLiteral("Device is already paired to a different workspace"), requestedWs);
                return;
            }
            if (!workspace_id_.is_nil() && requestedWs == workspace_id_) {
                if (sync_debug_enabled()) {
                    qInfo() << "SYNC: PairingRequest no-op (already in requested workspace)"
                            << "remote_id=" << QString::fromStdString(pid.to_string())
                            << "requested_ws=" << QString::fromStdString(requestedWs.to_string());
                }
                sendPairingResponse(pid, true, QString{}, requestedWs);
                return;
            }

            qInfo() << "SYNC: PairingRequest received"
                    << "remote_id=" << QString::fromStdString(pid.to_string())
                    << "remote_name=" << name
                    << "endpoint=" << peer->host.toString()
                    << "port=" << peer->port
                    << "requested_ws=" << QString::fromStdString(requestedWs.to_string());
            emit pairingRequestReceived(pid, name, peer->host.toString(), peer->port, requestedWs);
            break;
        }
        case MessageType::PairingResponse: {
            QJsonParseError err{};
            const auto objOpt = parse_object(payload, &err);
            if (!objOpt) {
                if (sync_debug_enabled()) {
                    qInfo() << "SYNC: PairingResponse parse failed:" << err.errorString();
                }
                return;
            }
            const auto obj = *objOpt;
            const auto ok = obj.value("ok").toBool(false);
            const auto reason = obj.value("reason").toString();
            const auto wsStr = obj.value("ws").toString();
            const auto wsParsed = Uuid::parse(wsStr.toStdString());
            if (!wsParsed) {
                return;
            }

            Uuid pid;
            for (const auto& [id, p] : peers_) {
                if (p && p->connection.get() == conn) {
                    pid = id;
                    break;
                }
            }
            if (pid.is_nil()) return;

            qInfo() << "SYNC: PairingResponse received"
                    << "remote_id=" << QString::fromStdString(pid.to_string())
                    << "ok=" << ok
                    << "ws=" << wsStr
                    << "reason=" << reason;
            emit pairingResponseReceived(pid, ok, reason, *wsParsed);
            break;
        }
        case MessageType::PagesSnapshot: {
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: msg PagesSnapshot bytes=" << payload.size();
            }
            qInfo() << "SYNC: Received PagesSnapshot bytes=" << payload.size();
            if (peer_ptr) {
                qInfo() << "SYNC: PagesSnapshot from peer_id="
                        << QString::fromStdString(peer_id.to_string())
                        << "peer_name=" << debug_peer_name(peer_ptr);
            }
            QByteArray data(
                reinterpret_cast<const char*>(payload.data()),
                static_cast<int>(payload.size()));
            emit pageSnapshotReceived(data);
            break;
        }
        case MessageType::PresenceUpdate: {
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: msg PresenceUpdate bytes=" << payload.size();
                QJsonParseError err{};
                const auto objOpt = parse_object(payload, &err);
                if (objOpt) {
                    qInfo() << "SYNC: msg PresenceUpdate decoded"
                            << "peer_id=" << QString::fromStdString(peer_id.to_string())
                            << "pageId=" << objOpt->value(QStringLiteral("pageId")).toString()
                            << "titlePreview=" << objOpt->value(QStringLiteral("titlePreview")).toString();
                } else {
                    qInfo() << "SYNC: msg PresenceUpdate decode failed:" << err.errorString();
                }
            }
            QByteArray data(
                reinterpret_cast<const char*>(payload.data()),
                static_cast<int>(payload.size()));
            emit presenceReceived(peer_id, data);
            break;
        }
        case MessageType::SyncRequest:
            handleSyncRequest(peer_id, payload);
            break;
        case MessageType::SyncResponse:
            handleSyncResponse(peer_id, payload);
            break;
        case MessageType::ChangeNotify:
            handleChangeNotify(peer_id, payload);
            break;
        case MessageType::Ping:
            // Respond with pong
            if (auto it = peers_.find(peer_id); it != peers_.end()) {
                it->second->connection->send(MessageType::Pong, {});
            }
            break;
        default:
            break;
    }
}

void SyncManager::sendHello(Connection& conn) const {
    QJsonObject obj;
    obj["id"] = QString::fromStdString(device_id_.to_string());
    obj["ws"] = QString::fromStdString(workspace_id_.to_string());
    obj["name"] = device_name_;
    obj["port"] = static_cast<int>(listeningPort());
    const auto bytes = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    const std::vector<uint8_t> payload(bytes.begin(), bytes.end());
    conn.send(MessageType::Hello, payload);
}

static int connection_rank(Connection::State state) {
    switch (state) {
        case Connection::State::Connected: return 4;
        case Connection::State::Handshaking: return 3;
        case Connection::State::Connecting: return 2;
        case Connection::State::Failed: return 1;
        case Connection::State::Disconnected: return 0;
    }
    return 0;
}

void SyncManager::handleHello(Connection& conn, const std::vector<uint8_t>& payload) {
    const QByteArray bytes(reinterpret_cast<const char*>(payload.data()),
                           static_cast<int>(payload.size()));
    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(bytes, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        if (sync_debug_enabled()) {
            qInfo() << "SYNC: Hello parse failed:" << err.errorString();
        }
        return;
    }

    const auto obj = doc.object();
    const auto idStr = obj.value("id").toString();
    const auto wsStr = obj.value("ws").toString();
    const auto name = obj.value("name").toString();
    const auto port = obj.value("port").toInt();

    const auto remoteIdParsed = Uuid::parse(idStr.toStdString());
    const auto remoteWsParsed = Uuid::parse(wsStr.toStdString());
    if (!remoteIdParsed || !remoteWsParsed) {
        if (sync_debug_enabled()) {
            qInfo() << "SYNC: Hello invalid id/ws id=" << idStr << "ws=" << wsStr;
        }
        return;
    }

    const auto remoteId = *remoteIdParsed;
    const auto remoteWs = *remoteWsParsed;

    // Find current peer entry by connection pointer.
    const auto currentIt = std::find_if(peers_.begin(), peers_.end(),
                                        [&](const auto& entry) {
                                            return entry.second && entry.second->connection.get() == &conn;
                                        });
    if (currentIt == peers_.end() || !currentIt->second) {
        return;
    }

    // Hold onto the current key before any map mutation.
    const auto currentKey = currentIt->first;
    const auto allowRekey = currentIt->second->allow_rekey_on_hello;
    const auto helloPeerPort = port > 0 && port <= 65535 ? static_cast<uint16_t>(port) : conn.peerPort();
    const auto helloHostStr = conn.peerAddress().toString();

    const auto decision = decide_hello(device_id_, workspace_id_, currentKey, allowRekey, remoteId, remoteWs);
    switch (decision.kind) {
        case HelloDecisionKind::DisconnectSelf: {
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: Hello from self, disconnecting";
            }
            conn.disconnect();
            return;
        }
        case HelloDecisionKind::DisconnectIdentityMismatch: {
            qInfo() << "SYNC: Hello identity mismatch; disconnecting"
                    << "expected_id=" << QString::fromStdString(currentKey.to_string())
                    << "remote_id=" << QString::fromStdString(remoteId.to_string())
                    << "remote_name=" << name
                    << "endpoint=" << helloHostStr
                    << "port=" << helloPeerPort;
            QMetaObject::invokeMethod(this, [this, expected = currentKey, actual = remoteId, name, hostStr = helloHostStr, peerPort = helloPeerPort]() {
                emit peerIdentityMismatch(expected, actual, name, hostStr, peerPort);
                emit error(QStringLiteral("Peer identity mismatch: expected %1 but got %2 at %3:%4. Re-pair required.")
                               .arg(QString::fromStdString(expected.to_string()),
                                    QString::fromStdString(actual.to_string()),
                                    hostStr)
                               .arg(peerPort));
            }, Qt::QueuedConnection);
            conn.disconnect();
            return;
        }
        case HelloDecisionKind::DisconnectWorkspaceMismatch: {
            qInfo() << "SYNC: Hello workspace mismatch; disconnecting"
                    << "remote_id=" << QString::fromStdString(remoteId.to_string())
                    << "remote_ws=" << QString::fromStdString(remoteWs.to_string())
                    << "local_ws=" << QString::fromStdString(workspace_id_.to_string())
                    << "remote_name=" << name
                    << "endpoint=" << helloHostStr
                    << "port=" << helloPeerPort;
            QMetaObject::invokeMethod(this, [this, remoteId, remoteWs, localWs = workspace_id_, name, hostStr = helloHostStr, peerPort = helloPeerPort]() {
                emit peerWorkspaceMismatch(remoteId, remoteWs, localWs, name, hostStr, peerPort);
                emit error(QStringLiteral("Peer workspace mismatch: device %1 is not in this workspace. Re-pair required.")
                               .arg(QString::fromStdString(remoteId.to_string())));
            }, Qt::QueuedConnection);
            conn.disconnect();
            return;
        }
        case HelloDecisionKind::AcceptPairingBootstrap: {
            qInfo() << "SYNC: Hello workspace mismatch (pairing bootstrap allowed)"
                    << "remote_id=" << QString::fromStdString(remoteId.to_string())
                    << "remote_ws=" << QString::fromStdString(remoteWs.to_string())
                    << "local_ws=" << QString::fromStdString(workspace_id_.to_string())
                    << "remote_name=" << name;
            break;
        }
        case HelloDecisionKind::Accept:
            break;
    }

    {
        auto& peer = *currentIt->second;
        peer.hello_received = true;
        peer.device_name = name;
        peer.host = conn.peerAddress();
        peer.port = port > 0 && port <= 65535 ? static_cast<uint16_t>(port) : conn.peerPort();

        if (sync_debug_enabled()) {
            qInfo() << "SYNC: Hello received"
                    << "remote_id=" << QString::fromStdString(remoteId.to_string())
                    << "remote_name=" << name
                    << "host=" << peer.host.toString()
                    << "port=" << peer.port
                    << "initiated_by_us=" << peer.initiated_by_us
                    << "current_key=" << QString::fromStdString(currentKey.to_string());
        }
    }

    // If we already have an entry for this remoteId, dedupe.
    auto existingIt = peers_.find(remoteId);
    if (existingIt != peers_.end() && existingIt->second && existingIt->first != currentKey) {
        auto& existingPeer = *existingIt->second;

        const auto currentPeerIt = peers_.find(currentKey);
        if (currentPeerIt == peers_.end() || !currentPeerIt->second) {
            return;
        }
        auto& currentPeer = *currentPeerIt->second;

        const auto existingRank = connection_rank(existingPeer.connection ? existingPeer.connection->state()
                                                                         : Connection::State::Disconnected);
        const auto currentRank = connection_rank(currentPeer.connection ? currentPeer.connection->state()
                                                                       : Connection::State::Disconnected);

        const auto existingInitiator = existingPeer.initiated_by_us ? device_id_ : remoteId;
        const auto currentInitiator = currentPeer.initiated_by_us ? device_id_ : remoteId;

        const auto keepExisting =
            (existingRank > currentRank) ||
            (existingRank == currentRank && existingInitiator < currentInitiator);

        if (keepExisting) {
            currentPeer.connection->disconnect();
            peers_.erase(currentKey);
            return;
        }

        existingPeer.connection->disconnect();
        peers_.erase(existingIt);
    }

    // Rekey the map entry to the real remoteId if needed (incoming connections start with a temp id).
    if (currentKey != remoteId) {
        auto node = peers_.extract(currentKey);
        node.key() = remoteId;
        peers_.insert(std::move(node));
    }

    // Re-acquire the peer after potential rekey/dedup.
    auto updatedIt = peers_.find(remoteId);
    if (updatedIt == peers_.end() || !updatedIt->second) {
        return;
    }
    auto& updatedPeer = *updatedIt->second;
    const auto hostStr = updatedPeer.host.toString();
    const auto peerPort = updatedPeer.port;
    const bool initiatedByUs = updatedPeer.initiated_by_us;

    // Use queued emission to avoid re-entrancy hazards (slots may trigger additional sync actions).
    QMetaObject::invokeMethod(this, [this, remoteId, name, hostStr, peerPort]() {
        emit peerHelloReceived(remoteId, name, hostStr, peerPort);
    }, Qt::QueuedConnection);

    // If we're not yet in the same workspace, treat this connection as pairing-only.
    if (remoteWs != workspace_id_) {
        updatedPeer.approved = false;
        return;
    }

    // For inbound connections that were not discovered locally (e.g. manual/Tailscale), require
    // an explicit confirmation from the user before treating the peer as connected.
    const bool discovered =
        discovery_ && discovery_->peer(remoteId).has_value();
    if (!initiatedByUs && !discovered) {
        qInfo() << "SYNC: peer approval required"
                << "remote_id=" << QString::fromStdString(remoteId.to_string())
                << "remote_name=" << name
                << "endpoint=" << hostStr
                << "port=" << peerPort;
        updatedPeer.approved = false;
        emit peerApprovalRequired(remoteId, name, hostStr, peerPort);
        return;
    }

    updatedPeer.approved = true;
    emit peerConnected(remoteId);
    emit peersChanged();
}

void SyncManager::handleSyncRequest(const Uuid& peer_id, 
                                    const std::vector<uint8_t>& payload) {
    std::string doc_id(payload.begin(), payload.end());
    emit syncRequested(peer_id, QString::fromStdString(doc_id));
}

void SyncManager::handleSyncResponse(const Uuid& peer_id,
                                     const std::vector<uint8_t>& payload) {
    // Parse and emit changes
    if (payload.size() < 4) return;
    
    uint32_t doc_id_len = (payload[0] << 24) | (payload[1] << 16) | 
                          (payload[2] << 8) | payload[3];
    if (payload.size() < 4 + doc_id_len) return;
    
    std::string doc_id(payload.begin() + 4, payload.begin() + 4 + doc_id_len);
    QByteArray changes(
        reinterpret_cast<const char*>(payload.data() + 4 + doc_id_len),
        static_cast<int>(payload.size() - 4 - doc_id_len)
    );
    
    emit changeReceived(QString::fromStdString(doc_id), changes);
}

void SyncManager::handleChangeNotify(const Uuid& peer_id,
                                     const std::vector<uint8_t>& payload) {
    // Same format as sync response
    handleSyncResponse(peer_id, payload);
}

void SyncManager::sendPageSnapshot(const std::vector<uint8_t>& payload) {
    qInfo() << "SYNC: Sending PagesSnapshot bytes=" << payload.size()
             << "peers=" << peers_.size();
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: sendPageSnapshot connectedPeers=" << connectedPeerCount();
    }
    std::vector<QPointer<Connection>> targets;
    targets.reserve(peers_.size());
    for (const auto& [id, peer] : peers_) {
        if (peer && peer->connection && peer->connection->isConnected()) {
            targets.push_back(peer->connection.get());
        }
    }
    if (sync_debug_enabled() && targets.empty()) {
        qInfo() << "SYNC: sendPageSnapshot no connected peers; skipping send";
    }
    if (sync_debug_enabled()) {
        for (const auto& [id, peer] : peers_) {
            if (!peer || !peer->connection || !peer->connection->isConnected()) continue;
            qInfo() << "SYNC: sendPageSnapshot target_id=" << QString::fromStdString(id.to_string())
                    << "target_name=" << debug_peer_name(peer.get());
        }
    }
    for (const auto& conn : targets) {
        if (conn && conn->isConnected()) {
            conn->send(MessageType::PagesSnapshot, payload);
        }
    }
}

void SyncManager::sendPresenceUpdate(const std::vector<uint8_t>& payload) {
    if (sync_debug_enabled()) {
        QString preview;
        QString pageId;
        QJsonParseError err{};
        const auto objOpt = parse_object(payload, &err);
        if (objOpt) {
            pageId = objOpt->value(QStringLiteral("pageId")).toString();
            preview = objOpt->value(QStringLiteral("titlePreview")).toString();
        }
        qInfo() << "SYNC: sendPresenceUpdate bytes=" << payload.size()
                << "pageId=" << pageId
                << "titlePreview=" << preview
                << "connectedPeers=" << connectedPeerCount();
    }
    std::vector<QPointer<Connection>> targets;
    targets.reserve(peers_.size());
    std::vector<QString> targetIds;
    targetIds.reserve(peers_.size());
    for (const auto& [id, peer] : peers_) {
        if (peer && peer->connection && peer->connection->isConnected()) {
            targets.push_back(peer->connection.get());
            if (sync_debug_enabled()) {
                targetIds.push_back(QString::fromStdString(id.to_string()));
            }
        }
    }
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: sendPresenceUpdate targets=" << targetIds;
    }
    for (const auto& conn : targets) {
        if (conn && conn->isConnected()) {
            conn->send(MessageType::PresenceUpdate, payload);
        }
    }
}

} // namespace zinc::network
