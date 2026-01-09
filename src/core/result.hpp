#pragma once

#include <variant>
#include <string>
#include <functional>
#include <stdexcept>
#include <type_traits>

namespace zinc {

/**
 * Error type for Result - represents a failure with a message and optional code.
 */
struct Error {
    std::string message;
    int code{0};
    
    Error() = default;
    explicit Error(std::string msg, int c = 0) : message(std::move(msg)), code(c) {}
    
    bool operator==(const Error& other) const {
        return message == other.message && code == other.code;
    }
};

/**
 * Result<T, E> - A functional error handling type.
 * 
 * Represents either a successful value (Ok) or an error (Err).
 * Inspired by Rust's Result type, providing functional combinators
 * for composing operations that may fail.
 * 
 * Usage:
 *   Result<int> divide(int a, int b) {
 *       if (b == 0) return Result<int>::err(Error{"Division by zero"});
 *       return Result<int>::ok(a / b);
 *   }
 *   
 *   auto result = divide(10, 2)
 *       .map([](int x) { return x * 2; })
 *       .and_then([](int x) { return divide(x, 2); });
 */
template<typename T, typename E = Error>
class Result {
public:
    // Type aliases for easier access
    using value_type = T;
    using error_type = E;
    
    /**
     * Create a successful Result containing a value.
     */
    [[nodiscard]] static Result ok(T value) {
        return Result(std::in_place_index<0>, std::move(value));
    }
    
    /**
     * Create a failed Result containing an error.
     */
    [[nodiscard]] static Result err(E error) {
        return Result(std::in_place_index<1>, std::move(error));
    }
    
    /**
     * Check if the Result contains a success value.
     */
    [[nodiscard]] bool is_ok() const noexcept {
        return std::holds_alternative<T>(data_);
    }
    
    /**
     * Check if the Result contains an error.
     */
    [[nodiscard]] bool is_err() const noexcept {
        return std::holds_alternative<E>(data_);
    }
    
    /**
     * Get the success value, throwing if this is an error.
     * Use sparingly - prefer map/and_then for safe access.
     */
    [[nodiscard]] T& unwrap() & {
        if (is_err()) {
            if constexpr (std::is_same_v<E, Error>) {
                throw std::runtime_error("Result::unwrap() called on error: " + 
                                        std::get<E>(data_).message);
            } else {
                throw std::runtime_error("Result::unwrap() called on error");
            }
        }
        return std::get<T>(data_);
    }
    
    [[nodiscard]] const T& unwrap() const& {
        if (is_err()) {
            if constexpr (std::is_same_v<E, Error>) {
                throw std::runtime_error("Result::unwrap() called on error: " + 
                                        std::get<E>(data_).message);
            } else {
                throw std::runtime_error("Result::unwrap() called on error");
            }
        }
        return std::get<T>(data_);
    }
    
    [[nodiscard]] T unwrap() && {
        if (is_err()) {
            if constexpr (std::is_same_v<E, Error>) {
                throw std::runtime_error("Result::unwrap() called on error: " + 
                                        std::get<E>(data_).message);
            } else {
                throw std::runtime_error("Result::unwrap() called on error");
            }
        }
        return std::get<T>(std::move(data_));
    }
    
    /**
     * Get the error, throwing if this is a success.
     */
    [[nodiscard]] E& unwrap_err() & {
        if (is_ok()) {
            throw std::runtime_error("Result::unwrap_err() called on success");
        }
        return std::get<E>(data_);
    }
    
    [[nodiscard]] const E& unwrap_err() const& {
        if (is_ok()) {
            throw std::runtime_error("Result::unwrap_err() called on success");
        }
        return std::get<E>(data_);
    }
    
    /**
     * Get the success value or a default if this is an error.
     */
    [[nodiscard]] T value_or(T default_value) const& {
        if (is_ok()) {
            return std::get<T>(data_);
        }
        return default_value;
    }
    
    [[nodiscard]] T value_or(T default_value) && {
        if (is_ok()) {
            return std::get<T>(std::move(data_));
        }
        return default_value;
    }
    
    /**
     * Transform the success value using a function.
     * If this is an error, the error is propagated unchanged.
     * 
     * map : Result<T, E> -> (T -> U) -> Result<U, E>
     */
    template<typename F>
    [[nodiscard]] auto map(F&& f) const& -> Result<std::invoke_result_t<F, const T&>, E> {
        using U = std::invoke_result_t<F, const T&>;
        if (is_ok()) {
            return Result<U, E>::ok(std::invoke(std::forward<F>(f), std::get<T>(data_)));
        }
        return Result<U, E>::err(std::get<E>(data_));
    }
    
    template<typename F>
    [[nodiscard]] auto map(F&& f) && -> Result<std::invoke_result_t<F, T>, E> {
        using U = std::invoke_result_t<F, T>;
        if (is_ok()) {
            return Result<U, E>::ok(std::invoke(std::forward<F>(f), std::get<T>(std::move(data_))));
        }
        return Result<U, E>::err(std::get<E>(std::move(data_)));
    }
    
    /**
     * Transform the error using a function.
     * If this is a success, the value is propagated unchanged.
     * 
     * map_err : Result<T, E> -> (E -> F) -> Result<T, F>
     */
    template<typename F>
    [[nodiscard]] auto map_err(F&& f) const& -> Result<T, std::invoke_result_t<F, const E&>> {
        using NewE = std::invoke_result_t<F, const E&>;
        if (is_err()) {
            return Result<T, NewE>::err(std::invoke(std::forward<F>(f), std::get<E>(data_)));
        }
        return Result<T, NewE>::ok(std::get<T>(data_));
    }
    
    template<typename F>
    [[nodiscard]] auto map_err(F&& f) && -> Result<T, std::invoke_result_t<F, E>> {
        using NewE = std::invoke_result_t<F, E>;
        if (is_err()) {
            return Result<T, NewE>::err(std::invoke(std::forward<F>(f), std::get<E>(std::move(data_))));
        }
        return Result<T, NewE>::ok(std::get<T>(std::move(data_)));
    }
    
    /**
     * Chain operations that return Results (flatMap/bind).
     * If this is an error, the error is propagated.
     * 
     * and_then : Result<T, E> -> (T -> Result<U, E>) -> Result<U, E>
     */
    template<typename F>
    [[nodiscard]] auto and_then(F&& f) const& -> std::invoke_result_t<F, const T&> {
        using ResultU = std::invoke_result_t<F, const T&>;
        if (is_ok()) {
            return std::invoke(std::forward<F>(f), std::get<T>(data_));
        }
        return ResultU::err(std::get<E>(data_));
    }
    
    template<typename F>
    [[nodiscard]] auto and_then(F&& f) && -> std::invoke_result_t<F, T> {
        using ResultU = std::invoke_result_t<F, T>;
        if (is_ok()) {
            return std::invoke(std::forward<F>(f), std::get<T>(std::move(data_)));
        }
        return ResultU::err(std::get<E>(std::move(data_)));
    }
    
    /**
     * Handle errors by providing an alternative Result.
     * If this is a success, the value is returned unchanged.
     * 
     * or_else : Result<T, E> -> (E -> Result<T, F>) -> Result<T, F>
     */
    template<typename F>
    [[nodiscard]] auto or_else(F&& f) const& -> std::invoke_result_t<F, const E&> {
        using ResultT = std::invoke_result_t<F, const E&>;
        if (is_err()) {
            return std::invoke(std::forward<F>(f), std::get<E>(data_));
        }
        return ResultT::ok(std::get<T>(data_));
    }
    
    template<typename F>
    [[nodiscard]] auto or_else(F&& f) && -> std::invoke_result_t<F, E> {
        using ResultT = std::invoke_result_t<F, E>;
        if (is_err()) {
            return std::invoke(std::forward<F>(f), std::get<E>(std::move(data_)));
        }
        return ResultT::ok(std::get<T>(std::move(data_)));
    }
    
    /**
     * Execute a function on success, returning this Result unchanged.
     * Useful for side effects like logging.
     */
    template<typename F>
    Result& inspect(F&& f) & {
        if (is_ok()) {
            std::invoke(std::forward<F>(f), std::get<T>(data_));
        }
        return *this;
    }
    
    template<typename F>
    const Result& inspect(F&& f) const& {
        if (is_ok()) {
            std::invoke(std::forward<F>(f), std::get<T>(data_));
        }
        return *this;
    }
    
    /**
     * Execute a function on error, returning this Result unchanged.
     */
    template<typename F>
    Result& inspect_err(F&& f) & {
        if (is_err()) {
            std::invoke(std::forward<F>(f), std::get<E>(data_));
        }
        return *this;
    }
    
    template<typename F>
    const Result& inspect_err(F&& f) const& {
        if (is_err()) {
            std::invoke(std::forward<F>(f), std::get<E>(data_));
        }
        return *this;
    }
    
    /**
     * Match on the Result, calling one of two functions.
     */
    template<typename OnOk, typename OnErr>
    [[nodiscard]] auto match(OnOk&& on_ok, OnErr&& on_err) const& {
        if (is_ok()) {
            return std::invoke(std::forward<OnOk>(on_ok), std::get<T>(data_));
        }
        return std::invoke(std::forward<OnErr>(on_err), std::get<E>(data_));
    }
    
    template<typename OnOk, typename OnErr>
    [[nodiscard]] auto match(OnOk&& on_ok, OnErr&& on_err) && {
        if (is_ok()) {
            return std::invoke(std::forward<OnOk>(on_ok), std::get<T>(std::move(data_)));
        }
        return std::invoke(std::forward<OnErr>(on_err), std::get<E>(std::move(data_)));
    }

private:
    template<size_t I, typename... Args>
    explicit Result(std::in_place_index_t<I> idx, Args&&... args)
        : data_(idx, std::forward<Args>(args)...) {}
    
    std::variant<T, E> data_;
};

/**
 * Specialization for void success type (Result<void, E>).
 * Represents operations that either succeed (with no value) or fail with an error.
 */
template<typename E>
class Result<void, E> {
public:
    using value_type = void;
    using error_type = E;
    
    [[nodiscard]] static Result ok() {
        return Result(true);
    }
    
    [[nodiscard]] static Result err(E error) {
        return Result(std::move(error));
    }
    
    [[nodiscard]] bool is_ok() const noexcept {
        return is_ok_;
    }
    
    [[nodiscard]] bool is_err() const noexcept {
        return !is_ok_;
    }
    
    void unwrap() const {
        if (is_err()) {
            if constexpr (std::is_same_v<E, Error>) {
                throw std::runtime_error("Result::unwrap() called on error: " + error_.message);
            } else {
                throw std::runtime_error("Result::unwrap() called on error");
            }
        }
    }
    
    [[nodiscard]] E& unwrap_err() & {
        if (is_ok()) {
            throw std::runtime_error("Result::unwrap_err() called on success");
        }
        return error_;
    }
    
    [[nodiscard]] const E& unwrap_err() const& {
        if (is_ok()) {
            throw std::runtime_error("Result::unwrap_err() called on success");
        }
        return error_;
    }
    
    template<typename F>
    [[nodiscard]] auto map(F&& f) const -> Result<std::invoke_result_t<F>, E> {
        using U = std::invoke_result_t<F>;
        if (is_ok()) {
            if constexpr (std::is_void_v<U>) {
                std::invoke(std::forward<F>(f));
                return Result<void, E>::ok();
            } else {
                return Result<U, E>::ok(std::invoke(std::forward<F>(f)));
            }
        }
        return Result<U, E>::err(error_);
    }
    
    template<typename F>
    [[nodiscard]] auto and_then(F&& f) const -> std::invoke_result_t<F> {
        using ResultU = std::invoke_result_t<F>;
        if (is_ok()) {
            return std::invoke(std::forward<F>(f));
        }
        return ResultU::err(error_);
    }
    
    template<typename F>
    [[nodiscard]] auto or_else(F&& f) const -> std::invoke_result_t<F, const E&> {
        if (is_err()) {
            return std::invoke(std::forward<F>(f), error_);
        }
        return std::invoke_result_t<F, const E&>::ok();
    }

private:
    explicit Result(bool ok) : is_ok_(ok) {}
    explicit Result(E error) : is_ok_(false), error_(std::move(error)) {}
    
    bool is_ok_;
    E error_{};
};

// Convenience type alias
template<typename T>
using Res = Result<T, Error>;

} // namespace zinc

