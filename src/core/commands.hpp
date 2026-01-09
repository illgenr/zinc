#pragma once

#include "core/block_types.hpp"
#include <vector>
#include <string>
#include <string_view>
#include <functional>
#include <algorithm>

namespace zinc::commands {

/**
 * SlashCommand - Definition of a slash command.
 * 
 * Commands can:
 * - Insert new blocks
 * - Transform existing blocks
 * - Trigger actions
 */
struct SlashCommand {
    std::string trigger;      // e.g., "/h1", "/todo", "/code"
    std::string label;        // Display name
    std::string description;  // Help text
    std::string icon;         // Icon identifier
    std::function<blocks::BlockContent()> create_content;
    
    /**
     * Check if this command matches a query (for filtering).
     */
    [[nodiscard]] bool matches(std::string_view query) const {
        // Match against trigger or label (case-insensitive)
        auto lower_query = std::string(query);
        std::transform(lower_query.begin(), lower_query.end(), 
                      lower_query.begin(), ::tolower);
        
        auto lower_trigger = trigger;
        std::transform(lower_trigger.begin(), lower_trigger.end(), 
                      lower_trigger.begin(), ::tolower);
        
        auto lower_label = label;
        std::transform(lower_label.begin(), lower_label.end(), 
                      lower_label.begin(), ::tolower);
        
        return lower_trigger.find(lower_query) != std::string::npos ||
               lower_label.find(lower_query) != std::string::npos;
    }
};

/**
 * Built-in slash commands.
 */
inline const std::vector<SlashCommand> BUILTIN_COMMANDS = {
    {
        "/text", "Text", "Plain text paragraph", "text",
        [] { return blocks::Paragraph{""}; }
    },
    {
        "/h1", "Heading 1", "Large heading", "heading-1",
        [] { return blocks::Heading{1, ""}; }
    },
    {
        "/h2", "Heading 2", "Medium heading", "heading-2",
        [] { return blocks::Heading{2, ""}; }
    },
    {
        "/h3", "Heading 3", "Small heading", "heading-3",
        [] { return blocks::Heading{3, ""}; }
    },
    {
        "/todo", "To-do", "Checkbox item", "checkbox",
        [] { return blocks::Todo{false, ""}; }
    },
    {
        "/code", "Code", "Code block", "code",
        [] { return blocks::Code{"", ""}; }
    },
    {
        "/quote", "Quote", "Block quote", "quote",
        [] { return blocks::Quote{""}; }
    },
    {
        "/divider", "Divider", "Horizontal line", "minus",
        [] { return blocks::Divider{}; }
    },
    {
        "/toggle", "Toggle", "Collapsible content", "chevron-right",
        [] { return blocks::Toggle{true, ""}; }
    },
};

/**
 * CommandRegistry - Registry of available slash commands.
 * 
 * Provides methods to query and filter commands.
 */
class CommandRegistry {
public:
    /**
     * Get all registered commands.
     */
    [[nodiscard]] static const std::vector<SlashCommand>& all() {
        return BUILTIN_COMMANDS;
    }
    
    /**
     * Filter commands by a query string.
     */
    [[nodiscard]] static std::vector<SlashCommand> filter(std::string_view query) {
        std::vector<SlashCommand> results;
        
        // Remove leading slash if present
        if (!query.empty() && query[0] == '/') {
            query = query.substr(1);
        }
        
        for (const auto& cmd : BUILTIN_COMMANDS) {
            if (query.empty() || cmd.matches(query)) {
                results.push_back(cmd);
            }
        }
        
        return results;
    }
    
    /**
     * Find a command by its exact trigger.
     */
    [[nodiscard]] static const SlashCommand* find(std::string_view trigger) {
        for (const auto& cmd : BUILTIN_COMMANDS) {
            if (cmd.trigger == trigger) {
                return &cmd;
            }
        }
        return nullptr;
    }
    
    /**
     * Execute a command by trigger, returning the created block content.
     */
    [[nodiscard]] static std::optional<blocks::BlockContent> execute(
        std::string_view trigger
    ) {
        auto cmd = find(trigger);
        if (cmd && cmd->create_content) {
            return cmd->create_content();
        }
        return std::nullopt;
    }
};

/**
 * Parse text to detect slash commands.
 * 
 * Returns the command trigger if the text starts with a slash command,
 * or nullopt if no command is detected.
 */
[[nodiscard]] inline std::optional<std::string> parse_command(std::string_view text) {
    if (text.empty() || text[0] != '/') {
        return std::nullopt;
    }
    
    // Find end of command (space or end of string)
    auto end = text.find(' ');
    auto trigger = std::string(text.substr(0, end));
    
    // Check if it's a valid command
    if (CommandRegistry::find(trigger)) {
        return trigger;
    }
    
    return std::nullopt;
}

/**
 * Check if text is in the middle of typing a slash command.
 * Returns the partial command text being typed.
 */
[[nodiscard]] inline std::optional<std::string> detect_partial_command(
    std::string_view text
) {
    if (text.empty() || text[0] != '/') {
        return std::nullopt;
    }
    
    // Check if there's a space (command would be complete)
    if (text.find(' ') != std::string_view::npos) {
        return std::nullopt;
    }
    
    return std::string(text);
}

} // namespace zinc::commands

