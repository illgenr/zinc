#include "storage/page_repository.hpp"

namespace zinc::storage {

Page PageRepository::row_to_page(Statement& stmt) {
    auto id = Uuid::parse(stmt.column_text(0)).value_or(Uuid{});
    auto workspace_id = Uuid::parse(stmt.column_text(1)).value_or(Uuid{});
    
    std::optional<Uuid> parent_page_id;
    if (!stmt.column_is_null(2)) {
        parent_page_id = Uuid::parse(stmt.column_text(2));
    }
    
    return Page{
        .id = id,
        .workspace_id = workspace_id,
        .parent_page_id = parent_page_id,
        .title = stmt.column_text(3),
        .sort_order = stmt.column_int(4),
        .is_archived = stmt.column_int(5) != 0,
        .created_at = Timestamp(stmt.column_int64(6)),
        .updated_at = Timestamp(stmt.column_int64(7)),
        .crdt_doc_id = stmt.column_text(8)
    };
}

Result<std::optional<Page>, Error> PageRepository::get(const Uuid& id) {
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, workspace_id, parent_page_id, title, sort_order,
               is_archived, created_at, updated_at, crdt_doc_id
        FROM pages WHERE id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::optional<Page>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<std::optional<Page>, Error>::err(step_result.unwrap_err());
    }
    
    if (!step_result.unwrap()) {
        return Result<std::optional<Page>, Error>::ok(std::nullopt);
    }
    
    return Result<std::optional<Page>, Error>::ok(row_to_page(stmt));
}

Result<std::vector<Page>, Error> PageRepository::get_by_workspace(const Uuid& workspace_id) {
    std::vector<Page> pages;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, workspace_id, parent_page_id, title, sort_order,
               is_archived, created_at, updated_at, crdt_doc_id
        FROM pages WHERE workspace_id = ? ORDER BY sort_order;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<Page>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, workspace_id.to_string());
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<Page>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        pages.push_back(row_to_page(stmt));
    }
    
    return Result<std::vector<Page>, Error>::ok(std::move(pages));
}

Result<std::vector<Page>, Error> PageRepository::get_children(
    const Uuid& workspace_id,
    const std::optional<Uuid>& parent_id
) {
    std::vector<Page> pages;
    
    std::string sql = R"SQL(
        SELECT id, workspace_id, parent_page_id, title, sort_order,
               is_archived, created_at, updated_at, crdt_doc_id
        FROM pages WHERE workspace_id = ? AND )SQL";
    
    if (parent_id) {
        sql += "parent_page_id = ?";
    } else {
        sql += "parent_page_id IS NULL";
    }
    sql += " AND is_archived = 0 ORDER BY sort_order;";
    
    auto stmt_result = db_.prepare(sql);
    if (stmt_result.is_err()) {
        return Result<std::vector<Page>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, workspace_id.to_string());
    
    if (parent_id) {
        stmt.bind_text(2, parent_id->to_string());
    }
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<Page>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        pages.push_back(row_to_page(stmt));
    }
    
    return Result<std::vector<Page>, Error>::ok(std::move(pages));
}

Result<std::vector<Page>, Error> PageRepository::get_root_pages(const Uuid& workspace_id) {
    return get_children(workspace_id, std::nullopt);
}

Result<void, Error> PageRepository::save(const Page& page) {
    auto stmt_result = db_.prepare(R"SQL(
        INSERT INTO pages (id, workspace_id, parent_page_id, title, sort_order,
                          is_archived, created_at, updated_at, crdt_doc_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            workspace_id = excluded.workspace_id,
            parent_page_id = excluded.parent_page_id,
            title = excluded.title,
            sort_order = excluded.sort_order,
            is_archived = excluded.is_archived,
            updated_at = excluded.updated_at,
            crdt_doc_id = excluded.crdt_doc_id;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, page.id.to_string());
    stmt.bind_text(2, page.workspace_id.to_string());
    
    if (page.parent_page_id) {
        stmt.bind_text(3, page.parent_page_id->to_string());
    } else {
        stmt.bind_null(3);
    }
    
    stmt.bind_text(4, page.title);
    stmt.bind_int(5, page.sort_order);
    stmt.bind_int(6, page.is_archived ? 1 : 0);
    stmt.bind_int64(7, page.created_at.millis());
    stmt.bind_int64(8, page.updated_at.millis());
    stmt.bind_text(9, page.crdt_doc_id);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> PageRepository::remove(const Uuid& id) {
    auto stmt_result = db_.prepare("DELETE FROM pages WHERE id = ?;");
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

Result<std::vector<Page>, Error> PageRepository::search_by_title(
    const Uuid& workspace_id,
    const std::string& query
) {
    std::vector<Page> pages;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, workspace_id, parent_page_id, title, sort_order,
               is_archived, created_at, updated_at, crdt_doc_id
        FROM pages 
        WHERE workspace_id = ? AND title LIKE ? AND is_archived = 0
        ORDER BY title;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<Page>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, workspace_id.to_string());
    stmt.bind_text(2, "%" + query + "%");
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<Page>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        pages.push_back(row_to_page(stmt));
    }
    
    return Result<std::vector<Page>, Error>::ok(std::move(pages));
}

} // namespace zinc::storage

