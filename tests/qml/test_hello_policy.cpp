#include <catch2/catch_test_macros.hpp>

#include "core/types.hpp"
#include "network/hello_policy.hpp"

using zinc::Uuid;
using zinc::network::HelloDecisionKind;
using zinc::network::decide_hello;

TEST_CASE("HelloPolicy: disconnect self", "[qml][sync]") {
    const auto deviceId = Uuid::generate();
    const auto wsId = Uuid::generate();
    const auto decision = decide_hello(deviceId, wsId, Uuid::generate(), false, deviceId, wsId);
    REQUIRE(decision.kind == HelloDecisionKind::DisconnectSelf);
}

TEST_CASE("HelloPolicy: identity mismatch for expected peer", "[qml][sync]") {
    const auto localDeviceId = Uuid::generate();
    const auto localWsId = Uuid::generate();
    const auto expectedPeerId = Uuid::generate();
    const auto remotePeerId = Uuid::generate();
    const auto decision = decide_hello(localDeviceId, localWsId, expectedPeerId, false, remotePeerId, localWsId);
    REQUIRE(decision.kind == HelloDecisionKind::DisconnectIdentityMismatch);
}

TEST_CASE("HelloPolicy: workspace mismatch for expected peer even when remote ws nil", "[qml][sync]") {
    const auto localDeviceId = Uuid::generate();
    const auto localWsId = Uuid::generate();
    const auto expectedPeerId = Uuid::generate();
    const auto decision = decide_hello(localDeviceId, localWsId, expectedPeerId, false, expectedPeerId, Uuid{});
    REQUIRE(decision.kind == HelloDecisionKind::DisconnectWorkspaceMismatch);
}

TEST_CASE("HelloPolicy: allow pairing bootstrap when rekey is allowed", "[qml][sync]") {
    const auto localDeviceId = Uuid::generate();
    const auto localWsId = Uuid::generate();
    const auto placeholderId = Uuid::generate();
    const auto remoteId = Uuid::generate();
    const auto decision = decide_hello(localDeviceId, localWsId, placeholderId, true, remoteId, Uuid{});
    REQUIRE(decision.kind == HelloDecisionKind::AcceptPairingBootstrap);
}

