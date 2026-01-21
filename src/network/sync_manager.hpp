#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include "network/discovery.hpp"
#include "network/transport.hpp"
#include "crypto/keys.hpp"
#include <QObject>
#include <QByteArray>
#include <map>
#include <memory>
#include <set>

namespace zinc::network {

/**
 * SyncState - State of synchronization with a peer.
 */
enum class SyncState {
    Idle,
    Connecting,
    Syncing,
    Streaming,
    Error
};

/**
 * PeerConnection - Manages a connection to a single peer.
 */
struct PeerConnection {
    Uuid device_id;
    std::unique_ptr<Connection> connection;
    SyncState sync_state = SyncState::Idle;
    Timestamp last_sync;
    int retry_count = 0;
    bool initiated_by_us = false;
    bool hello_received = false;
    QString device_name;
    QHostAddress host;
    uint16_t port = 0;
};

/**
 * SyncManager - Manages synchronization with multiple peers.
 * 
 * Responsibilities:
 * - Discovery of peers via mDNS
 * - Connection management (connect, reconnect, disconnect)
 * - CRDT sync protocol coordination
 * - Change propagation
 */
class SyncManager : public QObject {
    Q_OBJECT
    
    Q_PROPERTY(bool syncing READ isSyncing NOTIFY syncingChanged)
    Q_PROPERTY(int connectedPeerCount READ connectedPeerCount NOTIFY peersChanged)
    
public:
    explicit SyncManager(QObject* parent = nullptr);
    ~SyncManager() override;
    
    /**
     * Initialize with our identity and workspace.
     */
    void initialize(const crypto::KeyPair& identity,
                   const Uuid& workspace_id,
                   const QString& device_name,
                   const Uuid& device_id);
    
    /**
     * Start discovery and listening for connections.
     */
    Q_INVOKABLE bool start(uint16_t port = 0);
    
    /**
     * Stop all sync activity.
     */
    Q_INVOKABLE void stop();
    
    /**
     * Connect to a specific peer.
     */
    Q_INVOKABLE void connectToPeer(const Uuid& device_id);

    /**
     * Connect to a peer directly using endpoint info (e.g., from QR).
     */
    void connectToEndpoint(const Uuid& device_id,
                           const QHostAddress& host,
                           uint16_t port);
    
    /**
     * Disconnect from a peer.
     */
    Q_INVOKABLE void disconnectFromPeer(const Uuid& device_id);
    
    /**
     * Broadcast a change to all connected peers.
     */
    void broadcastChange(const std::string& doc_id, 
                        const std::vector<uint8_t>& change_bytes);
    
    /**
     * Request full sync with a peer.
     */
    void requestSync(const Uuid& device_id, const std::string& doc_id);
    
    [[nodiscard]] bool isSyncing() const { return syncing_; }
    [[nodiscard]] int connectedPeerCount() const;
    [[nodiscard]] uint16_t listeningPort() const;
    [[nodiscard]] DiscoveryService* discovery() { return discovery_.get(); }

signals:
    void syncingChanged();
    void peersChanged();
    void peerConnected(const Uuid& device_id);
    void peerDisconnected(const Uuid& device_id);
    void peerDiscovered(const PeerInfo& peer);
    void pageSnapshotReceived(const QByteArray& payload);
    void presenceReceived(const Uuid& peer_id, const QByteArray& payload);
    void changeReceived(const QString& doc_id, const QByteArray& change_bytes);
    void syncRequested(const Uuid& device_id, const QString& doc_id);
    void error(const QString& message);

private slots:
    void onPeerDiscovered(const PeerInfo& peer);
    void onPeerLost(const Uuid& device_id);
    void onNewConnection(QTcpSocket* socket);
    void onConnectionConnected();
    void onConnectionDisconnected();
    void onConnectionStateChanged(Connection::State state);
    void onMessageReceived(MessageType type, const std::vector<uint8_t>& payload);

private:
    std::unique_ptr<DiscoveryService> discovery_;
    std::unique_ptr<TransportServer> server_;
    std::map<Uuid, std::unique_ptr<PeerConnection>> peers_;
    
    crypto::KeyPair identity_;
    Uuid workspace_id_;
    Uuid device_id_;
    QString device_name_;
    
    bool syncing_ = false;
    bool started_ = false;
    bool stopping_ = false;

    // Prevent repeated auto-connect attempts on every discovery heartbeat.
    std::set<Uuid> autoconnect_attempted_;
    
    void setupConnection(PeerConnection& peer);
    void sendHello(Connection& conn) const;
    void handleHello(Connection& conn, const std::vector<uint8_t>& payload);
    void handleSyncRequest(const Uuid& peer_id, const std::vector<uint8_t>& payload);
    void handleSyncResponse(const Uuid& peer_id, const std::vector<uint8_t>& payload);
    void handleChangeNotify(const Uuid& peer_id, const std::vector<uint8_t>& payload);

public:
    void sendPageSnapshot(const std::vector<uint8_t>& payload);
    void sendPresenceUpdate(const std::vector<uint8_t>& payload);
};

} // namespace zinc::network
