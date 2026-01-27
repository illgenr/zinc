#include <catch2/catch_test_macros.hpp>

#include "network/discovery_datagram.hpp"

#include <QHostAddress>

using namespace zinc;
using namespace zinc::network;

TEST_CASE("UDP discovery datagram: encodes/decodes service info", "[integration][network][discovery]") {
    ServiceInfo info{};
    info.device_id = Uuid::generate();
    info.workspace_id = Uuid::generate();
    info.device_name = QStringLiteral("My Device");
    info.port = 47888;
    info.public_key_fingerprint = {0x01, 0x02, 0x03, 0x04};
    info.protocol_version = 1;

    const QHostAddress sender(QStringLiteral("192.168.50.10"));
    const auto bytes = encode_discovery_datagram(info);

    const auto decoded = decode_discovery_datagram(bytes, sender);
    REQUIRE(decoded.is_ok());

    const auto peer = decoded.unwrap();
    REQUIRE(peer.device_id == info.device_id);
    REQUIRE(peer.workspace_id == info.workspace_id);
    REQUIRE(peer.device_name == info.device_name);
    REQUIRE(peer.host == sender);
    REQUIRE(peer.port == info.port);
    REQUIRE(peer.public_key_fingerprint == info.public_key_fingerprint);
    REQUIRE(peer.protocol_version == info.protocol_version);
}

TEST_CASE("UDP discovery datagram: rejects invalid json", "[integration][network][discovery]") {
    const QHostAddress sender(QStringLiteral("192.168.50.10"));
    const auto decoded = decode_discovery_datagram(QByteArray("not-json"), sender);
    REQUIRE(decoded.is_err());
}

TEST_CASE("UDP discovery datagram: rejects wrong message type", "[integration][network][discovery]") {
    const QHostAddress sender(QStringLiteral("192.168.50.10"));
    const auto decoded = decode_discovery_datagram(QByteArray("{\"t\":\"nope\"}"), sender);
    REQUIRE(decoded.is_err());
}

