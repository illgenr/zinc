#include <catch2/catch_test_macros.hpp>
#include "core/commands.hpp"

using namespace zinc::commands;
using namespace zinc::blocks;

TEST_CASE("CommandRegistry::all returns all commands", "[commands]") {
    const auto& commands = CommandRegistry::all();
    
    REQUIRE(commands.size() >= 9);  // At least the built-in commands
}

TEST_CASE("CommandRegistry::filter filters by query", "[commands]") {
    SECTION("Empty query returns all") {
        auto results = CommandRegistry::filter("");
        REQUIRE(results.size() == CommandRegistry::all().size());
    }
    
    SECTION("Filter by trigger") {
        auto results = CommandRegistry::filter("h1");
        REQUIRE(results.size() >= 1);
        REQUIRE(results[0].trigger == "/h1");
    }
    
    SECTION("Filter with leading slash") {
        auto results = CommandRegistry::filter("/h1");
        REQUIRE(results.size() >= 1);
        REQUIRE(results[0].trigger == "/h1");
    }
    
    SECTION("Filter by label") {
        auto results = CommandRegistry::filter("todo");
        REQUIRE(results.size() >= 1);
        
        bool found = false;
        for (const auto& cmd : results) {
            if (cmd.trigger == "/todo") found = true;
        }
        REQUIRE(found);
    }
    
    SECTION("Case insensitive") {
        auto results = CommandRegistry::filter("HEADING");
        REQUIRE(results.size() >= 1);
    }
    
    SECTION("No match returns empty") {
        auto results = CommandRegistry::filter("nonexistent");
        REQUIRE(results.empty());
    }
}

TEST_CASE("CommandRegistry::find finds by exact trigger", "[commands]") {
    SECTION("Found") {
        auto cmd = CommandRegistry::find("/todo");
        REQUIRE(cmd != nullptr);
        REQUIRE(cmd->trigger == "/todo");
    }
    
    SECTION("Not found") {
        auto cmd = CommandRegistry::find("/nonexistent");
        REQUIRE(cmd == nullptr);
    }
}

TEST_CASE("CommandRegistry::execute creates block content", "[commands]") {
    SECTION("Todo command") {
        auto result = CommandRegistry::execute("/todo");
        REQUIRE(result.has_value());
        REQUIRE(get_type(*result) == BlockType::Todo);
    }
    
    SECTION("Heading command") {
        auto result = CommandRegistry::execute("/h1");
        REQUIRE(result.has_value());
        REQUIRE(get_type(*result) == BlockType::Heading);
        REQUIRE(std::get<Heading>(*result).level == 1);
    }
    
    SECTION("Code command") {
        auto result = CommandRegistry::execute("/code");
        REQUIRE(result.has_value());
        REQUIRE(get_type(*result) == BlockType::Code);
    }
    
    SECTION("Invalid command returns nullopt") {
        auto result = CommandRegistry::execute("/invalid");
        REQUIRE_FALSE(result.has_value());
    }
}

TEST_CASE("SlashCommand::matches", "[commands]") {
    SlashCommand cmd{"/test", "Test Command", "A test", "test-icon", nullptr};
    
    REQUIRE(cmd.matches("test"));
    REQUIRE(cmd.matches("Test"));
    REQUIRE(cmd.matches("TEST"));
    REQUIRE(cmd.matches("est"));  // Partial match
    REQUIRE(cmd.matches("Command"));
    REQUIRE_FALSE(cmd.matches("xyz"));
}

TEST_CASE("parse_command detects slash commands", "[commands]") {
    SECTION("Valid command") {
        auto result = parse_command("/todo");
        REQUIRE(result.has_value());
        REQUIRE(*result == "/todo");
    }
    
    SECTION("Command with trailing text") {
        auto result = parse_command("/todo some text");
        REQUIRE(result.has_value());
        REQUIRE(*result == "/todo");
    }
    
    SECTION("No slash") {
        auto result = parse_command("todo");
        REQUIRE_FALSE(result.has_value());
    }
    
    SECTION("Invalid command") {
        auto result = parse_command("/invalidcmd");
        REQUIRE_FALSE(result.has_value());
    }
    
    SECTION("Empty string") {
        auto result = parse_command("");
        REQUIRE_FALSE(result.has_value());
    }
}

TEST_CASE("detect_partial_command", "[commands]") {
    SECTION("Partial command being typed") {
        auto result = detect_partial_command("/to");
        REQUIRE(result.has_value());
        REQUIRE(*result == "/to");
    }
    
    SECTION("Complete command with space") {
        auto result = detect_partial_command("/todo ");
        REQUIRE_FALSE(result.has_value());
    }
    
    SECTION("Not a command") {
        auto result = detect_partial_command("some text");
        REQUIRE_FALSE(result.has_value());
    }
    
    SECTION("Just slash") {
        auto result = detect_partial_command("/");
        REQUIRE(result.has_value());
        REQUIRE(*result == "/");
    }
}

TEST_CASE("Built-in commands create correct content", "[commands]") {
    for (const auto& cmd : BUILTIN_COMMANDS) {
        REQUIRE_FALSE(cmd.trigger.empty());
        REQUIRE_FALSE(cmd.label.empty());
        REQUIRE(cmd.create_content != nullptr);
        
        // Verify the content can be created
        auto content = cmd.create_content();
        // Just verify it doesn't throw
        (void)get_type(content);
    }
}

