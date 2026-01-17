#include "network/sync_manager.hpp"
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>

namespace zinc::network {

namespace {
bool sync_debug_enabled() {
    return qEnvironmentVariableIsSet("ZINC_DEBUG_SYNC");
}

bool sync_discovery_disabled() {
    return qEnvironmentVariableIsSet("ZINC_SYNC_DISABLE_DISCOVERY");
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

    if (sync_discovery_disabled()) {
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
    
    setupConnection(*peer);
    peer->connection->connectToPeer(peer_info->host, peer_info->port, identity_);
    
    peers_[device_id] = std::move(peer);
}

void SyncManager::connectToEndpoint(const Uuid& device_id,
                                    const QHostAddress& host,
                                    uint16_t port) {
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
    
    setupConnection(*peer);
    peer->connection->connectToPeer(host, port, identity_);
    
    peers_[device_id] = std::move(peer);
}

void SyncManager::disconnectFromPeer(const Uuid& device_id) {
    auto it = peers_.find(device_id);
    if (it != peers_.end()) {
        if (sync_debug_enabled()) {
            qInfo() << "SYNC: disconnectFromPeer device_id=" << QString::fromStdString(device_id.to_string());
        }
        if (it->second->connection) {
            it->second->connection->disconnect();
        }
        peers_.erase(it);
        emit peerDisconnected(device_id);
        emit peersChanged();
    }
    autoconnect_attempted_.erase(device_id);
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
    
    for (auto& [id, peer] : peers_) {
        if (peer->connection && peer->connection->isConnected()) {
            peer->connection->send(MessageType::ChangeNotify, payload);
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
        if (peer->connection && peer->connection->isConnected()) {
            ++count;
        }
    }
    return count;
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
    autoconnect_attempted_.erase(device_id);
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
    
    // Find and remove the peer
    for (auto it = peers_.begin(); it != peers_.end(); ++it) {
        if (it->second->connection.get() == conn) {
            Uuid id = it->first;
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: disconnected peer_id=" << QString::fromStdString(id.to_string());
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
    for (auto it = peers_.begin(); it != peers_.end(); ++it) {
        if (it->second->connection.get() == conn) {
            const auto id = it->first;
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
    for (const auto& [id, peer] : peers_) {
        if (peer->connection.get() == conn) {
            peer_id = id;
            break;
        }
    }
    
    switch (type) {
        case MessageType::Hello:
            handleHello(*conn, payload);
            break;
        case MessageType::PagesSnapshot: {
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: msg PagesSnapshot bytes=" << payload.size();
            }
            qInfo() << "SYNC: Received PagesSnapshot bytes=" << payload.size();
            QByteArray data(
                reinterpret_cast<const char*>(payload.data()),
                static_cast<int>(payload.size()));
            emit pageSnapshotReceived(data);
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
        return;
    }

    const auto remoteId = *remoteIdParsed;
    const auto remoteWs = *remoteWsParsed;
    if (remoteId == device_id_) {
        conn.disconnect();
        return;
    }
    if (remoteWs != workspace_id_) {
        conn.disconnect();
        return;
    }

    // Find current peer entry by connection pointer.
    auto currentIt = std::find_if(peers_.begin(), peers_.end(),
                                  [&](const auto& entry) { return entry.second->connection.get() == &conn; });
    if (currentIt == peers_.end()) {
        return;
    }

    auto& currentPeer = *currentIt->second;
    currentPeer.hello_received = true;
    currentPeer.device_name = name;
    currentPeer.host = conn.peerAddress();
    currentPeer.port = port > 0 && port <= 65535 ? static_cast<uint16_t>(port) : conn.peerPort();

    // If we already have an entry for this remoteId, dedupe.
    auto existingIt = peers_.find(remoteId);
    if (existingIt != peers_.end() && existingIt != currentIt) {
        auto& existingPeer = *existingIt->second;

        const auto existingRank = connection_rank(existingPeer.connection ? existingPeer.connection->state() : Connection::State::Disconnected);
        const auto currentRank = connection_rank(currentPeer.connection ? currentPeer.connection->state() : Connection::State::Disconnected);

        const auto existingInitiator = existingPeer.initiated_by_us ? device_id_ : remoteId;
        const auto currentInitiator = currentPeer.initiated_by_us ? device_id_ : remoteId;

        const auto keepExisting =
            (existingRank > currentRank) ||
            (existingRank == currentRank && existingInitiator < currentInitiator);

        if (keepExisting) {
            currentPeer.connection->disconnect();
            peers_.erase(currentIt);
            return;
        }

        existingPeer.connection->disconnect();
        peers_.erase(existingIt);
    }

    // Rekey the map entry to the real remoteId if needed (incoming connections start with a temp id).
    if (currentIt->first != remoteId) {
        auto node = peers_.extract(currentIt->first);
        node.key() = remoteId;
        peers_.insert(std::move(node));
    }

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
    for (const auto& [id, peer] : peers_) {
        if (peer->connection && peer->connection->isConnected()) {
            peer->connection->send(MessageType::PagesSnapshot, payload);
        }
    }
}

} // namespace zinc::network
