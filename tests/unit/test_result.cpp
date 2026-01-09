#include <catch2/catch_test_macros.hpp>
#include "core/result.hpp"

using namespace zinc;

TEST_CASE("Result::ok creates a success result", "[result]") {
    auto result = Result<int>::ok(42);
    
    REQUIRE(result.is_ok());
    REQUIRE_FALSE(result.is_err());
    REQUIRE(result.unwrap() == 42);
}

TEST_CASE("Result::err creates an error result", "[result]") {
    auto result = Result<int>::err(Error{"something went wrong", 1});
    
    REQUIRE_FALSE(result.is_ok());
    REQUIRE(result.is_err());
    REQUIRE(result.unwrap_err().message == "something went wrong");
    REQUIRE(result.unwrap_err().code == 1);
}

TEST_CASE("Result::unwrap throws on error", "[result]") {
    auto result = Result<int>::err(Error{"error"});
    
    REQUIRE_THROWS_AS(result.unwrap(), std::runtime_error);
}

TEST_CASE("Result::value_or returns default on error", "[result]") {
    auto ok_result = Result<int>::ok(42);
    auto err_result = Result<int>::err(Error{"error"});
    
    REQUIRE(ok_result.value_or(0) == 42);
    REQUIRE(err_result.value_or(0) == 0);
}

TEST_CASE("Result::map transforms success value", "[result]") {
    auto result = Result<int>::ok(21);
    auto mapped = result.map([](int x) { return x * 2; });
    
    REQUIRE(mapped.is_ok());
    REQUIRE(mapped.unwrap() == 42);
}

TEST_CASE("Result::map propagates error", "[result]") {
    auto result = Result<int>::err(Error{"error"});
    auto mapped = result.map([](int x) { return x * 2; });
    
    REQUIRE(mapped.is_err());
    REQUIRE(mapped.unwrap_err().message == "error");
}

TEST_CASE("Result::and_then chains operations", "[result]") {
    auto divide = [](int x) -> Result<int> {
        if (x == 0) return Result<int>::err(Error{"division by zero"});
        return Result<int>::ok(100 / x);
    };
    
    auto result = Result<int>::ok(5).and_then(divide);
    
    REQUIRE(result.is_ok());
    REQUIRE(result.unwrap() == 20);
}

TEST_CASE("Result::and_then short-circuits on error", "[result]") {
    auto divide = [](int x) -> Result<int> {
        return Result<int>::ok(100 / x);
    };
    
    auto result = Result<int>::err(Error{"initial error"}).and_then(divide);
    
    REQUIRE(result.is_err());
    REQUIRE(result.unwrap_err().message == "initial error");
}

TEST_CASE("Result::or_else handles errors", "[result]") {
    auto fallback = [](const Error&) -> Result<int> {
        return Result<int>::ok(0);
    };
    
    auto ok_result = Result<int>::ok(42).or_else(fallback);
    auto err_result = Result<int>::err(Error{"error"}).or_else(fallback);
    
    REQUIRE(ok_result.unwrap() == 42);
    REQUIRE(err_result.unwrap() == 0);
}

TEST_CASE("Result::map_err transforms error", "[result]") {
    auto result = Result<int>::err(Error{"error", 1});
    auto mapped = result.map_err([](Error e) {
        return Error{e.message + " (transformed)", e.code + 10};
    });
    
    REQUIRE(mapped.is_err());
    REQUIRE(mapped.unwrap_err().message == "error (transformed)");
    REQUIRE(mapped.unwrap_err().code == 11);
}

TEST_CASE("Result::match handles both cases", "[result]") {
    auto ok_result = Result<int>::ok(42);
    auto err_result = Result<int>::err(Error{"error"});
    
    auto ok_value = ok_result.match(
        [](int x) { return x; },
        [](const Error&) { return -1; }
    );
    
    auto err_value = err_result.match(
        [](int x) { return x; },
        [](const Error&) { return -1; }
    );
    
    REQUIRE(ok_value == 42);
    REQUIRE(err_value == -1);
}

TEST_CASE("Result<void> works correctly", "[result]") {
    auto ok_result = Result<void>::ok();
    auto err_result = Result<void>::err(Error{"error"});
    
    REQUIRE(ok_result.is_ok());
    REQUIRE(err_result.is_err());
    
    REQUIRE_NOTHROW(ok_result.unwrap());
    REQUIRE_THROWS(err_result.unwrap());
}

TEST_CASE("Result chaining works with different types", "[result]") {
    auto result = Result<int>::ok(5)
        .map([](int x) { return std::to_string(x); })
        .map([](const std::string& s) { return s + " items"; });
    
    REQUIRE(result.is_ok());
    REQUIRE(result.unwrap() == "5 items");
}

