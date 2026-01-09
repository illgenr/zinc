#pragma once

#include "storage/database.hpp"
#include "core/page.hpp"
#include "core/result.hpp"
#include <vector>
#include <optional>

namespace zinc::storage {

/**
 * PageRepository - Data access layer for pages.
 */
class PageRepository {
public:
    explicit PageRepository(Database& db) : db_(db) {}
    
    /**
     * Get a page by ID.
     */
    [[nodiscard]] Result<std::optional<Page>, Error> get(const Uuid& id);
    
    /**
     * Get all pages for a workspace.
     */
    [[nodiscard]] Result<std::vector<Page>, Error> get_by_workspace(const Uuid& workspace_id);
    
    /**
     * Get child pages of a parent page.
     */
    [[nodiscard]] Result<std::vector<Page>, Error> get_children(
        const Uuid& workspace_id,
        const std::optional<Uuid>& parent_id);
    
    /**
     * Get root pages (no parent) for a workspace.
     */
    [[nodiscard]] Result<std::vector<Page>, Error> get_root_pages(const Uuid& workspace_id);
    
    /**
     * Save a page (insert or update).
     */
    [[nodiscard]] Result<void, Error> save(const Page& page);
    
    /**
     * Delete a page by ID.
     */
    [[nodiscard]] Result<void, Error> remove(const Uuid& id);
    
    /**
     * Search pages by title.
     */
    [[nodiscard]] Result<std::vector<Page>, Error> search_by_title(
        const Uuid& workspace_id,
        const std::string& query);

private:
    Database& db_;
    
    [[nodiscard]] Page row_to_page(Statement& stmt);
};

} // namespace zinc::storage

