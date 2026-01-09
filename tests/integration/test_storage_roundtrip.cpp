#include <catch2/catch_test_macros.hpp>
#include "storage/database.hpp"
#include "storage/migrations.hpp"
#include "storage/block_repository.hpp"
#include "storage/page_repository.hpp"
#include "storage/workspace_repository.hpp"

using namespace zinc;
using namespace zinc::storage;
using namespace zinc::blocks;

TEST_CASE("Storage round-trip: Full document structure", "[integration][storage]") {
    auto db = Database::open_memory().unwrap();
    initialize_database(db);
    
    WorkspaceRepository ws_repo(db);
    PageRepository page_repo(db);
    BlockRepository block_repo(db);
    
    // Create workspace
    auto workspace = create_workspace(Uuid::generate(), "My Notes");
    ws_repo.save_workspace(workspace);
    
    // Create page hierarchy
    auto page1 = create_page(Uuid::generate(), workspace.id, "Projects", 0);
    auto page2 = create_page(Uuid::generate(), workspace.id, "Personal", 1);
    auto subpage = create_page(Uuid::generate(), workspace.id, "Work Project", 0, page1.id);
    
    page_repo.save(page1);
    page_repo.save(page2);
    page_repo.save(subpage);
    
    // Create block structure
    // Page 1: Projects
    //   - Heading: "Current Projects"
    //   - Todo: "Project A" (nested under heading via parent)
    //   - Todo: "Project B"
    
    auto heading = create(Uuid::generate(), page1.id, 
        Heading{1, "Current Projects"}, FractionalIndex("a"));
    auto todo1 = create(Uuid::generate(), page1.id,
        Todo{false, "Project A"}, FractionalIndex("a"), heading.id);
    auto todo2 = create(Uuid::generate(), page1.id,
        Todo{true, "Project B"}, FractionalIndex("b"), heading.id);
    auto para = create(Uuid::generate(), page1.id,
        Paragraph{"Some notes here"}, FractionalIndex("b"));
    
    block_repo.save(heading);
    block_repo.save(todo1);
    block_repo.save(todo2);
    block_repo.save(para);
    
    SECTION("Verify workspace") {
        auto retrieved = ws_repo.get_workspace(workspace.id).unwrap();
        REQUIRE(retrieved.has_value());
        REQUIRE(retrieved->name == "My Notes");
    }
    
    SECTION("Verify page hierarchy") {
        auto root_pages = page_repo.get_root_pages(workspace.id).unwrap();
        REQUIRE(root_pages.size() == 2);
        REQUIRE(root_pages[0].title == "Projects");
        REQUIRE(root_pages[1].title == "Personal");
        
        auto children = page_repo.get_children(workspace.id, page1.id).unwrap();
        REQUIRE(children.size() == 1);
        REQUIRE(children[0].title == "Work Project");
    }
    
    SECTION("Verify block structure") {
        auto all_blocks = block_repo.get_by_page(page1.id).unwrap();
        REQUIRE(all_blocks.size() == 4);
        
        auto root_blocks = block_repo.get_root_blocks(page1.id).unwrap();
        REQUIRE(root_blocks.size() == 2);  // heading and para
        
        auto nested = block_repo.get_children(heading.id).unwrap();
        REQUIRE(nested.size() == 2);  // todo1 and todo2
    }
    
    SECTION("Verify block content types") {
        auto blocks = block_repo.get_by_page(page1.id).unwrap();
        
        int heading_count = 0, todo_count = 0, para_count = 0;
        for (const auto& block : blocks) {
            switch (get_type(block.content)) {
                case BlockType::Heading: heading_count++; break;
                case BlockType::Todo: todo_count++; break;
                case BlockType::Paragraph: para_count++; break;
                default: break;
            }
        }
        
        REQUIRE(heading_count == 1);
        REQUIRE(todo_count == 2);
        REQUIRE(para_count == 1);
    }
    
    SECTION("Update and verify") {
        // Update a todo
        auto updated_todo = with_content(todo1, Todo{true, "Project A - Done!"});
        block_repo.save(updated_todo);
        
        auto retrieved = block_repo.get(todo1.id).unwrap();
        REQUIRE(retrieved.has_value());
        
        auto* todo = std::get_if<Todo>(&retrieved->content);
        REQUIRE(todo != nullptr);
        REQUIRE(todo->checked == true);
        REQUIRE(todo->markdown == "Project A - Done!");
    }
    
    SECTION("Delete cascade") {
        // Delete page should cascade to blocks
        page_repo.remove(page1.id);
        
        auto blocks = block_repo.get_by_page(page1.id).unwrap();
        REQUIRE(blocks.empty());
    }
}

TEST_CASE("Storage round-trip: All block types", "[integration][storage]") {
    auto db = Database::open_memory().unwrap();
    initialize_database(db);
    
    WorkspaceRepository ws_repo(db);
    PageRepository page_repo(db);
    BlockRepository block_repo(db);
    
    auto workspace = create_workspace(Uuid::generate(), "Block Types Test");
    ws_repo.save_workspace(workspace);
    
    auto page = create_page(Uuid::generate(), workspace.id, "Test Page");
    page_repo.save(page);
    
    // Create one of each block type
    std::vector<Block> blocks = {
        create(Uuid::generate(), page.id, 
            Paragraph{"A paragraph with *markdown*"}, FractionalIndex("a")),
        create(Uuid::generate(), page.id,
            Heading{1, "Heading Level 1"}, FractionalIndex("b")),
        create(Uuid::generate(), page.id,
            Heading{2, "Heading Level 2"}, FractionalIndex("c")),
        create(Uuid::generate(), page.id,
            Heading{3, "Heading Level 3"}, FractionalIndex("d")),
        create(Uuid::generate(), page.id,
            Todo{false, "Unchecked todo"}, FractionalIndex("e")),
        create(Uuid::generate(), page.id,
            Todo{true, "Checked todo"}, FractionalIndex("f")),
        create(Uuid::generate(), page.id,
            Code{"python", "print('hello')"}, FractionalIndex("g")),
        create(Uuid::generate(), page.id,
            Code{"", "no language"}, FractionalIndex("h")),
        create(Uuid::generate(), page.id,
            Quote{"A famous quote"}, FractionalIndex("i")),
        create(Uuid::generate(), page.id,
            Divider{}, FractionalIndex("j")),
        create(Uuid::generate(), page.id,
            Toggle{true, "Collapsed toggle"}, FractionalIndex("k")),
        create(Uuid::generate(), page.id,
            Toggle{false, "Expanded toggle"}, FractionalIndex("l")),
    };
    
    // Save all blocks
    auto save_result = block_repo.save_all(blocks);
    REQUIRE(save_result.is_ok());
    
    // Retrieve and verify
    auto retrieved = block_repo.get_by_page(page.id).unwrap();
    REQUIRE(retrieved.size() == blocks.size());
    
    // Verify each block type
    for (size_t i = 0; i < blocks.size(); ++i) {
        const auto& original = blocks[i];
        const auto& loaded = retrieved[i];
        
        REQUIRE(original.id == loaded.id);
        REQUIRE(get_type(original.content) == get_type(loaded.content));
        REQUIRE(get_text(original.content) == get_text(loaded.content));
        
        // Verify type-specific properties
        if (auto* h = std::get_if<Heading>(&original.content)) {
            auto* lh = std::get_if<Heading>(&loaded.content);
            REQUIRE(lh != nullptr);
            REQUIRE(h->level == lh->level);
        }
        
        if (auto* t = std::get_if<Todo>(&original.content)) {
            auto* lt = std::get_if<Todo>(&loaded.content);
            REQUIRE(lt != nullptr);
            REQUIRE(t->checked == lt->checked);
        }
        
        if (auto* c = std::get_if<Code>(&original.content)) {
            auto* lc = std::get_if<Code>(&loaded.content);
            REQUIRE(lc != nullptr);
            REQUIRE(c->language == lc->language);
        }
        
        if (auto* tog = std::get_if<Toggle>(&original.content)) {
            auto* ltog = std::get_if<Toggle>(&loaded.content);
            REQUIRE(ltog != nullptr);
            REQUIRE(tog->collapsed == ltog->collapsed);
        }
    }
}

