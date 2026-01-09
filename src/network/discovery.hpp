#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include <QObject>
#include <QString>
#include <QHostAddress>
#include <vector>
#include <memory>

namespace zinc::network {

/**
 * PeerInfo - Information about a discovered peer.
 */
struct PeerInfo {
    Uuid device_id;
    QString device_name;
    QHostAddress host;
    uint16_t port;
    std::vector<uint8_t> public_key_fingerprint;
    Timestamp last_seen;
    Uuid workspace_id;
    int protocol_version;
    
    bool operator==(const PeerInfo& other) const {
        return device_id == other.device_id;
    }
};

/**
 * ServiceInfo - Information for advertising our service.
 */
struct ServiceInfo {
    Uuid device_id;
    QString device_name;
    uint16_t port;
    std::vector<uint8_t> public_key_fingerprint;
    Uuid workspace_id;
    int protocol_version;
};

/**
 * DiscoveryBackend - Abstract interface for platform-specific mDNS.
 */
class DiscoveryBackend {
public:
    virtual ~DiscoveryBackend() = default;
    
    virtual Result<void, Error> start_advertising(const ServiceInfo& info) = 0;
    virtual void stop_advertising() = 0;
    
    virtual Result<void, Error> start_browsing() = 0;
    virtual void stop_browsing() = 0;
    
    // Callbacks
    std::function<void(PeerInfo)> on_peer_discovered;
    std::function<void(Uuid)> on_peer_lost;
    std::function<void(PeerInfo)> on_peer_updated;
};

/**
 * DiscoveryService - Service discovery for LAN peers using mDNS/DNS-SD.
 * 
 * Uses platform-specific backends:
 * - Linux: Avahi via D-Bus
 * - Android: NsdManager via JNI
 * 
 * DNS-SD service type: _zinc-sync._tcp
 * 
 * TXT records:
 * - v=<protocol_version>
 * - id=<device_uuid>
 * - pk=<base64_public_key_fingerprint>
 * - ws=<workspace_uuid>
 */
class DiscoveryService : public QObject {
    Q_OBJECT
    
    Q_PROPERTY(bool advertising READ isAdvertising NOTIFY advertisingChanged)
    Q_PROPERTY(bool browsing READ isBrowsing NOTIFY browsingChanged)
    Q_PROPERTY(int peerCount READ peerCount NOTIFY peersChanged)
    
public:
    static constexpr const char* SERVICE_TYPE = "_zinc-sync._tcp";
    static constexpr int PROTOCOL_VERSION = 1;
    
    explicit DiscoveryService(QObject* parent = nullptr);
    ~DiscoveryService() override;
    
    /**
     * Start advertising our service.
     */
    Q_INVOKABLE bool startAdvertising(const ServiceInfo& info);
    
    /**
     * Stop advertising.
     */
    Q_INVOKABLE void stopAdvertising();
    
    /**
     * Start browsing for peers.
     */
    Q_INVOKABLE bool startBrowsing();
    
    /**
     * Stop browsing.
     */
    Q_INVOKABLE void stopBrowsing();
    
    /**
     * Get all discovered peers.
     */
    [[nodiscard]] std::vector<PeerInfo> peers() const;
    
    /**
     * Get a specific peer by device ID.
     */
    [[nodiscard]] std::optional<PeerInfo> peer(const Uuid& device_id) const;
    
    [[nodiscard]] bool isAdvertising() const { return advertising_; }
    [[nodiscard]] bool isBrowsing() const { return browsing_; }
    [[nodiscard]] int peerCount() const { return static_cast<int>(peers_.size()); }

signals:
    void peerDiscovered(const PeerInfo& peer);
    void peerLost(const Uuid& device_id);
    void peerUpdated(const PeerInfo& peer);
    void advertisingChanged();
    void browsingChanged();
    void peersChanged();
    void error(const QString& message);

private:
    std::unique_ptr<DiscoveryBackend> backend_;
    std::vector<PeerInfo> peers_;
    bool advertising_ = false;
    bool browsing_ = false;
    
    void handlePeerDiscovered(PeerInfo peer);
    void handlePeerLost(Uuid device_id);
    void handlePeerUpdated(PeerInfo peer);
};

/**
 * Create the platform-appropriate discovery backend.
 */
std::unique_ptr<DiscoveryBackend> createDiscoveryBackend();

} // namespace zinc::network

// Register metatypes for Qt signals
Q_DECLARE_METATYPE(zinc::network::PeerInfo)

