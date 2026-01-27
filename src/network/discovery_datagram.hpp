#pragma once

#include "core/result.hpp"
#include "network/discovery.hpp"

#include <QByteArray>
#include <QHostAddress>

namespace zinc::network {

// UDP discovery message helpers (used by UdpDiscoveryBackend).
// Kept separate so we can unit/integration test encode/decode without sockets.

QByteArray encode_discovery_datagram(const ServiceInfo& info);

Result<PeerInfo, Error> decode_discovery_datagram(const QByteArray& datagram,
                                                  const QHostAddress& sender);

} // namespace zinc::network

