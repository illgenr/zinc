#pragma once

#include "core/types.hpp"
#include "core/fractional_index.hpp"
#include "core/result.hpp"

#include <variant>
#include <string>
#include <optional>
#include <vector>

namespace zinc::blocks {

/**
 * Block content types - each represents a different type of content block.
 * These are immutable value types.
 */

struct Paragraph {
    std::string markdown;
    
    bool operator==(const Paragraph&) const = default;
};

struct Heading {
    int level;  // 1, 2, or 3
    std::string markdown;
    
    bool operator==(const Heading&) const = default;
};

struct Todo {
    bool checked;
    std::string markdown;
    
    bool operator==(const Todo&) const = default;
};

struct Code {
    std::string language;
    std::string content;
    
    bool operator==(const Code&) const = default;
};

struct Quote {
    std::string markdown;
    
    bool operator==(const Quote&) const = default;
};

struct Divider {
    bool operator==(const Divider&) const = default;
};

struct Toggle {
    bool collapsed;
    std::string summary;
    
    bool operator==(const Toggle&) const = default;
};

/**
 * BlockContent - Sum type representing all possible block contents.
 */
using BlockContent = std::variant<
    Paragraph,
    Heading,
    Todo,
    Code,
    Quote,
    Divider,
    Toggle
>;

/**
 * BlockType - Enum for block type identification.
 */
enum class BlockType {
    Paragraph,
    Heading,
    Todo,
    Code,
    Quote,
    Divider,
    Toggle
};

/**
 * Get the BlockType for a BlockContent variant.
 */
[[nodiscard]] constexpr BlockType get_type(const BlockContent& content) {
    return std::visit([](const auto& c) -> BlockType {
        using T = std::decay_t<decltype(c)>;
        if constexpr (std::is_same_v<T, Paragraph>) return BlockType::Paragraph;
        else if constexpr (std::is_same_v<T, Heading>) return BlockType::Heading;
        else if constexpr (std::is_same_v<T, Todo>) return BlockType::Todo;
        else if constexpr (std::is_same_v<T, Code>) return BlockType::Code;
        else if constexpr (std::is_same_v<T, Quote>) return BlockType::Quote;
        else if constexpr (std::is_same_v<T, Divider>) return BlockType::Divider;
        else if constexpr (std::is_same_v<T, Toggle>) return BlockType::Toggle;
    }, content);
}

/**
 * Get the type name as a string.
 */
[[nodiscard]] constexpr std::string_view type_name(BlockType type) {
    switch (type) {
        case BlockType::Paragraph: return "paragraph";
        case BlockType::Heading: return "heading";
        case BlockType::Todo: return "todo";
        case BlockType::Code: return "code";
        case BlockType::Quote: return "quote";
        case BlockType::Divider: return "divider";
        case BlockType::Toggle: return "toggle";
    }
    return "unknown";
}

/**
 * Parse a block type from string.
 */
[[nodiscard]] inline std::optional<BlockType> parse_type(std::string_view name) {
    if (name == "paragraph") return BlockType::Paragraph;
    if (name == "heading") return BlockType::Heading;
    if (name == "todo") return BlockType::Todo;
    if (name == "code") return BlockType::Code;
    if (name == "quote") return BlockType::Quote;
    if (name == "divider") return BlockType::Divider;
    if (name == "toggle") return BlockType::Toggle;
    return std::nullopt;
}

/**
 * Get the markdown/text content from any block type.
 */
[[nodiscard]] inline std::string get_text(const BlockContent& content) {
    return std::visit([](const auto& c) -> std::string {
        using T = std::decay_t<decltype(c)>;
        if constexpr (std::is_same_v<T, Paragraph>) return c.markdown;
        else if constexpr (std::is_same_v<T, Heading>) return c.markdown;
        else if constexpr (std::is_same_v<T, Todo>) return c.markdown;
        else if constexpr (std::is_same_v<T, Code>) return c.content;
        else if constexpr (std::is_same_v<T, Quote>) return c.markdown;
        else if constexpr (std::is_same_v<T, Divider>) return "";
        else if constexpr (std::is_same_v<T, Toggle>) return c.summary;
    }, content);
}

/**
 * Set the text content for a block, returning a new BlockContent.
 */
[[nodiscard]] inline BlockContent with_text(const BlockContent& content, std::string text) {
    return std::visit([&text](const auto& c) -> BlockContent {
        using T = std::decay_t<decltype(c)>;
        if constexpr (std::is_same_v<T, Paragraph>) {
            return Paragraph{std::move(text)};
        } else if constexpr (std::is_same_v<T, Heading>) {
            return Heading{c.level, std::move(text)};
        } else if constexpr (std::is_same_v<T, Todo>) {
            return Todo{c.checked, std::move(text)};
        } else if constexpr (std::is_same_v<T, Code>) {
            return Code{c.language, std::move(text)};
        } else if constexpr (std::is_same_v<T, Quote>) {
            return Quote{std::move(text)};
        } else if constexpr (std::is_same_v<T, Divider>) {
            return Divider{};
        } else if constexpr (std::is_same_v<T, Toggle>) {
            return Toggle{c.collapsed, std::move(text)};
        }
    }, content);
}

/**
 * Block - An immutable block in a page.
 * 
 * Blocks are the fundamental unit of content. They have:
 * - A unique ID
 * - A page they belong to
 * - Optional parent block (for nesting)
 * - Content (one of the BlockContent variants)
 * - Sort order (fractional index for CRDT-friendly ordering)
 * - Timestamps
 */
struct Block {
    Uuid id;
    Uuid page_id;
    std::optional<Uuid> parent_id;
    BlockContent content;
    FractionalIndex sort_order;
    Timestamp created_at;
    Timestamp updated_at;
    
    bool operator==(const Block&) const = default;
};

// ============================================================================
// Pure transformation functions
// ============================================================================

/**
 * Create a new block with the given ID and content.
 */
[[nodiscard]] inline Block create(
    Uuid id,
    Uuid page_id,
    BlockContent content,
    FractionalIndex sort_order,
    std::optional<Uuid> parent_id = std::nullopt
) {
    auto now = Timestamp::now();
    return Block{
        .id = id,
        .page_id = page_id,
        .parent_id = parent_id,
        .content = std::move(content),
        .sort_order = std::move(sort_order),
        .created_at = now,
        .updated_at = now
    };
}

/**
 * Create a new block with updated content.
 */
[[nodiscard]] inline Block with_content(Block block, BlockContent content) {
    block.content = std::move(content);
    block.updated_at = Timestamp::now();
    return block;
}

/**
 * Create a new block with updated parent.
 */
[[nodiscard]] inline Block with_parent(Block block, std::optional<Uuid> parent_id) {
    block.parent_id = parent_id;
    block.updated_at = Timestamp::now();
    return block;
}

/**
 * Create a new block with updated sort order.
 */
[[nodiscard]] inline Block with_sort_order(Block block, FractionalIndex sort_order) {
    block.sort_order = std::move(sort_order);
    block.updated_at = Timestamp::now();
    return block;
}

/**
 * Create a new block with updated page.
 */
[[nodiscard]] inline Block with_page(Block block, Uuid page_id) {
    block.page_id = page_id;
    block.updated_at = Timestamp::now();
    return block;
}

/**
 * Transform a block to a different type while preserving text content.
 * Returns nullopt if the transformation doesn't make sense.
 */
[[nodiscard]] inline std::optional<Block> transform_to(
    const Block& block, 
    BlockType target_type
) {
    auto text = get_text(block.content);
    
    BlockContent new_content;
    switch (target_type) {
        case BlockType::Paragraph:
            new_content = Paragraph{text};
            break;
        case BlockType::Heading:
            new_content = Heading{1, text};
            break;
        case BlockType::Todo:
            new_content = Todo{false, text};
            break;
        case BlockType::Code:
            new_content = Code{"", text};
            break;
        case BlockType::Quote:
            new_content = Quote{text};
            break;
        case BlockType::Divider:
            new_content = Divider{};
            break;
        case BlockType::Toggle:
            new_content = Toggle{false, text};
            break;
    }
    
    return with_content(block, std::move(new_content));
}

/**
 * Get the nesting depth of a block within a block list.
 */
[[nodiscard]] inline int get_depth(
    const Block& block,
    const std::vector<Block>& blocks
) {
    int depth = 0;
    std::optional<Uuid> current_parent = block.parent_id;
    
    while (current_parent.has_value()) {
        ++depth;
        auto it = std::find_if(blocks.begin(), blocks.end(),
            [&](const Block& b) { return b.id == *current_parent; });
        
        if (it == blocks.end()) break;
        current_parent = it->parent_id;
    }
    
    return depth;
}

/**
 * Get all child blocks of a parent block.
 */
[[nodiscard]] inline std::vector<Block> get_children(
    const Uuid& parent_id,
    const std::vector<Block>& blocks
) {
    std::vector<Block> children;
    for (const auto& block : blocks) {
        if (block.parent_id == parent_id) {
            children.push_back(block);
        }
    }
    
    // Sort by sort_order
    std::sort(children.begin(), children.end(),
        [](const Block& a, const Block& b) {
            return a.sort_order < b.sort_order;
        });
    
    return children;
}

/**
 * Get root-level blocks (those with no parent).
 */
[[nodiscard]] inline std::vector<Block> get_root_blocks(
    const std::vector<Block>& blocks
) {
    std::vector<Block> roots;
    for (const auto& block : blocks) {
        if (!block.parent_id.has_value()) {
            roots.push_back(block);
        }
    }
    
    // Sort by sort_order
    std::sort(roots.begin(), roots.end(),
        [](const Block& a, const Block& b) {
            return a.sort_order < b.sort_order;
        });
    
    return roots;
}

/**
 * Flatten a block tree into a depth-first ordered list.
 */
[[nodiscard]] inline std::vector<Block> flatten_tree(
    const std::vector<Block>& blocks
) {
    std::vector<Block> result;
    
    std::function<void(const std::optional<Uuid>&)> visit = 
        [&](const std::optional<Uuid>& parent_id) {
            std::vector<Block> children;
            for (const auto& block : blocks) {
                if (block.parent_id == parent_id) {
                    children.push_back(block);
                }
            }
            
            std::sort(children.begin(), children.end(),
                [](const Block& a, const Block& b) {
                    return a.sort_order < b.sort_order;
                });
            
            for (const auto& child : children) {
                result.push_back(child);
                visit(child.id);
            }
        };
    
    visit(std::nullopt);
    return result;
}

} // namespace zinc::blocks

