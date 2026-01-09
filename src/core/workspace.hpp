#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include <string>
#include <vector>

namespace zinc {

/**
 * Workspace - A collection of pages that can be synced.
 * 
 * A workspace represents a single collaborative space. Users can have
 * multiple workspaces, each with its own set of paired devices and
 * encryption keys.
 */
struct Workspace {
    Uuid id;
    std::string name;
    std::vector<uint8_t> encryption_key_salt;  // For key derivation
    Timestamp created_at;
    Timestamp updated_at;
    
    bool operator==(const Workspace&) const = default;
};

/**
 * Device - A paired device in a workspace.
 * 
 * Tracks devices that have been authorized to sync with this workspace.
 */
struct Device {
    Uuid id;
    Uuid workspace_id;
    std::string device_name;
    std::vector<uint8_t> public_key;
    Timestamp paired_at;
    Timestamp last_seen;
    bool is_revoked;
    
    bool operator==(const Device&) const = default;
};

// ============================================================================
// Pure transformation functions
// ============================================================================

/**
 * Create a new workspace.
 */
[[nodiscard]] inline Workspace create_workspace(
    Uuid id,
    std::string name,
    std::vector<uint8_t> encryption_key_salt = {}
) {
    auto now = Timestamp::now();
    return Workspace{
        .id = id,
        .name = std::move(name),
        .encryption_key_salt = std::move(encryption_key_salt),
        .created_at = now,
        .updated_at = now
    };
}

/**
 * Update workspace name.
 */
[[nodiscard]] inline Workspace with_name(Workspace ws, std::string name) {
    ws.name = std::move(name);
    ws.updated_at = Timestamp::now();
    return ws;
}

/**
 * Create a new device entry.
 */
[[nodiscard]] inline Device create_device(
    Uuid id,
    Uuid workspace_id,
    std::string device_name,
    std::vector<uint8_t> public_key
) {
    auto now = Timestamp::now();
    return Device{
        .id = id,
        .workspace_id = workspace_id,
        .device_name = std::move(device_name),
        .public_key = std::move(public_key),
        .paired_at = now,
        .last_seen = now,
        .is_revoked = false
    };
}

/**
 * Update device last seen time.
 */
[[nodiscard]] inline Device with_last_seen(Device device, Timestamp last_seen) {
    device.last_seen = last_seen;
    return device;
}

/**
 * Revoke a device.
 */
[[nodiscard]] inline Device with_revoked(Device device, bool revoked) {
    device.is_revoked = revoked;
    return device;
}

/**
 * Get active (non-revoked) devices for a workspace.
 */
[[nodiscard]] inline std::vector<Device> get_active_devices(
    const std::vector<Device>& devices
) {
    std::vector<Device> active;
    for (const auto& device : devices) {
        if (!device.is_revoked) {
            active.push_back(device);
        }
    }
    return active;
}

} // namespace zinc

