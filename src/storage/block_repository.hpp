#pragma once

#include "storage/database.hpp"
#include "core/block_types.hpp"
#include "core/result.hpp"
#include <vector>
#include <optional>

namespace zinc::storage {

/**
 * BlockRepository - Data access layer for blocks.
 * 
 * Provides CRUD operations for blocks with SQLite persistence.
 * All operations return Results for error handling.
 */
class BlockRepository {
public:
    explicit BlockRepository(Database& db) : db_(db) {}
    
    /**
     * Get a block by ID.
     */
    [[nodiscard]] Result<std::optional<blocks::Block>, Error> get(const Uuid& id);
    
    /**
     * Get all blocks for a page.
     */
    [[nodiscard]] Result<std::vector<blocks::Block>, Error> get_by_page(const Uuid& page_id);
    
    /**
     * Get child blocks of a parent block.
     */
    [[nodiscard]] Result<std::vector<blocks::Block>, Error> get_children(
        const Uuid& parent_id);
    
    /**
     * Get root blocks (no parent) for a page.
     */
    [[nodiscard]] Result<std::vector<blocks::Block>, Error> get_root_blocks(
        const Uuid& page_id);
    
    /**
     * Save a block (insert or update).
     */
    [[nodiscard]] Result<void, Error> save(const blocks::Block& block);
    
    /**
     * Save multiple blocks in a transaction.
     */
    [[nodiscard]] Result<void, Error> save_all(const std::vector<blocks::Block>& blocks);
    
    /**
     * Delete a block by ID.
     */
    [[nodiscard]] Result<void, Error> remove(const Uuid& id);
    
    /**
     * Delete all blocks for a page.
     */
    [[nodiscard]] Result<void, Error> remove_by_page(const Uuid& page_id);
    
    /**
     * Count blocks in a page.
     */
    [[nodiscard]] Result<int, Error> count_by_page(const Uuid& page_id);

private:
    Database& db_;
    
    /**
     * Convert a database row to a Block.
     */
    [[nodiscard]] blocks::Block row_to_block(Statement& stmt);
    
    /**
     * Convert BlockContent to type string and JSON properties.
     */
    [[nodiscard]] std::pair<std::string, std::string> content_to_db(
        const blocks::BlockContent& content);
    
    /**
     * Convert type string and JSON properties to BlockContent.
     */
    [[nodiscard]] blocks::BlockContent db_to_content(
        const std::string& type,
        const std::string& markdown,
        const std::string& props_json);
};

} // namespace zinc::storage

