#include "storage/migrations.hpp"

namespace zinc::storage {

Result<void, Error> MigrationRunner::ensure_migrations_table() {
    return db_.execute(R"SQL(
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            applied_at INTEGER NOT NULL
        );
    )SQL");
}

Result<int, Error> MigrationRunner::current_version() {
    auto ensure_result = ensure_migrations_table();
    if (ensure_result.is_err()) {
        return Result<int, Error>::err(ensure_result.unwrap_err());
    }
    
    auto stmt_result = db_.prepare(
        "SELECT COALESCE(MAX(version), 0) FROM schema_migrations;");
    if (stmt_result.is_err()) {
        return Result<int, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<int, Error>::err(step_result.unwrap_err());
    }
    
    return Result<int, Error>::ok(stmt.column_int(0));
}

Result<void, Error> MigrationRunner::set_version(int version) {
    auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    
    // Find migration name
    std::string name = "unknown";
    for (const auto& m : ALL_MIGRATIONS) {
        if (m.version == version) {
            name = m.name;
            break;
        }
    }
    
    auto stmt_result = db_.prepare(
        "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_int(1, version);
    stmt.bind_text(2, name);
    stmt.bind_int64(3, now);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> MigrationRunner::run_migration(const Migration& m) {
    auto exec_result = db_.execute(m.up_sql);
    if (exec_result.is_err()) {
        return Result<void, Error>::err(Error{
            "Migration " + std::to_string(m.version) + " (" + m.name + ") failed: " +
            exec_result.unwrap_err().message
        });
    }
    
    return set_version(m.version);
}

Result<void, Error> MigrationRunner::run_rollback(const Migration& m) {
    if (m.down_sql.empty()) {
        return Result<void, Error>::err(Error{
            "Migration " + std::to_string(m.version) + " has no rollback SQL"
        });
    }
    
    auto exec_result = db_.execute(m.down_sql);
    if (exec_result.is_err()) {
        return Result<void, Error>::err(Error{
            "Rollback of migration " + std::to_string(m.version) + " failed: " +
            exec_result.unwrap_err().message
        });
    }
    
    // Remove from migrations table
    auto delete_result = db_.execute(
        "DELETE FROM schema_migrations WHERE version = " + 
        std::to_string(m.version) + ";");
    if (delete_result.is_err()) {
        return Result<void, Error>::err(delete_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> MigrationRunner::migrate() {
    return migrate_to(latest_version());
}

Result<void, Error> MigrationRunner::migrate_to(int target_version) {
    auto current_result = current_version();
    if (current_result.is_err()) {
        return Result<void, Error>::err(current_result.unwrap_err());
    }
    
    int current = current_result.unwrap();
    
    if (current >= target_version) {
        return Result<void, Error>::ok();  // Already at or past target
    }
    
    // Run migrations in a transaction
    return db_.transaction([&]() -> Result<void, Error> {
        for (const auto& m : ALL_MIGRATIONS) {
            if (m.version > current && m.version <= target_version) {
                auto result = run_migration(m);
                if (result.is_err()) {
                    return result;
                }
            }
        }
        return Result<void, Error>::ok();
    });
}

Result<void, Error> MigrationRunner::rollback() {
    auto current_result = current_version();
    if (current_result.is_err()) {
        return Result<void, Error>::err(current_result.unwrap_err());
    }
    
    int current = current_result.unwrap();
    if (current == 0) {
        return Result<void, Error>::ok();  // Nothing to rollback
    }
    
    return rollback_to(current - 1);
}

Result<void, Error> MigrationRunner::rollback_to(int target_version) {
    auto current_result = current_version();
    if (current_result.is_err()) {
        return Result<void, Error>::err(current_result.unwrap_err());
    }
    
    int current = current_result.unwrap();
    
    if (current <= target_version) {
        return Result<void, Error>::ok();  // Already at or before target
    }
    
    // Run rollbacks in reverse order in a transaction
    return db_.transaction([&]() -> Result<void, Error> {
        for (auto it = ALL_MIGRATIONS.rbegin(); it != ALL_MIGRATIONS.rend(); ++it) {
            if (it->version <= current && it->version > target_version) {
                auto result = run_rollback(*it);
                if (result.is_err()) {
                    return result;
                }
            }
        }
        return Result<void, Error>::ok();
    });
}

} // namespace zinc::storage

