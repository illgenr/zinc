#pragma once

#include "storage/database.hpp"
#include "core/workspace.hpp"
#include "core/result.hpp"
#include <vector>
#include <optional>

namespace zinc::storage {

/**
 * WorkspaceRepository - Data access layer for workspaces and devices.
 */
class WorkspaceRepository {
public:
    explicit WorkspaceRepository(Database& db) : db_(db) {}
    
    // Workspace operations
    
    [[nodiscard]] Result<std::optional<Workspace>, Error> get_workspace(const Uuid& id);
    [[nodiscard]] Result<std::vector<Workspace>, Error> get_all_workspaces();
    [[nodiscard]] Result<void, Error> save_workspace(const Workspace& workspace);
    [[nodiscard]] Result<void, Error> remove_workspace(const Uuid& id);
    
    // Device operations
    
    [[nodiscard]] Result<std::optional<Device>, Error> get_device(const Uuid& id);
    [[nodiscard]] Result<std::vector<Device>, Error> get_devices_by_workspace(const Uuid& workspace_id);
    [[nodiscard]] Result<std::vector<Device>, Error> get_active_devices(const Uuid& workspace_id);
    [[nodiscard]] Result<void, Error> save_device(const Device& device);
    [[nodiscard]] Result<void, Error> remove_device(const Uuid& id);
    [[nodiscard]] Result<void, Error> update_device_last_seen(const Uuid& id, Timestamp last_seen);
    [[nodiscard]] Result<void, Error> revoke_device(const Uuid& id);

private:
    Database& db_;
    
    [[nodiscard]] Workspace row_to_workspace(Statement& stmt);
    [[nodiscard]] Device row_to_device(Statement& stmt);
};

} // namespace zinc::storage

