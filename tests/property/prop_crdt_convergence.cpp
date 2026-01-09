#include <catch2/catch_test_macros.hpp>
#include <rapidcheck.h>
#include "core/block_types.hpp"
#include "core/fractional_index.hpp"

using namespace zinc;
using namespace zinc::blocks;

// Placeholder for future CRDT property tests
// These will be implemented when the Automerge bridge is complete

namespace rc {

// Generator for BlockType
template<>
struct Arbitrary<BlockType> {
    static Gen<BlockType> arbitrary() {
        return gen::element(
            BlockType::Paragraph,
            BlockType::Heading,
            BlockType::Todo,
            BlockType::Code,
            BlockType::Quote,
            BlockType::Divider,
            BlockType::Toggle
        );
    }
};

// Generator for BlockContent
template<>
struct Arbitrary<BlockContent> {
    static Gen<BlockContent> arbitrary() {
        return gen::oneOf(
            gen::map(gen::arbitrary<std::string>(), 
                [](std::string s) -> BlockContent { return Paragraph{s}; }),
            gen::map(gen::pair(gen::inRange(1, 4), gen::arbitrary<std::string>()),
                [](std::pair<int, std::string> p) -> BlockContent { 
                    return Heading{p.first, p.second}; 
                }),
            gen::map(gen::pair(gen::arbitrary<bool>(), gen::arbitrary<std::string>()),
                [](std::pair<bool, std::string> p) -> BlockContent { 
                    return Todo{p.first, p.second}; 
                }),
            gen::construct<BlockContent>(gen::just(Divider{}))
        );
    }
};

} // namespace rc

TEST_CASE("Property: block type transformation preserves text", "[property][blocks]") {
    rc::check("transform_to preserves text content",
        [](const BlockContent& content, BlockType target_type) {
            auto original_text = get_text(content);
            
            auto id = Uuid::generate();
            auto page_id = Uuid::generate();
            auto block = create(id, page_id, content, FractionalIndex::first());
            
            auto transformed = transform_to(block, target_type);
            
            RC_ASSERT(transformed.has_value());
            
            // Dividers don't preserve text
            if (target_type != BlockType::Divider) {
                RC_ASSERT(get_text(transformed->content) == original_text);
            }
            
            return true;
        }
    );
}

TEST_CASE("Property: with_text preserves non-text properties", "[property][blocks]") {
    rc::check("with_text only changes text",
        [](const BlockContent& content, std::string new_text) {
            auto modified = with_text(content, new_text);
            
            // Type should be preserved
            RC_ASSERT(get_type(content) == get_type(modified));
            
            // Text should be updated
            if (get_type(content) != BlockType::Divider) {
                RC_ASSERT(get_text(modified) == new_text);
            }
            
            // Type-specific properties should be preserved
            if (auto* heading = std::get_if<Heading>(&content)) {
                auto* modified_heading = std::get_if<Heading>(&modified);
                RC_ASSERT(modified_heading != nullptr);
                RC_ASSERT(heading->level == modified_heading->level);
            }
            
            if (auto* todo = std::get_if<Todo>(&content)) {
                auto* modified_todo = std::get_if<Todo>(&modified);
                RC_ASSERT(modified_todo != nullptr);
                RC_ASSERT(todo->checked == modified_todo->checked);
            }
            
            return true;
        }
    );
}

TEST_CASE("Property: block transformations are pure", "[property][blocks]") {
    rc::check("transformations don't modify original",
        [](const BlockContent& content) {
            auto id = Uuid::generate();
            auto page_id = Uuid::generate();
            auto original = create(id, page_id, content, FractionalIndex::first());
            auto original_copy = original;
            
            // Apply various transformations
            auto with_new_content = with_content(original, Paragraph{"new"});
            auto with_new_parent = with_parent(original, Uuid::generate());
            auto with_new_order = with_sort_order(original, FractionalIndex("z"));
            
            // Original should be unchanged
            RC_ASSERT(original.id == original_copy.id);
            RC_ASSERT(get_text(original.content) == get_text(original_copy.content));
            RC_ASSERT(original.parent_id == original_copy.parent_id);
            RC_ASSERT(original.sort_order == original_copy.sort_order);
            
            return true;
        }
    );
}

// Placeholder for future CRDT convergence tests
TEST_CASE("Property: CRDT convergence (placeholder)", "[property][crdt]") {
    // TODO: Implement when Automerge bridge is complete
    // 
    // rc::check("concurrent edits converge to same state",
    //     [](std::vector<Edit> edits_a, std::vector<Edit> edits_b) {
    //         auto doc_a = Document::create().unwrap();
    //         auto doc_b = Document::create().unwrap();
    //         
    //         // Apply edits concurrently
    //         for (const auto& e : edits_a) doc_a = apply_edit(doc_a, e);
    //         for (const auto& e : edits_b) doc_b = apply_edit(doc_b, e);
    //         
    //         // Sync both ways
    //         auto synced_a = doc_a.merge(doc_b).unwrap();
    //         auto synced_b = doc_b.merge(doc_a).unwrap();
    //         
    //         // Must converge to same state
    //         RC_ASSERT(synced_a.get_text() == synced_b.get_text());
    //         return true;
    //     }
    // );
    
    SUCCEED("CRDT tests pending Automerge integration");
}

