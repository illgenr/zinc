#include "storage/database.hpp"
#include <cstring>

namespace zinc::storage {

// ============================================================================
// Statement implementation
// ============================================================================

Result<void, Error> Statement::bind_text(int index, std::string_view text) {
    int rc = sqlite3_bind_text(stmt_.get(), index, text.data(), 
                               static_cast<int>(text.size()), SQLITE_TRANSIENT);
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Failed to bind text", rc});
    }
    return Result<void, Error>::ok();
}

Result<void, Error> Statement::bind_int(int index, int value) {
    int rc = sqlite3_bind_int(stmt_.get(), index, value);
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Failed to bind int", rc});
    }
    return Result<void, Error>::ok();
}

Result<void, Error> Statement::bind_int64(int index, int64_t value) {
    int rc = sqlite3_bind_int64(stmt_.get(), index, value);
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Failed to bind int64", rc});
    }
    return Result<void, Error>::ok();
}

Result<void, Error> Statement::bind_double(int index, double value) {
    int rc = sqlite3_bind_double(stmt_.get(), index, value);
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Failed to bind double", rc});
    }
    return Result<void, Error>::ok();
}

Result<void, Error> Statement::bind_blob(int index, const void* data, size_t size) {
    if (size > 0 && !data) {
        return Result<void, Error>::err(Error{"Failed to bind blob (null data)", SQLITE_MISUSE});
    }
    const char* empty = "";
    const void* safe_data = (size == 0) ? static_cast<const void*>(empty) : data;
    int rc = sqlite3_bind_blob(stmt_.get(), index, safe_data,
                               static_cast<int>(size), SQLITE_TRANSIENT);
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Failed to bind blob", rc});
    }
    return Result<void, Error>::ok();
}

Result<void, Error> Statement::bind_null(int index) {
    int rc = sqlite3_bind_null(stmt_.get(), index);
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Failed to bind null", rc});
    }
    return Result<void, Error>::ok();
}

std::string Statement::column_text(int index) const {
    const unsigned char* text = sqlite3_column_text(stmt_.get(), index);
    if (!text) return "";
    return reinterpret_cast<const char*>(text);
}

int Statement::column_int(int index) const {
    return sqlite3_column_int(stmt_.get(), index);
}

int64_t Statement::column_int64(int index) const {
    return sqlite3_column_int64(stmt_.get(), index);
}

double Statement::column_double(int index) const {
    return sqlite3_column_double(stmt_.get(), index);
}

std::vector<uint8_t> Statement::column_blob(int index) const {
    const void* data = sqlite3_column_blob(stmt_.get(), index);
    int size = sqlite3_column_bytes(stmt_.get(), index);
    if (!data || size <= 0) return {};
    
    const auto* bytes = static_cast<const uint8_t*>(data);
    return std::vector<uint8_t>(bytes, bytes + size);
}

bool Statement::column_is_null(int index) const {
    return sqlite3_column_type(stmt_.get(), index) == SQLITE_NULL;
}

Result<bool, Error> Statement::step() {
    int rc = sqlite3_step(stmt_.get());
    if (rc == SQLITE_ROW) {
        return Result<bool, Error>::ok(true);
    }
    if (rc == SQLITE_DONE) {
        return Result<bool, Error>::ok(false);
    }
    return Result<bool, Error>::err(Error{"Step failed", rc});
}

Result<void, Error> Statement::reset() {
    int rc = sqlite3_reset(stmt_.get());
    if (rc != SQLITE_OK) {
        return Result<void, Error>::err(Error{"Reset failed", rc});
    }
    return Result<void, Error>::ok();
}

// ============================================================================
// Database implementation
// ============================================================================

Database::~Database() {
    close();
}

Database::Database(Database&& other) noexcept : db_(other.db_) {
    other.db_ = nullptr;
}

Database& Database::operator=(Database&& other) noexcept {
    if (this != &other) {
        close();
        db_ = other.db_;
        other.db_ = nullptr;
    }
    return *this;
}

Result<Database, Error> Database::open(const std::string& path) {
    sqlite3* db = nullptr;
    int rc = sqlite3_open(path.c_str(), &db);
    if (rc != SQLITE_OK) {
        std::string error = db ? sqlite3_errmsg(db) : "Unknown error";
        if (db) sqlite3_close(db);
        return Result<Database, Error>::err(Error{error, rc});
    }
    
    // Enable foreign keys
    sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nullptr, nullptr, nullptr);
    
    // Set journal mode to WAL for better concurrency
    sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nullptr, nullptr, nullptr);
    
    return Result<Database, Error>::ok(Database(db));
}

Result<Database, Error> Database::open_memory() {
    return open(":memory:");
}

Result<Database, Error> Database::open_encrypted(
    const std::string& path,
    const std::string& key
) {
#ifdef ZINC_USE_SQLCIPHER
    auto result = open(path);
    if (result.is_err()) return result;
    
    auto db = std::move(result).unwrap();
    
    // Set encryption key
    std::string pragma = "PRAGMA key = '" + key + "';";
    auto exec_result = db.execute(pragma);
    if (exec_result.is_err()) {
        return Result<Database, Error>::err(exec_result.unwrap_err());
    }
    
    // Verify key is correct by running a simple query
    exec_result = db.execute("SELECT count(*) FROM sqlite_master;");
    if (exec_result.is_err()) {
        return Result<Database, Error>::err(
            Error{"Invalid encryption key or corrupted database"});
    }
    
    return Result<Database, Error>::ok(std::move(db));
#else
    (void)path;
    (void)key;
    return Result<Database, Error>::err(
        Error{"SQLCipher not available. Compile with ZINC_USE_SQLCIPHER=ON"});
#endif
}

void Database::close() {
    if (db_) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

Result<Statement, Error> Database::prepare(const std::string& sql) {
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db_, sql.c_str(), 
                                static_cast<int>(sql.size()), &stmt, nullptr);
    if (rc != SQLITE_OK) {
        return Result<Statement, Error>::err(Error{last_error(), rc});
    }
    return Result<Statement, Error>::ok(Statement(stmt));
}

Result<void, Error> Database::execute(const std::string& sql) {
    char* error_msg = nullptr;
    int rc = sqlite3_exec(db_, sql.c_str(), nullptr, nullptr, &error_msg);
    if (rc != SQLITE_OK) {
        std::string error = error_msg ? error_msg : "Unknown error";
        sqlite3_free(error_msg);
        return Result<void, Error>::err(Error{error, rc});
    }
    return Result<void, Error>::ok();
}

Result<void, Error> Database::begin_transaction() {
    return execute("BEGIN TRANSACTION;");
}

Result<void, Error> Database::commit() {
    return execute("COMMIT;");
}

Result<void, Error> Database::rollback() {
    return execute("ROLLBACK;");
}

int64_t Database::last_insert_rowid() const {
    return sqlite3_last_insert_rowid(db_);
}

int Database::changes() const {
    return sqlite3_changes(db_);
}

std::string Database::last_error() const {
    return db_ ? sqlite3_errmsg(db_) : "Database not open";
}

// ============================================================================
// TransactionGuard implementation
// ============================================================================

TransactionGuard::TransactionGuard(Database& db) : db_(db) {
    auto result = db_.begin_transaction();
    active_ = result.is_ok();
}

TransactionGuard::~TransactionGuard() {
    if (active_) {
        rollback();
    }
}

Result<void, Error> TransactionGuard::commit() {
    if (!active_) {
        return Result<void, Error>::err(Error{"No active transaction"});
    }
    auto result = db_.commit();
    if (result.is_ok()) {
        active_ = false;
    }
    return result;
}

void TransactionGuard::rollback() {
    if (active_) {
        db_.rollback();
        active_ = false;
    }
}

} // namespace zinc::storage
