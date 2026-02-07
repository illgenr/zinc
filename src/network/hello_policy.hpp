#pragma once

#include "core/types.hpp"
#include <QString>

namespace zinc::network {

enum class HelloDecisionKind {
    Accept,
    AcceptPairingBootstrap,
    DisconnectSelf,
    DisconnectIdentityMismatch,
    DisconnectWorkspaceMismatch,
};

struct HelloDecision {
    HelloDecisionKind kind = HelloDecisionKind::Accept;
    QString reason;
};

[[nodiscard]] inline HelloDecision decide_hello(const Uuid& local_device_id,
                                                const Uuid& local_workspace_id,
                                                const Uuid& expected_peer_id,
                                                bool allow_rekey_on_hello,
                                                const Uuid& remote_device_id,
                                                const Uuid& remote_workspace_id) {
    if (remote_device_id == local_device_id) {
        return {HelloDecisionKind::DisconnectSelf, QStringLiteral("Hello from self")};
    }

    if (!allow_rekey_on_hello && expected_peer_id != remote_device_id) {
        return {HelloDecisionKind::DisconnectIdentityMismatch, QStringLiteral("Peer identity mismatch")};
    }

    if (remote_workspace_id != local_workspace_id) {
        const bool pairing_bootstrap =
            allow_rekey_on_hello && (remote_workspace_id.is_nil() || local_workspace_id.is_nil());
        if (pairing_bootstrap) {
            return {HelloDecisionKind::AcceptPairingBootstrap, QStringLiteral("Pairing bootstrap allowed")};
        }
        return {HelloDecisionKind::DisconnectWorkspaceMismatch, QStringLiteral("Workspace mismatch")};
    }

    return {HelloDecisionKind::Accept, QString{}};
}

} // namespace zinc::network

