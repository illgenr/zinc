#pragma once

#include "storage/database.hpp"
#include "core/result.hpp"
#include <string>
#include <vector>
#include <functional>

namespace zinc::storage {

/**
 * Migration - A database schema migration.
 */
struct Migration {
    int version;
    std::string name;
    std::string up_sql;
    std::string down_sql;  // Optional - for rollback
};

/**
 * All migrations in order.
 */
inline const std::vector<Migration> ALL_MIGRATIONS = {
    {
        .version = 1,
        .name = "initial_schema",
        .up_sql = R"SQL(
            -- Workspaces table
            CREATE TABLE IF NOT EXISTS workspaces (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                encryption_key_salt BLOB,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            
            -- Pages table
            CREATE TABLE IF NOT EXISTS pages (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                parent_page_id TEXT REFERENCES pages(id) ON DELETE SET NULL,
                title TEXT NOT NULL DEFAULT '',
                sort_order INTEGER NOT NULL DEFAULT 0,
                is_archived INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                crdt_doc_id TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_pages_workspace ON pages(workspace_id);
            CREATE INDEX IF NOT EXISTS idx_pages_parent ON pages(parent_page_id);
            
            -- Blocks table
            CREATE TABLE IF NOT EXISTS blocks (
                id TEXT PRIMARY KEY,
                page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                parent_block_id TEXT REFERENCES blocks(id) ON DELETE SET NULL,
                block_type TEXT NOT NULL,
                content_markdown TEXT NOT NULL DEFAULT '',
                properties_json TEXT NOT NULL DEFAULT '{}',
                sort_order TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_blocks_page ON blocks(page_id);
            CREATE INDEX IF NOT EXISTS idx_blocks_parent ON blocks(parent_block_id);
            
            -- Devices table
            CREATE TABLE IF NOT EXISTS devices (
                id TEXT PRIMARY KEY,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                device_name TEXT NOT NULL,
                public_key BLOB NOT NULL,
                paired_at INTEGER NOT NULL,
                last_seen INTEGER NOT NULL,
                is_revoked INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_devices_workspace ON devices(workspace_id);
        )SQL",
        .down_sql = R"SQL(
            DROP TABLE IF EXISTS devices;
            DROP TABLE IF EXISTS blocks;
            DROP TABLE IF EXISTS pages;
            DROP TABLE IF EXISTS workspaces;
        )SQL"
    },
    {
        .version = 2,
        .name = "fts5_search",
        .up_sql = R"SQL(
            -- FTS5 virtual table for full-text search
            CREATE VIRTUAL TABLE IF NOT EXISTS block_fts USING fts5(
                block_id UNINDEXED,
                page_id UNINDEXED,
                page_title,
                content,
                tokenize='porter unicode61 remove_diacritics 2'
            );
            
            -- Trigger to insert into FTS on block insert
            CREATE TRIGGER IF NOT EXISTS blocks_ai AFTER INSERT ON blocks BEGIN
                INSERT INTO block_fts(block_id, page_id, page_title, content)
                VALUES (
                    new.id,
                    new.page_id,
                    (SELECT title FROM pages WHERE id = new.page_id),
                    new.content_markdown
                );
            END;
            
            -- Trigger to update FTS on block delete
            CREATE TRIGGER IF NOT EXISTS blocks_ad AFTER DELETE ON blocks BEGIN
                DELETE FROM block_fts WHERE block_id = old.id;
            END;
            
            -- Trigger to update FTS on block update
            CREATE TRIGGER IF NOT EXISTS blocks_au AFTER UPDATE ON blocks BEGIN
                DELETE FROM block_fts WHERE block_id = old.id;
                INSERT INTO block_fts(block_id, page_id, page_title, content)
                VALUES (
                    new.id,
                    new.page_id,
                    (SELECT title FROM pages WHERE id = new.page_id),
                    new.content_markdown
                );
            END;
            
            -- Trigger to update FTS when page title changes
            CREATE TRIGGER IF NOT EXISTS pages_au_title AFTER UPDATE OF title ON pages BEGIN
                UPDATE block_fts SET page_title = new.title WHERE page_id = new.id;
            END;
        )SQL",
        .down_sql = R"SQL(
            DROP TRIGGER IF EXISTS pages_au_title;
            DROP TRIGGER IF EXISTS blocks_au;
            DROP TRIGGER IF EXISTS blocks_ad;
            DROP TRIGGER IF EXISTS blocks_ai;
            DROP TABLE IF EXISTS block_fts;
        )SQL"
    },
    {
        .version = 3,
        .name = "block_links",
        .up_sql = R"SQL(
            -- Backlinks index for bi-directional linking
            CREATE TABLE IF NOT EXISTS block_links (
                source_block_id TEXT NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
                target_page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                target_block_id TEXT REFERENCES blocks(id) ON DELETE SET NULL,
                PRIMARY KEY (source_block_id, target_page_id, COALESCE(target_block_id, ''))
            );
            CREATE INDEX IF NOT EXISTS idx_block_links_target ON block_links(target_page_id);
            CREATE INDEX IF NOT EXISTS idx_block_links_target_block ON block_links(target_block_id);
        )SQL",
        .down_sql = R"SQL(
            DROP TABLE IF EXISTS block_links;
        )SQL"
    },
    {
        .version = 4,
        .name = "crdt_storage",
        .up_sql = R"SQL(
            -- Store Automerge document snapshots
            CREATE TABLE IF NOT EXISTS crdt_documents (
                doc_id TEXT PRIMARY KEY,
                page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
                snapshot BLOB NOT NULL,
                vector_clock TEXT NOT NULL DEFAULT '{}',
                updated_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_crdt_documents_page ON crdt_documents(page_id);
            
            -- Incremental changes for efficient sync
            CREATE TABLE IF NOT EXISTS crdt_changes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                doc_id TEXT NOT NULL REFERENCES crdt_documents(doc_id) ON DELETE CASCADE,
                change_bytes BLOB NOT NULL,
                actor_id TEXT NOT NULL,
                seq_num INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                synced_to TEXT NOT NULL DEFAULT '{}',
                UNIQUE(doc_id, actor_id, seq_num)
            );
            CREATE INDEX IF NOT EXISTS idx_crdt_changes_doc ON crdt_changes(doc_id);
            CREATE INDEX IF NOT EXISTS idx_crdt_changes_unsynced ON crdt_changes(doc_id, synced_to);
        )SQL",
        .down_sql = R"SQL(
            DROP TABLE IF EXISTS crdt_changes;
            DROP TABLE IF EXISTS crdt_documents;
        )SQL"
    },
    {
        .version = 5,
        .name = "attachments_placeholder",
        .up_sql = R"SQL(
            -- Placeholder for future attachments support
            CREATE TABLE IF NOT EXISTS attachments (
                id TEXT PRIMARY KEY,
                block_id TEXT REFERENCES blocks(id) ON DELETE SET NULL,
                filename TEXT NOT NULL,
                mime_type TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                hash_sha256 TEXT NOT NULL,
                encrypted_blob BLOB,
                external_path TEXT,
                created_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_attachments_block ON attachments(block_id);
            CREATE INDEX IF NOT EXISTS idx_attachments_hash ON attachments(hash_sha256);
        )SQL",
        .down_sql = R"SQL(
            DROP TABLE IF EXISTS attachments;
        )SQL"
    }
};

/**
 * MigrationRunner - Runs database migrations.
 */
class MigrationRunner {
public:
    explicit MigrationRunner(Database& db) : db_(db) {}
    
    /**
     * Run all pending migrations.
     */
    [[nodiscard]] Result<void, Error> migrate();
    
    /**
     * Migrate to a specific version.
     */
    [[nodiscard]] Result<void, Error> migrate_to(int target_version);
    
    /**
     * Rollback the last migration.
     */
    [[nodiscard]] Result<void, Error> rollback();
    
    /**
     * Rollback to a specific version.
     */
    [[nodiscard]] Result<void, Error> rollback_to(int target_version);
    
    /**
     * Get the current schema version.
     */
    [[nodiscard]] Result<int, Error> current_version();
    
    /**
     * Get the latest available migration version.
     */
    [[nodiscard]] static int latest_version() {
        return ALL_MIGRATIONS.empty() ? 0 : ALL_MIGRATIONS.back().version;
    }

private:
    Database& db_;
    
    [[nodiscard]] Result<void, Error> ensure_migrations_table();
    [[nodiscard]] Result<void, Error> run_migration(const Migration& m);
    [[nodiscard]] Result<void, Error> run_rollback(const Migration& m);
    [[nodiscard]] Result<void, Error> set_version(int version);
};

/**
 * Initialize a database with all migrations.
 */
[[nodiscard]] inline Result<void, Error> initialize_database(Database& db) {
    MigrationRunner runner(db);
    return runner.migrate();
}

} // namespace zinc::storage

