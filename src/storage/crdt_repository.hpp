#pragma once

#include "storage/database.hpp"
#include "core/types.hpp"
#include "core/result.hpp"
#include <vector>
#include <optional>

namespace zinc::storage {

/**
 * CrdtDocument - A stored CRDT document snapshot.
 */
struct CrdtDocument {
    std::string doc_id;
    Uuid page_id;
    std::vector<uint8_t> snapshot;
    std::string vector_clock_json;  // JSON: {"device_id": seq_num}
    Timestamp updated_at;
};

/**
 * CrdtChange - An incremental CRDT change.
 */
struct CrdtChange {
    int64_t id;
    std::string doc_id;
    std::vector<uint8_t> change_bytes;
    std::string actor_id;
    int64_t seq_num;
    Timestamp created_at;
    std::string synced_to_json;  // JSON: {"device_id": true}
};

/**
 * CrdtRepository - Data access layer for CRDT documents and changes.
 */
class CrdtRepository {
public:
    explicit CrdtRepository(Database& db) : db_(db) {}
    
    // Document operations
    
    [[nodiscard]] Result<std::optional<CrdtDocument>, Error> get_document(
        const std::string& doc_id);
    
    [[nodiscard]] Result<std::optional<CrdtDocument>, Error> get_document_by_page(
        const Uuid& page_id);
    
    [[nodiscard]] Result<void, Error> save_document(const CrdtDocument& doc);
    
    [[nodiscard]] Result<void, Error> remove_document(const std::string& doc_id);
    
    // Change operations
    
    [[nodiscard]] Result<std::vector<CrdtChange>, Error> get_changes(
        const std::string& doc_id);
    
    [[nodiscard]] Result<std::vector<CrdtChange>, Error> get_changes_since(
        const std::string& doc_id,
        const std::string& actor_id,
        int64_t since_seq_num);
    
    [[nodiscard]] Result<std::vector<CrdtChange>, Error> get_unsynced_changes(
        const std::string& doc_id,
        const std::string& target_device_id);
    
    [[nodiscard]] Result<void, Error> save_change(const CrdtChange& change);
    
    [[nodiscard]] Result<void, Error> mark_change_synced(
        int64_t change_id,
        const std::string& device_id);
    
    [[nodiscard]] Result<void, Error> remove_changes(const std::string& doc_id);
    
    /**
     * Compact old changes by saving a new snapshot and removing processed changes.
     */
    [[nodiscard]] Result<void, Error> compact(
        const std::string& doc_id,
        const std::vector<uint8_t>& new_snapshot,
        const std::string& new_vector_clock_json);

private:
    Database& db_;
    
    [[nodiscard]] CrdtDocument row_to_document(Statement& stmt);
    [[nodiscard]] CrdtChange row_to_change(Statement& stmt);
};

} // namespace zinc::storage

