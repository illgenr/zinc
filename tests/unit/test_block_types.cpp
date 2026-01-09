#include <catch2/catch_test_macros.hpp>
#include "core/block_types.hpp"

using namespace zinc;
using namespace zinc::blocks;

TEST_CASE("Block creation", "[blocks]") {
    auto id = Uuid::generate();
    auto page_id = Uuid::generate();
    auto sort_order = FractionalIndex::first();
    
    auto block = create(id, page_id, Paragraph{"Hello, world!"}, sort_order);
    
    REQUIRE(block.id == id);
    REQUIRE(block.page_id == page_id);
    REQUIRE_FALSE(block.parent_id.has_value());
    REQUIRE(block.sort_order == sort_order);
    REQUIRE(get_type(block.content) == BlockType::Paragraph);
}

TEST_CASE("BlockContent variants", "[blocks]") {
    SECTION("Paragraph") {
        BlockContent content = Paragraph{"Some text"};
        REQUIRE(get_type(content) == BlockType::Paragraph);
        REQUIRE(get_text(content) == "Some text");
    }
    
    SECTION("Heading") {
        BlockContent content = Heading{2, "Title"};
        REQUIRE(get_type(content) == BlockType::Heading);
        REQUIRE(get_text(content) == "Title");
        REQUIRE(std::get<Heading>(content).level == 2);
    }
    
    SECTION("Todo") {
        BlockContent content = Todo{true, "Task"};
        REQUIRE(get_type(content) == BlockType::Todo);
        REQUIRE(get_text(content) == "Task");
        REQUIRE(std::get<Todo>(content).checked == true);
    }
    
    SECTION("Code") {
        BlockContent content = Code{"cpp", "int main() {}"};
        REQUIRE(get_type(content) == BlockType::Code);
        REQUIRE(get_text(content) == "int main() {}");
        REQUIRE(std::get<Code>(content).language == "cpp");
    }
    
    SECTION("Quote") {
        BlockContent content = Quote{"A wise saying"};
        REQUIRE(get_type(content) == BlockType::Quote);
        REQUIRE(get_text(content) == "A wise saying");
    }
    
    SECTION("Divider") {
        BlockContent content = Divider{};
        REQUIRE(get_type(content) == BlockType::Divider);
        REQUIRE(get_text(content) == "");
    }
    
    SECTION("Toggle") {
        BlockContent content = Toggle{false, "Summary"};
        REQUIRE(get_type(content) == BlockType::Toggle);
        REQUIRE(get_text(content) == "Summary");
        REQUIRE(std::get<Toggle>(content).collapsed == false);
    }
}

TEST_CASE("Block transformations are pure", "[blocks]") {
    auto id = Uuid::generate();
    auto page_id = Uuid::generate();
    auto original = create(id, page_id, Paragraph{"Original"}, FractionalIndex::first());
    
    SECTION("with_content returns new block") {
        auto modified = with_content(original, Paragraph{"Modified"});
        
        REQUIRE(get_text(original.content) == "Original");
        REQUIRE(get_text(modified.content) == "Modified");
        REQUIRE(modified.id == original.id);
    }
    
    SECTION("with_parent returns new block") {
        auto parent_id = Uuid::generate();
        auto modified = with_parent(original, parent_id);
        
        REQUIRE_FALSE(original.parent_id.has_value());
        REQUIRE(modified.parent_id.has_value());
        REQUIRE(*modified.parent_id == parent_id);
    }
    
    SECTION("with_sort_order returns new block") {
        auto new_order = FractionalIndex("z");
        auto modified = with_sort_order(original, new_order);
        
        REQUIRE(original.sort_order == FractionalIndex::first());
        REQUIRE(modified.sort_order == new_order);
    }
}

TEST_CASE("Block type transformation", "[blocks]") {
    auto id = Uuid::generate();
    auto page_id = Uuid::generate();
    auto block = create(id, page_id, Paragraph{"My text"}, FractionalIndex::first());
    
    SECTION("Paragraph to Heading") {
        auto result = transform_to(block, BlockType::Heading);
        REQUIRE(result.has_value());
        REQUIRE(get_type(result->content) == BlockType::Heading);
        REQUIRE(get_text(result->content) == "My text");
    }
    
    SECTION("Paragraph to Todo") {
        auto result = transform_to(block, BlockType::Todo);
        REQUIRE(result.has_value());
        REQUIRE(get_type(result->content) == BlockType::Todo);
        REQUIRE(std::get<Todo>(result->content).checked == false);
    }
    
    SECTION("Paragraph to Divider loses text") {
        auto result = transform_to(block, BlockType::Divider);
        REQUIRE(result.has_value());
        REQUIRE(get_type(result->content) == BlockType::Divider);
        REQUIRE(get_text(result->content) == "");
    }
}

TEST_CASE("with_text preserves block properties", "[blocks]") {
    SECTION("Heading preserves level") {
        BlockContent content = Heading{2, "Old"};
        auto modified = with_text(content, "New");
        
        REQUIRE(get_text(modified) == "New");
        REQUIRE(std::get<Heading>(modified).level == 2);
    }
    
    SECTION("Todo preserves checked state") {
        BlockContent content = Todo{true, "Old"};
        auto modified = with_text(content, "New");
        
        REQUIRE(get_text(modified) == "New");
        REQUIRE(std::get<Todo>(modified).checked == true);
    }
    
    SECTION("Code preserves language") {
        BlockContent content = Code{"rust", "old code"};
        auto modified = with_text(content, "new code");
        
        REQUIRE(get_text(modified) == "new code");
        REQUIRE(std::get<Code>(modified).language == "rust");
    }
}

TEST_CASE("type_name and parse_type", "[blocks]") {
    REQUIRE(type_name(BlockType::Paragraph) == "paragraph");
    REQUIRE(type_name(BlockType::Heading) == "heading");
    REQUIRE(type_name(BlockType::Todo) == "todo");
    REQUIRE(type_name(BlockType::Code) == "code");
    REQUIRE(type_name(BlockType::Quote) == "quote");
    REQUIRE(type_name(BlockType::Divider) == "divider");
    REQUIRE(type_name(BlockType::Toggle) == "toggle");
    
    REQUIRE(parse_type("paragraph") == BlockType::Paragraph);
    REQUIRE(parse_type("heading") == BlockType::Heading);
    REQUIRE(parse_type("invalid") == std::nullopt);
}

TEST_CASE("Block tree operations", "[blocks]") {
    auto page_id = Uuid::generate();
    
    // Create a tree structure:
    // - root1
    //   - child1
    //   - child2
    // - root2
    
    auto root1 = create(Uuid::generate(), page_id, Paragraph{"Root 1"}, 
                        FractionalIndex("a"));
    auto root2 = create(Uuid::generate(), page_id, Paragraph{"Root 2"}, 
                        FractionalIndex("b"));
    auto child1 = create(Uuid::generate(), page_id, Paragraph{"Child 1"}, 
                         FractionalIndex("a"), root1.id);
    auto child2 = create(Uuid::generate(), page_id, Paragraph{"Child 2"}, 
                         FractionalIndex("b"), root1.id);
    
    std::vector<Block> blocks = {root1, root2, child1, child2};
    
    SECTION("get_root_blocks returns only root blocks") {
        auto roots = get_root_blocks(blocks);
        REQUIRE(roots.size() == 2);
        REQUIRE(roots[0].id == root1.id);
        REQUIRE(roots[1].id == root2.id);
    }
    
    SECTION("get_children returns child blocks") {
        auto children = get_children(root1.id, blocks);
        REQUIRE(children.size() == 2);
        REQUIRE(children[0].id == child1.id);
        REQUIRE(children[1].id == child2.id);
    }
    
    SECTION("get_depth calculates nesting level") {
        REQUIRE(get_depth(root1, blocks) == 0);
        REQUIRE(get_depth(child1, blocks) == 1);
    }
    
    SECTION("flatten_tree returns depth-first order") {
        auto flattened = flatten_tree(blocks);
        REQUIRE(flattened.size() == 4);
        REQUIRE(flattened[0].id == root1.id);
        REQUIRE(flattened[1].id == child1.id);
        REQUIRE(flattened[2].id == child2.id);
        REQUIRE(flattened[3].id == root2.id);
    }
}

