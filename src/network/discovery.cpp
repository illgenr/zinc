#include "network/discovery.hpp"
#include <QDebug>

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
#ifdef Q_OS_ANDROID
    // Implemented in platform/android/nsd_discovery.cpp
    extern std::unique_ptr<DiscoveryBackend> createNsdBackend();
    return createNsdBackend();
#elif defined(ZINC_HAS_AVAHI)
    // Will be implemented in platform/linux/avahi_discovery.cpp
    extern std::unique_ptr<DiscoveryBackend> createAvahiBackend();
    return createAvahiBackend();
#else
    return std::make_unique<FallbackDiscoveryBackend>();
#endif
}

} // namespace zinc::network
