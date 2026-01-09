#pragma once

#include "core/result.hpp"
#include "core/types.hpp"
#include <sqlite3.h>
#include <string>
#include <memory>
#include <functional>
#include <vector>
#include <optional>

namespace zinc::storage {

/**
 * SQLite statement wrapper with RAII.
 */
class Statement {
public:
    Statement() = default;
    explicit Statement(sqlite3_stmt* stmt) : stmt_(stmt, sqlite3_finalize) {}
    
    [[nodiscard]] sqlite3_stmt* get() const { return stmt_.get(); }
    [[nodiscard]] explicit operator bool() const { return stmt_ != nullptr; }
    
    // Bind helpers
    Result<void, Error> bind_text(int index, std::string_view text);
    Result<void, Error> bind_int(int index, int value);
    Result<void, Error> bind_int64(int index, int64_t value);
    Result<void, Error> bind_double(int index, double value);
    Result<void, Error> bind_blob(int index, const void* data, size_t size);
    Result<void, Error> bind_null(int index);
    
    // Column getters
    [[nodiscard]] std::string column_text(int index) const;
    [[nodiscard]] int column_int(int index) const;
    [[nodiscard]] int64_t column_int64(int index) const;
    [[nodiscard]] double column_double(int index) const;
    [[nodiscard]] std::vector<uint8_t> column_blob(int index) const;
    [[nodiscard]] bool column_is_null(int index) const;
    
    // Execute
    Result<bool, Error> step();  // Returns true if there's a row
    Result<void, Error> reset();

private:
    std::shared_ptr<sqlite3_stmt> stmt_;
};

/**
 * Database - SQLite database wrapper.
 * 
 * Provides a safe, functional interface to SQLite with:
 * - RAII connection management
 * - Prepared statement caching
 * - Transaction support
 * - Error handling via Result type
 */
class Database {
public:
    Database() = default;
    ~Database();
    
    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;
    Database(Database&& other) noexcept;
    Database& operator=(Database&& other) noexcept;
    
    /**
     * Open a database connection.
     */
    [[nodiscard]] static Result<Database, Error> open(const std::string& path);
    
    /**
     * Open an in-memory database (for testing).
     */
    [[nodiscard]] static Result<Database, Error> open_memory();
    
    /**
     * Open an encrypted database (requires SQLCipher).
     */
    [[nodiscard]] static Result<Database, Error> open_encrypted(
        const std::string& path,
        const std::string& key
    );
    
    /**
     * Check if the database is open.
     */
    [[nodiscard]] bool is_open() const { return db_ != nullptr; }
    
    /**
     * Close the database connection.
     */
    void close();
    
    /**
     * Get the raw SQLite handle (use with caution).
     */
    [[nodiscard]] sqlite3* handle() const { return db_; }
    
    /**
     * Prepare a SQL statement.
     */
    [[nodiscard]] Result<Statement, Error> prepare(const std::string& sql);
    
    /**
     * Execute a SQL statement without results.
     */
    [[nodiscard]] Result<void, Error> execute(const std::string& sql);
    
    /**
     * Execute a SQL statement and process results with a callback.
     */
    template<typename F>
    [[nodiscard]] Result<void, Error> query(const std::string& sql, F&& callback) {
        auto stmt_result = prepare(sql);
        if (stmt_result.is_err()) {
            return Result<void, Error>::err(stmt_result.unwrap_err());
        }
        
        auto stmt = std::move(stmt_result).unwrap();
        while (true) {
            auto step_result = stmt.step();
            if (step_result.is_err()) {
                return Result<void, Error>::err(step_result.unwrap_err());
            }
            if (!step_result.unwrap()) break;
            callback(stmt);
        }
        
        return Result<void, Error>::ok();
    }
    
    /**
     * Begin a transaction.
     */
    [[nodiscard]] Result<void, Error> begin_transaction();
    
    /**
     * Commit the current transaction.
     */
    [[nodiscard]] Result<void, Error> commit();
    
    /**
     * Rollback the current transaction.
     */
    [[nodiscard]] Result<void, Error> rollback();
    
    /**
     * Execute a function within a transaction.
     * Automatically commits on success, rolls back on failure.
     */
    template<typename F>
    [[nodiscard]] auto transaction(F&& f) -> decltype(f()) {
        using ResultType = decltype(f());
        
        auto begin_result = begin_transaction();
        if (begin_result.is_err()) {
            return ResultType::err(begin_result.unwrap_err());
        }
        
        auto result = f();
        
        if (result.is_err()) {
            rollback();  // Ignore rollback errors
            return result;
        }
        
        auto commit_result = commit();
        if (commit_result.is_err()) {
            return ResultType::err(commit_result.unwrap_err());
        }
        
        return result;
    }
    
    /**
     * Get the last insert rowid.
     */
    [[nodiscard]] int64_t last_insert_rowid() const;
    
    /**
     * Get the number of rows changed by the last statement.
     */
    [[nodiscard]] int changes() const;
    
    /**
     * Get the last error message.
     */
    [[nodiscard]] std::string last_error() const;

private:
    explicit Database(sqlite3* db) : db_(db) {}
    
    sqlite3* db_ = nullptr;
};

/**
 * Transaction RAII guard.
 * Automatically rolls back if not explicitly committed.
 */
class TransactionGuard {
public:
    explicit TransactionGuard(Database& db);
    ~TransactionGuard();
    
    TransactionGuard(const TransactionGuard&) = delete;
    TransactionGuard& operator=(const TransactionGuard&) = delete;
    
    [[nodiscard]] Result<void, Error> commit();
    void rollback();
    
    [[nodiscard]] bool is_active() const { return active_; }

private:
    Database& db_;
    bool active_ = false;
};

} // namespace zinc::storage

