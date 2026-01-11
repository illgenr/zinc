#include "network/sync_manager.hpp"
#include <QDebug>

namespace zinc::network {

SyncManager::SyncManager(QObject* parent)
    : QObject(parent)
    , discovery_(std::make_unique<DiscoveryService>(this))
    , server_(std::make_unique<TransportServer>(this))
{
    connect(discovery_.get(), &DiscoveryService::peerDiscovered,
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
                             const QString& device_name) {
    identity_ = identity;
    workspace_id_ = workspace_id;
    device_name_ = device_name;
    device_id_ = Uuid::generate();  // Generate a stable device ID
}

bool SyncManager::start(uint16_t port) {
    if (started_) return true;
    
    // Start listening for incoming connections
    auto listen_result = server_->listen(port);
    if (listen_result.is_err()) {
        emit error(QString::fromStdString(listen_result.unwrap_err().message));
        return false;
    }
    
    uint16_t actual_port = listen_result.unwrap();
    
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
    
    // Disconnect all peers
    for (auto& [id, peer] : peers_) {
        if (peer->connection) {
            peer->connection->disconnect();
        }
    }
    peers_.clear();
    
    discovery_->stopBrowsing();
    discovery_->stopAdvertising();
    server_->close();
    
    started_ = false;
    syncing_ = false;
    emit syncingChanged();
    emit peersChanged();
}

void SyncManager::connectToPeer(const Uuid& device_id) {
    auto peer_info = discovery_->peer(device_id);
    if (!peer_info) {
        emit error("Peer not found");
        return;
    }
    
    // Check if already connected
    auto it = peers_.find(device_id);
    if (it != peers_.end() && it->second->connection && 
        it->second->connection->isConnected()) {
        return;
    }
    
    // Create new connection
    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = device_id;
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    
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
    
    // Check if already connected
    auto it = peers_.find(device_id);
    if (it != peers_.end() && it->second->connection &&
        it->second->connection->isConnected()) {
        return;
    }
    
    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = device_id;
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    
    setupConnection(*peer);
    peer->connection->connectToPeer(host, port, identity_);
    
    peers_[device_id] = std::move(peer);
}

void SyncManager::disconnectFromPeer(const Uuid& device_id) {
    auto it = peers_.find(device_id);
    if (it != peers_.end()) {
        if (it->second->connection) {
            it->second->connection->disconnect();
        }
        peers_.erase(it);
        emit peerDisconnected(device_id);
        emit peersChanged();
    }
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
    connect(peer.connection.get(), &Connection::messageReceived,
            this, &SyncManager::onMessageReceived);
    connect(peer.connection.get(), &Connection::error,
            this, &SyncManager::error);
}

void SyncManager::onPeerDiscovered(const PeerInfo& peer) {
    // Auto-connect to peers in same workspace
    if (peer.workspace_id == workspace_id_ && peer.device_id != device_id_) {
        connectToPeer(peer.device_id);
    }
}

void SyncManager::onPeerLost(const Uuid& device_id) {
    disconnectFromPeer(device_id);
}

void SyncManager::onNewConnection(QTcpSocket* socket) {
    // Accept incoming connection
    auto peer = std::make_unique<PeerConnection>();
    peer->device_id = Uuid::generate();  // Will be updated after handshake
    peer->connection = std::make_unique<Connection>(this);
    peer->sync_state = SyncState::Connecting;
    
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
            emit peerConnected(id);
            emit peersChanged();
            break;
        }
    }
}

void SyncManager::onConnectionDisconnected() {
    auto* conn = qobject_cast<Connection*>(sender());
    if (!conn) return;
    
    // Find and remove the peer
    for (auto it = peers_.begin(); it != peers_.end(); ++it) {
        if (it->second->connection.get() == conn) {
            Uuid id = it->first;
            peers_.erase(it);
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

} // namespace zinc::network
