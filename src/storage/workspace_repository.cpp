#include "storage/workspace_repository.hpp"

namespace zinc::storage {

Workspace WorkspaceRepository::row_to_workspace(Statement& stmt) {
    auto id = Uuid::parse(stmt.column_text(0)).value_or(Uuid{});
    
    return Workspace{
        .id = id,
        .name = stmt.column_text(1),
        .encryption_key_salt = stmt.column_blob(2),
        .created_at = Timestamp(stmt.column_int64(3)),
        .updated_at = Timestamp(stmt.column_int64(4))
    };
}

Device WorkspaceRepository::row_to_device(Statement& stmt) {
    auto id = Uuid::parse(stmt.column_text(0)).value_or(Uuid{});
    auto workspace_id = Uuid::parse(stmt.column_text(1)).value_or(Uuid{});
    
    return Device{
        .id = id,
        .workspace_id = workspace_id,
        .device_name = stmt.column_text(2),
        .public_key = stmt.column_blob(3),
        .paired_at = Timestamp(stmt.column_int64(4)),
        .last_seen = Timestamp(stmt.column_int64(5)),
        .is_revoked = stmt.column_int(6) != 0
    };
}

Result<std::optional<Workspace>, Error> WorkspaceRepository::get_workspace(const Uuid& id) {
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, name, encryption_key_salt, created_at, updated_at
        FROM workspaces WHERE id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::optional<Workspace>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<std::optional<Workspace>, Error>::err(step_result.unwrap_err());
    }
    
    if (!step_result.unwrap()) {
        return Result<std::optional<Workspace>, Error>::ok(std::nullopt);
    }
    
    return Result<std::optional<Workspace>, Error>::ok(row_to_workspace(stmt));
}

Result<std::vector<Workspace>, Error> WorkspaceRepository::get_all_workspaces() {
    std::vector<Workspace> workspaces;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, name, encryption_key_salt, created_at, updated_at
        FROM workspaces ORDER BY name;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<Workspace>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<Workspace>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        workspaces.push_back(row_to_workspace(stmt));
    }
    
    return Result<std::vector<Workspace>, Error>::ok(std::move(workspaces));
}

Result<void, Error> WorkspaceRepository::save_workspace(const Workspace& workspace) {
    auto stmt_result = db_.prepare(R"SQL(
        INSERT INTO workspaces (id, name, encryption_key_salt, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            encryption_key_salt = excluded.encryption_key_salt,
            updated_at = excluded.updated_at;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, workspace.id.to_string());
    stmt.bind_text(2, workspace.name);
    stmt.bind_blob(3, workspace.encryption_key_salt.data(), 
                   workspace.encryption_key_salt.size());
    stmt.bind_int64(4, workspace.created_at.millis());
    stmt.bind_int64(5, workspace.updated_at.millis());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> WorkspaceRepository::remove_workspace(const Uuid& id) {
    auto stmt_result = db_.prepare("DELETE FROM workspaces WHERE id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<std::optional<Device>, Error> WorkspaceRepository::get_device(const Uuid& id) {
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, workspace_id, device_name, public_key, paired_at, last_seen, is_revoked
        FROM devices WHERE id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::optional<Device>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<std::optional<Device>, Error>::err(step_result.unwrap_err());
    }
    
    if (!step_result.unwrap()) {
        return Result<std::optional<Device>, Error>::ok(std::nullopt);
    }
    
    return Result<std::optional<Device>, Error>::ok(row_to_device(stmt));
}

Result<std::vector<Device>, Error> WorkspaceRepository::get_devices_by_workspace(
    const Uuid& workspace_id
) {
    std::vector<Device> devices;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, workspace_id, device_name, public_key, paired_at, last_seen, is_revoked
        FROM devices WHERE workspace_id = ? ORDER BY device_name;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<Device>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, workspace_id.to_string());
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<Device>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        devices.push_back(row_to_device(stmt));
    }
    
    return Result<std::vector<Device>, Error>::ok(std::move(devices));
}

Result<std::vector<Device>, Error> WorkspaceRepository::get_active_devices(
    const Uuid& workspace_id
) {
    std::vector<Device> devices;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, workspace_id, device_name, public_key, paired_at, last_seen, is_revoked
        FROM devices WHERE workspace_id = ? AND is_revoked = 0 ORDER BY device_name;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<Device>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, workspace_id.to_string());
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<Device>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        devices.push_back(row_to_device(stmt));
    }
    
    return Result<std::vector<Device>, Error>::ok(std::move(devices));
}

Result<void, Error> WorkspaceRepository::save_device(const Device& device) {
    auto stmt_result = db_.prepare(R"SQL(
        INSERT INTO devices (id, workspace_id, device_name, public_key, paired_at, last_seen, is_revoked)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            workspace_id = excluded.workspace_id,
            device_name = excluded.device_name,
            public_key = excluded.public_key,
            last_seen = excluded.last_seen,
            is_revoked = excluded.is_revoked;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, device.id.to_string());
    stmt.bind_text(2, device.workspace_id.to_string());
    stmt.bind_text(3, device.device_name);
    stmt.bind_blob(4, device.public_key.data(), device.public_key.size());
    stmt.bind_int64(5, device.paired_at.millis());
    stmt.bind_int64(6, device.last_seen.millis());
    stmt.bind_int(7, device.is_revoked ? 1 : 0);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> WorkspaceRepository::remove_device(const Uuid& id) {
    auto stmt_result = db_.prepare("DELETE FROM devices WHERE id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> WorkspaceRepository::update_device_last_seen(
    const Uuid& id, 
    Timestamp last_seen
) {
    auto stmt_result = db_.prepare("UPDATE devices SET last_seen = ? WHERE id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_int64(1, last_seen.millis());
    stmt.bind_text(2, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> WorkspaceRepository::revoke_device(const Uuid& id) {
    auto stmt_result = db_.prepare("UPDATE devices SET is_revoked = 1 WHERE id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

} // namespace zinc::storage

