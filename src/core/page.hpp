#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include <string>
#include <optional>
#include <vector>

namespace zinc {

/**
 * Page - A document containing blocks.
 * 
 * Pages are organized in a tree structure (pages can contain sub-pages).
 * Each page has its own CRDT document for real-time collaboration.
 */
struct Page {
    Uuid id;
    Uuid workspace_id;
    std::optional<Uuid> parent_page_id;  // For nested pages
    std::string title;
    int sort_order;
    bool is_archived;
    Timestamp created_at;
    Timestamp updated_at;
    std::string crdt_doc_id;  // Automerge document reference
    
    bool operator==(const Page&) const = default;
};

// ============================================================================
// Pure transformation functions
// ============================================================================

/**
 * Create a new page.
 */
[[nodiscard]] inline Page create_page(
    Uuid id,
    Uuid workspace_id,
    std::string title,
    int sort_order = 0,
    std::optional<Uuid> parent_page_id = std::nullopt
) {
    auto now = Timestamp::now();
    return Page{
        .id = id,
        .workspace_id = workspace_id,
        .parent_page_id = parent_page_id,
        .title = std::move(title),
        .sort_order = sort_order,
        .is_archived = false,
        .created_at = now,
        .updated_at = now,
        .crdt_doc_id = id.to_string()  // Use page ID as CRDT doc ID
    };
}

/**
 * Update page title.
 */
[[nodiscard]] inline Page with_title(Page page, std::string title) {
    page.title = std::move(title);
    page.updated_at = Timestamp::now();
    return page;
}

/**
 * Update page parent.
 */
[[nodiscard]] inline Page with_parent(Page page, std::optional<Uuid> parent_id) {
    page.parent_page_id = parent_id;
    page.updated_at = Timestamp::now();
    return page;
}

/**
 * Update page sort order.
 */
[[nodiscard]] inline Page with_sort_order(Page page, int sort_order) {
    page.sort_order = sort_order;
    page.updated_at = Timestamp::now();
    return page;
}

/**
 * Archive or unarchive a page.
 */
[[nodiscard]] inline Page with_archived(Page page, bool archived) {
    page.is_archived = archived;
    page.updated_at = Timestamp::now();
    return page;
}

/**
 * Get child pages of a parent page.
 */
[[nodiscard]] inline std::vector<Page> get_child_pages(
    const std::optional<Uuid>& parent_id,
    const std::vector<Page>& pages
) {
    std::vector<Page> children;
    for (const auto& page : pages) {
        if (page.parent_page_id == parent_id && !page.is_archived) {
            children.push_back(page);
        }
    }
    
    // Sort by sort_order
    std::sort(children.begin(), children.end(),
        [](const Page& a, const Page& b) {
            return a.sort_order < b.sort_order;
        });
    
    return children;
}

/**
 * Get root-level pages (those with no parent).
 */
[[nodiscard]] inline std::vector<Page> get_root_pages(
    const std::vector<Page>& pages
) {
    return get_child_pages(std::nullopt, pages);
}

/**
 * Flatten a page tree into a depth-first ordered list with depths.
 */
[[nodiscard]] inline std::vector<std::pair<Page, int>> flatten_page_tree(
    const std::vector<Page>& pages
) {
    std::vector<std::pair<Page, int>> result;
    
    std::function<void(const std::optional<Uuid>&, int)> visit = 
        [&](const std::optional<Uuid>& parent_id, int depth) {
            auto children = get_child_pages(parent_id, pages);
            for (const auto& child : children) {
                result.emplace_back(child, depth);
                visit(child.id, depth + 1);
            }
        };
    
    visit(std::nullopt, 0);
    return result;
}

} // namespace zinc

