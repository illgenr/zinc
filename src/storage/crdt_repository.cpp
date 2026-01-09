#include "storage/crdt_repository.hpp"

namespace zinc::storage {

CrdtDocument CrdtRepository::row_to_document(Statement& stmt) {
    return CrdtDocument{
        .doc_id = stmt.column_text(0),
        .page_id = Uuid::parse(stmt.column_text(1)).value_or(Uuid{}),
        .snapshot = stmt.column_blob(2),
        .vector_clock_json = stmt.column_text(3),
        .updated_at = Timestamp(stmt.column_int64(4))
    };
}

CrdtChange CrdtRepository::row_to_change(Statement& stmt) {
    return CrdtChange{
        .id = stmt.column_int64(0),
        .doc_id = stmt.column_text(1),
        .change_bytes = stmt.column_blob(2),
        .actor_id = stmt.column_text(3),
        .seq_num = stmt.column_int64(4),
        .created_at = Timestamp(stmt.column_int64(5)),
        .synced_to_json = stmt.column_text(6)
    };
}

Result<std::optional<CrdtDocument>, Error> CrdtRepository::get_document(
    const std::string& doc_id
) {
    auto stmt_result = db_.prepare(R"SQL(
        SELECT doc_id, page_id, snapshot, vector_clock, updated_at
        FROM crdt_documents WHERE doc_id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::optional<CrdtDocument>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc_id);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<std::optional<CrdtDocument>, Error>::err(step_result.unwrap_err());
    }
    
    if (!step_result.unwrap()) {
        return Result<std::optional<CrdtDocument>, Error>::ok(std::nullopt);
    }
    
    return Result<std::optional<CrdtDocument>, Error>::ok(row_to_document(stmt));
}

Result<std::optional<CrdtDocument>, Error> CrdtRepository::get_document_by_page(
    const Uuid& page_id
) {
    auto stmt_result = db_.prepare(R"SQL(
        SELECT doc_id, page_id, snapshot, vector_clock, updated_at
        FROM crdt_documents WHERE page_id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::optional<CrdtDocument>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, page_id.to_string());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<std::optional<CrdtDocument>, Error>::err(step_result.unwrap_err());
    }
    
    if (!step_result.unwrap()) {
        return Result<std::optional<CrdtDocument>, Error>::ok(std::nullopt);
    }
    
    return Result<std::optional<CrdtDocument>, Error>::ok(row_to_document(stmt));
}

Result<void, Error> CrdtRepository::save_document(const CrdtDocument& doc) {
    auto stmt_result = db_.prepare(R"SQL(
        INSERT INTO crdt_documents (doc_id, page_id, snapshot, vector_clock, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(doc_id) DO UPDATE SET
            page_id = excluded.page_id,
            snapshot = excluded.snapshot,
            vector_clock = excluded.vector_clock,
            updated_at = excluded.updated_at;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc.doc_id);
    stmt.bind_text(2, doc.page_id.to_string());
    stmt.bind_blob(3, doc.snapshot.data(), doc.snapshot.size());
    stmt.bind_text(4, doc.vector_clock_json);
    stmt.bind_int64(5, doc.updated_at.millis());
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> CrdtRepository::remove_document(const std::string& doc_id) {
    auto stmt_result = db_.prepare("DELETE FROM crdt_documents WHERE doc_id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc_id);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<std::vector<CrdtChange>, Error> CrdtRepository::get_changes(
    const std::string& doc_id
) {
    std::vector<CrdtChange> changes;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, doc_id, change_bytes, actor_id, seq_num, created_at, synced_to
        FROM crdt_changes WHERE doc_id = ? ORDER BY id;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<CrdtChange>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc_id);
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<CrdtChange>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        changes.push_back(row_to_change(stmt));
    }
    
    return Result<std::vector<CrdtChange>, Error>::ok(std::move(changes));
}

Result<std::vector<CrdtChange>, Error> CrdtRepository::get_changes_since(
    const std::string& doc_id,
    const std::string& actor_id,
    int64_t since_seq_num
) {
    std::vector<CrdtChange> changes;
    
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, doc_id, change_bytes, actor_id, seq_num, created_at, synced_to
        FROM crdt_changes 
        WHERE doc_id = ? AND actor_id = ? AND seq_num > ?
        ORDER BY seq_num;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<CrdtChange>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc_id);
    stmt.bind_text(2, actor_id);
    stmt.bind_int64(3, since_seq_num);
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<CrdtChange>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        changes.push_back(row_to_change(stmt));
    }
    
    return Result<std::vector<CrdtChange>, Error>::ok(std::move(changes));
}

Result<std::vector<CrdtChange>, Error> CrdtRepository::get_unsynced_changes(
    const std::string& doc_id,
    const std::string& target_device_id
) {
    std::vector<CrdtChange> changes;
    
    // Get changes where synced_to doesn't contain the target device
    auto stmt_result = db_.prepare(R"SQL(
        SELECT id, doc_id, change_bytes, actor_id, seq_num, created_at, synced_to
        FROM crdt_changes 
        WHERE doc_id = ? AND synced_to NOT LIKE ?
        ORDER BY id;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<std::vector<CrdtChange>, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc_id);
    stmt.bind_text(2, "%\"" + target_device_id + "\":true%");
    
    while (true) {
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<std::vector<CrdtChange>, Error>::err(step_result.unwrap_err());
        }
        if (!step_result.unwrap()) break;
        
        changes.push_back(row_to_change(stmt));
    }
    
    return Result<std::vector<CrdtChange>, Error>::ok(std::move(changes));
}

Result<void, Error> CrdtRepository::save_change(const CrdtChange& change) {
    auto stmt_result = db_.prepare(R"SQL(
        INSERT INTO crdt_changes (doc_id, change_bytes, actor_id, seq_num, created_at, synced_to)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(doc_id, actor_id, seq_num) DO NOTHING;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, change.doc_id);
    stmt.bind_blob(2, change.change_bytes.data(), change.change_bytes.size());
    stmt.bind_text(3, change.actor_id);
    stmt.bind_int64(4, change.seq_num);
    stmt.bind_int64(5, change.created_at.millis());
    stmt.bind_text(6, change.synced_to_json);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> CrdtRepository::mark_change_synced(
    int64_t change_id,
    const std::string& device_id
) {
    // Simple approach: append to JSON (production code should properly parse and update)
    auto stmt_result = db_.prepare(R"SQL(
        UPDATE crdt_changes 
        SET synced_to = json_set(synced_to, '$.' || ?, json('true'))
        WHERE id = ?;
    )SQL");
    
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, device_id);
    stmt.bind_int64(2, change_id);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> CrdtRepository::remove_changes(const std::string& doc_id) {
    auto stmt_result = db_.prepare("DELETE FROM crdt_changes WHERE doc_id = ?;");
    if (stmt_result.is_err()) {
        return Result<void, Error>::err(stmt_result.unwrap_err());
    }
    
    auto stmt = std::move(stmt_result).unwrap();
    stmt.bind_text(1, doc_id);
    
    auto step_result = stmt.step();
    if (step_result.is_err()) {
        return Result<void, Error>::err(step_result.unwrap_err());
    }
    
    return Result<void, Error>::ok();
}

Result<void, Error> CrdtRepository::compact(
    const std::string& doc_id,
    const std::vector<uint8_t>& new_snapshot,
    const std::string& new_vector_clock_json
) {
    return db_.transaction([&]() -> Result<void, Error> {
        // Update document snapshot
        auto update_result = db_.prepare(R"SQL(
            UPDATE crdt_documents 
            SET snapshot = ?, vector_clock = ?, updated_at = ?
            WHERE doc_id = ?;
        )SQL");
        
        if (update_result.is_err()) {
            return Result<void, Error>::err(update_result.unwrap_err());
        }
        
        auto stmt = std::move(update_result).unwrap();
        stmt.bind_blob(1, new_snapshot.data(), new_snapshot.size());
        stmt.bind_text(2, new_vector_clock_json);
        stmt.bind_int64(3, Timestamp::now().millis());
        stmt.bind_text(4, doc_id);
        
        auto step_result = stmt.step();
        if (step_result.is_err()) {
            return Result<void, Error>::err(step_result.unwrap_err());
        }
        
        // Remove all changes (they're now in the snapshot)
        return remove_changes(doc_id);
    });
}

} // namespace zinc::storage

