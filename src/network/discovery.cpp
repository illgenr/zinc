#include "network/discovery.hpp"
#include "network/udp_discovery_backend.hpp"
#include <QDebug>
#include <QProcessEnvironment>

namespace zinc::network {

DiscoveryService::DiscoveryService(QObject* parent)
    : QObject(parent)
    , backend_(createDiscoveryBackend())
{
    if (backend_) {
        backend_->on_peer_discovered = [this](PeerInfo peer) {
            handlePeerDiscovered(std::move(peer));
        };
        backend_->on_peer_lost = [this](Uuid device_id) {
            handlePeerLost(device_id);
        };
        backend_->on_peer_updated = [this](PeerInfo peer) {
            handlePeerUpdated(std::move(peer));
        };
    }
}

DiscoveryService::~DiscoveryService() {
    stopAdvertising();
    stopBrowsing();
}

bool DiscoveryService::startAdvertising(const ServiceInfo& info) {
    if (!backend_) {
        emit error("Discovery backend not available");
        return false;
    }
    
    auto result = backend_->start_advertising(info);
    if (result.is_err()) {
        emit error(QString::fromStdString(result.unwrap_err().message));
        return false;
    }
    
    advertising_ = true;
    emit advertisingChanged();
    return true;
}

void DiscoveryService::stopAdvertising() {
    if (backend_ && advertising_) {
        backend_->stop_advertising();
        advertising_ = false;
        emit advertisingChanged();
    }
}

bool DiscoveryService::startBrowsing() {
    if (!backend_) {
        emit error("Discovery backend not available");
        return false;
    }
    
    auto result = backend_->start_browsing();
    if (result.is_err()) {
        emit error(QString::fromStdString(result.unwrap_err().message));
        return false;
    }
    
    browsing_ = true;
    emit browsingChanged();
    return true;
}

void DiscoveryService::stopBrowsing() {
    if (backend_ && browsing_) {
        backend_->stop_browsing();
        browsing_ = false;
        peers_.clear();
        emit browsingChanged();
        emit peersChanged();
    }
}

std::vector<PeerInfo> DiscoveryService::peers() const {
    return peers_;
}

std::optional<PeerInfo> DiscoveryService::peer(const Uuid& device_id) const {
    auto it = std::find_if(peers_.begin(), peers_.end(),
        [&](const PeerInfo& p) { return p.device_id == device_id; });
    
    if (it != peers_.end()) {
        return *it;
    }
    return std::nullopt;
}

void DiscoveryService::handlePeerDiscovered(PeerInfo peer) {
    // Check if we already have this peer
    auto it = std::find_if(peers_.begin(), peers_.end(),
        [&](const PeerInfo& p) { return p.device_id == peer.device_id; });
    
    if (it == peers_.end()) {
        peers_.push_back(peer);
        emit peerDiscovered(peer);
        emit peersChanged();
    }
}

void DiscoveryService::handlePeerLost(Uuid device_id) {
    auto it = std::find_if(peers_.begin(), peers_.end(),
        [&](const PeerInfo& p) { return p.device_id == device_id; });
    
    if (it != peers_.end()) {
        peers_.erase(it);
        emit peerLost(device_id);
        emit peersChanged();
    }
}

void DiscoveryService::handlePeerUpdated(PeerInfo peer) {
    auto it = std::find_if(peers_.begin(), peers_.end(),
        [&](const PeerInfo& p) { return p.device_id == peer.device_id; });
    
    if (it != peers_.end()) {
        *it = peer;
        emit peerUpdated(peer);
    }
}

// Fallback backend for platforms without native mDNS support
class FallbackDiscoveryBackend : public DiscoveryBackend {
public:
    Result<void, Error> start_advertising(const ServiceInfo&) override {
        return Result<void, Error>::err(
            Error{"mDNS not available on this platform"});
    }
    
    void stop_advertising() override {}
    
    Result<void, Error> start_browsing() override {
        return Result<void, Error>::err(
            Error{"mDNS not available on this platform"});
    }
    
    void stop_browsing() override {}
};

std::unique_ptr<DiscoveryBackend> createDiscoveryBackend() {
#if QT_CONFIG(processenvironment)
    const auto backend = qEnvironmentVariable("ZINC_DISCOVERY_BACKEND").trimmed().toLower();
    if (backend == "udp") {
        return std::make_unique<UdpDiscoveryBackend>();
    }
#endif

#ifdef Q_OS_ANDROID
    // Prefer UDP to avoid platform-specific Java/JNI glue.
    return std::make_unique<UdpDiscoveryBackend>();
#elif defined(ZINC_HAS_AVAHI)
    // Allow forcing UDP even when Avahi is available.
#if QT_CONFIG(processenvironment)
    if (backend == "mdns") {
        extern std::unique_ptr<DiscoveryBackend> createAvahiBackend();
        return createAvahiBackend();
    }
#endif
    // Will be implemented in platform/linux/avahi_discovery.cpp
    extern std::unique_ptr<DiscoveryBackend> createAvahiBackend();
    return createAvahiBackend();
#else
    return std::make_unique<UdpDiscoveryBackend>();
#endif
}

} // namespace zinc::network
