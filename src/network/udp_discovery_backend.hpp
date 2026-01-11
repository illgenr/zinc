#pragma once

#include "network/discovery.hpp"
#include <QObject>
#include <QHostAddress>
#include <memory>
#include <unordered_map>

class QUdpSocket;
class QTimer;

namespace zinc::network {

/**
 * UDP multicast/broadcast discovery backend.
 *
 * This backend is cross-platform and doesn't require Avahi/NSD.
 * It periodically advertises `ServiceInfo` and listens for peer announcements.
 */
class UdpDiscoveryBackend final : public QObject, public DiscoveryBackend {
    Q_OBJECT

public:
    explicit UdpDiscoveryBackend(QObject* parent = nullptr);
    ~UdpDiscoveryBackend() override;

    Result<void, Error> start_advertising(const ServiceInfo& info) override;
    void stop_advertising() override;

    Result<void, Error> start_browsing() override;
    void stop_browsing() override;

private slots:
    void onReadyRead();
    void onAdvertiseTick();
    void onPruneTick();

private:
    struct PeerEntry {
        PeerInfo info;
        Timestamp last_seen;
    };

    Result<void, Error> ensureSockets();
    void closeSockets();
    void announceOnce();

    std::unique_ptr<QUdpSocket> socket_;
    std::unique_ptr<QTimer> advertise_timer_;
    std::unique_ptr<QTimer> prune_timer_;

    bool advertising_ = false;
    bool browsing_ = false;
    ServiceInfo advertised_{};

    std::unordered_map<Uuid, PeerEntry> peers_;
};

} // namespace zinc::network

