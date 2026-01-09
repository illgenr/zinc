#include "storage/block_repository.hpp"
#include <sstream>

namespace zinc::storage {

namespace {

// Simple JSON helpers (avoiding external dependency for MVP)
std::string escape_json_string(const std::string& s) {
    std::ostringstream oss;
    for (char c : s) {
        switch (c) {
            case '"': oss << "\\\""; break;
            case '\\': oss << "\\\\"; break;
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            case '\t': oss << "\\t"; break;
            default: oss << c;
        }
    }
    return oss.str();
}

std::string get_json_string(const std::string& json, const std::string& key) {
    // Very simple JSON string extraction - production code should use a proper parser
    auto key_pos = json.find("\"" + key + "\"");
    if (key_pos == std::string::npos) return "";
    
    auto colon_pos = json.find(':', key_pos);
    if (colon_pos == std::string::npos) return "";
    
    auto quote_start = json.find('"', colon_pos);
    if (quote_start == std::string::npos) return "";
    
    auto quote_end = json.find('"', quote_start + 1);
    if (quote_end == std::string::npos) return "";
    
    return json.substr(quote_start + 1, quote_end - quote_start - 1);
}

bool get_json_bool(const std::string& json, const std::string& key, bool default_val = false) {
    auto key_pos = json.find("\"" + key + "\"");
    if (key_pos == std::string::npos) return default_val;
    
    auto colon_pos = json.find(':', key_pos);
    if (colon_pos == std::string::npos) return default_val;
    
    auto value_start = json.find_first_not_of(" \t\n\r", colon_pos + 1);
    if (value_start == std::string::npos) return default_val;
    
    if (json.substr(value_start, 4) == "true") return true;
    if (json.substr(value_start, 5) == "false") return false;
    return default_val;
}

int get_json_int(const std::string& json, const std::string& key, int default_val = 0) {
    auto key_pos = json.find("\"" + key + "\"");
    if (key_pos == std::string::npos) return default_val;
    
    auto colon_pos = json.find(':', key_pos);
    if (colon_pos == std::string::npos) return default_val;
    
    auto value_start = json.find_first_not_of(" \t\n\r", colon_pos + 1);
    if (value_start == std::string::npos) return default_val;
    
    try {
        return std::stoi(json.substr(value_start));
    } catch (...) {
        return default_val;
    }
}

} // anonymous namespace

blocks::Block BlockRepository::row_to_block(Statement& stmt) {
    auto id = Uuid::parse(stmt.column_text(0)).value_or(Uuid{});
    auto page_id = Uuid::parse(stmt.column_text(1)).value_or(Uuid{});
    
    std::optional<Uuid> parent_id;
    if (!stmt.column_is_null(2)) {
        parent_id = Uuid::parse(stmt.column_text(2));
    }
    
    auto type = stmt.column_text(3);
    auto markdown = stmt.column_text(4);
    auto props_json = stmt.column_text(5);
    auto sort_order = FractionalIndex(stmt.column_text(6));
    auto created_at = Timestamp(stmt.column_int64(7));
    auto updated_at = Timestamp(stmt.column_int64(8));
    
    return blocks::Block{
        .id = id,
        .page_id = page_id,
        .parent_id = parent_id,
        .content = db_to_content(type, markdown, props_json),
        .sort_order = sort_order,
        .created_at = created_at,
        .updated_at = updated_at
    };
}

std::pair<std::string, std::string> BlockRepository::content_to_db(
    const blocks::BlockContent& content
) {
    return std::visit([](const auto& c) -> std::pair<std::string, std::string> {
        using T = std::decay_t<decltype(c)>;
        
        if constexpr (std::is_same_v<T, blocks::Paragraph>) {
            return {"paragraph", "{}"};
        } else if constexpr (std::is_same_v<T, blocks::Heading>) {
            return {"heading", "{\"level\":" + std::to_string(c.level) + "}"};
        } else if constexpr (std::is_same_v<T, blocks::Todo>) {
            return {"todo", std::string("{\"checked\":") + (c.checked ? "true" : "false") + "}"};
        } else if constexpr (std::is_same_v<T, blocks::Code>) {
            return {"code", "{\"language\":\"" + escape_json_string(c.language) + "\"}"};
        } else if constexpr (std::is_same_v<T, blocks::Quote>) {
            return {"quote", "{}"};
        } else if constexpr (std::is_same_v<T, blocks::Divider>) {
            return {"divider", "{}"};
        } else if constexpr (std::is_same_v<T, blocks::Toggle>) {
            return {"toggle", std::string("{\"collapsed\":") + (c.collapsed ? "true" : "false") + "}"};
        }
    }, content);
}

blocks::BlockContent BlockRepository::db_to_content(
    const std::string& type,
    const std::string& markdown,
    const std::string& props_json
) {
    if (type == "paragraph") {
        return blocks::Paragraph{markdown};
    } else if (type == "heading") {
        int level = get_json_int(props_json, "level", 1);
        return blocks::Heading{level, markdown};
    } else if (type == "todo") {
        bool checked = get_json_bool(props_json, "checked", false);
        return blocks::Todo{checked, markdown};
    } else if (type == "code") {
        std::string language = get_json_string(props_json, "language");
        return blocks::Code{language, markdown};
    } else if (type == "quote") {
        return blocks::Quote{markdown};
    } else if (type == "divider") {
        return blocks::Divider{};
    } else if (type == "toggle") {
        bool collapsed = get_json_bool(props_json, "collapsed", true);
        return blocks::Toggle{collapsed, markdown};
    }
    
    // Default to paragraph
    return blocks::Paragraph{markdown};
}

Result<std::optional<blocks::Block>, Error> BlockRepository::get(const Uuid& id) {
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, page_id, parent_block_id, block_type, content_markdown,
               properties_json, sort_order, created_at, updated_at
        FROM blocks WHERE id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::optional<blocks::Block>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<std::optional<blocks::Block>, Error>::err(step_result.unwrap_err());
    }
    
    if (!step_result.unwrap()) {
        return Result<std::optional<blocks::Block>, Error>::ok(std::nullopt);
    }
    
    return Result<std::optional<blocks::Block>, Error>::ok(row_to_block(stmt));
}

Result<std::vector<blocks::Block>, Error> BlockRepository::get_by_page(const Uuid& page_id) {
    std::vector<blocks::Block> blocks;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, page_id, parent_block_id, block_type, content_markdown,
               properties_json, sort_order, created_at, updated_at
        FROM blocks WHERE page_id = ? ORDER BY sort_order;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<blocks::Block>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, page_id.to_string());
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<blocks::Block>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        blocks.push_back(row_to_block(stmt));
    }
    
    return Result<std::vector<blocks::Block>, Error>::ok(std::move(blocks));
}

Result<std::vector<blocks::Block>, Error> BlockRepository::get_children(const Uuid& parent_id) {
    std::vector<blocks::Block> blocks;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, page_id, parent_block_id, block_type, content_markdown,
               properties_json, sort_order, created_at, updated_at
        FROM blocks WHERE parent_block_id = ? ORDER BY sort_order;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<blocks::Block>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, parent_id.to_string());
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<blocks::Block>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        blocks.push_back(row_to_block(stmt));
    }
    
    return Result<std::vector<blocks::Block>, Error>::ok(std::move(blocks));
}

Result<std::vector<blocks::Block>, Error> BlockRepository::get_root_blocks(const Uuid& page_id) {
    std::vector<blocks::Block> blocks;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, page_id, parent_block_id, block_type, content_markdown,
               properties_json, sort_order, created_at, updated_at
        FROM blocks WHERE page_id = ? AND parent_block_id IS NULL ORDER BY sort_order;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<blocks::Block>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, page_id.to_string());
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<blocks::Block>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        blocks.push_back(row_to_block(stmt));
    }
    
    return Result<std::vector<blocks::Block>, Error>::ok(std::move(blocks));
}

Result<void, Error> BlockRepository::save(const blocks::Block& block) {
    auto [type, props_json] = content_to_db(block.content);
    auto markdown = blocks::get_text(block.content);
    
    auto stmt_result = db_.prepare(R"SQL(
        INSERT INTO blocks (id, page_id, parent_block_id, block_type, content_markdown,
                           properties_json, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            page_id = excluded.page_id,
            parent_block_id = excluded.parent_block_id,
            block_type = excluded.block_type,
            content_markdown = excluded.content_markdown,
            properties_json = excluded.properties_json,
            sort_order = excluded.sort_order,
            updated_at = excluded.updated_at;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, block.id.to_string());
    stmt.bind_text(2, block.page_id.to_string());
    
    if (block.parent_id) {
        stmt.bind_text(3, block.parent_id->to_string());
    } else {
        stmt.bind_null(3);
    }
    
    stmt.bind_text(4, type);
    stmt.bind_text(5, markdown);
    stmt.bind_text(6, props_json);
    stmt.bind_text(7, block.sort_order.value());
    stmt.bind_int64(8, block.created_at.millis());
    stmt.bind_int64(9, block.updated_at.millis());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> BlockRepository::save_all(const std::vector<blocks::Block>& blocks) {
    return db_.transaction([&]() -> Result<void, Error> {
        for (const auto& block : blocks) {
            auto result = save(block);
            if (result.is_err()) {
                return result;
            }
        }
        return Result<void, Error>::ok();
    });
}

Result<void, Error> BlockRepository::remove(const Uuid& id) {
    auto stmt_result = db_.prepare("DELETE FROM blocks WHERE id = ?;");
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

Result<void, Error> BlockRepository::remove_by_page(const Uuid& page_id) {
    auto stmt_result = db_.prepare("DELETE FROM blocks WHERE page_id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, page_id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<int, Error> BlockRepository::count_by_page(const Uuid& page_id) {
    auto stmt_result = db_.prepare("SELECT COUNT(*) FROM blocks WHERE page_id = ?;");
    if (stmt_result.is_err()) {
        return Result<int, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, page_id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<int, Error>::err(step_result.unwrap_err());
    }
    
    return Result<int, Error>::ok(stmt.column_int(0));
}

} // namespace zinc::storage

