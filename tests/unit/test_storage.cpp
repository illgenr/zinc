#include <catch2/catch_test_macros.hpp>
#include "storage/database.hpp"
#include "storage/migrations.hpp"
#include "storage/block_repository.hpp"
#include "storage/page_repository.hpp"
#include "storage/workspace_repository.hpp"

using namespace zinc;
using namespace zinc::storage;
using namespace zinc::blocks;

TEST_CASE("Database basic operations", "[storage]") {
    auto db_result = Database::open_memory();
    REQUIRE(db_result.is_ok());
    auto db = std::move(db_result).unwrap();
    
    SECTION("Execute creates table") {
        auto result = db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY);");
        REQUIRE(result.is_ok());
    }
    
    SECTION("Prepare and step") {
        db.execute("CREATE TABLE test (id INTEGER, name TEXT);");
        db.execute("INSERT INTO test VALUES (1, 'Alice');");
        db.execute("INSERT INTO test VALUES (2, 'Bob');");
        
        auto stmt = db.prepare("SELECT * FROM test ORDER BY id;").unwrap();
        
        REQUIRE(stmt.step().unwrap() == true);
        REQUIRE(stmt.column_int(0) == 1);
        REQUIRE(stmt.column_text(1) == "Alice");
        
        REQUIRE(stmt.step().unwrap() == true);
        REQUIRE(stmt.column_int(0) == 2);
        REQUIRE(stmt.column_text(1) == "Bob");
        
        REQUIRE(stmt.step().unwrap() == false);
    }
    
    SECTION("Transaction commit") {
        db.execute("CREATE TABLE test (id INTEGER);");
        
        auto result = db.transaction([&]() -> Result<void, Error> {
            db.execute("INSERT INTO test VALUES (1);");
            db.execute("INSERT INTO test VALUES (2);");
            return Result<void, Error>::ok();
        });
        
        REQUIRE(result.is_ok());
        
        auto stmt = db.prepare("SELECT COUNT(*) FROM test;").unwrap();
        stmt.step();
        REQUIRE(stmt.column_int(0) == 2);
    }
    
    SECTION("Transaction rollback on error") {
        db.execute("CREATE TABLE test (id INTEGER);");
        db.execute("INSERT INTO test VALUES (1);");
        
        auto result = db.transaction([&]() -> Result<void, Error> {
            db.execute("INSERT INTO test VALUES (2);");
            return Result<void, Error>::err(Error{"forced error"});
        });
        
        REQUIRE(result.is_err());
        
        auto stmt = db.prepare("SELECT COUNT(*) FROM test;").unwrap();
        stmt.step();
        REQUIRE(stmt.column_int(0) == 1);  // Rollback happened
    }
}

TEST_CASE("Migrations", "[storage]") {
    auto db = Database::open_memory().unwrap();
    MigrationRunner runner(db);
    
    SECTION("Initial version is 0") {
        auto version = runner.current_version();
        REQUIRE(version.is_ok());
        REQUIRE(version.unwrap() == 0);
    }
    
    SECTION("Migrate to latest") {
        auto result = runner.migrate();
        REQUIRE(result.is_ok());
        
        auto version = runner.current_version();
        REQUIRE(version.unwrap() == MigrationRunner::latest_version());
    }
    
    SECTION("Migrate is idempotent") {
        runner.migrate();
        runner.migrate();
        
        auto version = runner.current_version();
        REQUIRE(version.unwrap() == MigrationRunner::latest_version());
    }
}

TEST_CASE("WorkspaceRepository", "[storage]") {
    auto db = Database::open_memory().unwrap();
    initialize_database(db);
    
    WorkspaceRepository repo(db);
    
    auto workspace = create_workspace(Uuid::generate(), "Test Workspace");
    
    SECTION("Save and get workspace") {
        auto save_result = repo.save_workspace(workspace);
        REQUIRE(save_result.is_ok());
        
        auto get_result = repo.get_workspace(workspace.id);
        REQUIRE(get_result.is_ok());
        REQUIRE(get_result.unwrap().has_value());
        REQUIRE(get_result.unwrap()->name == "Test Workspace");
    }
    
    SECTION("Get all workspaces") {
        repo.save_workspace(workspace);
        
        auto result = repo.get_all_workspaces();
        REQUIRE(result.is_ok());
        REQUIRE(result.unwrap().size() >= 1);
    }
    
    SECTION("Remove workspace") {
        repo.save_workspace(workspace);
        
        auto remove_result = repo.remove_workspace(workspace.id);
        REQUIRE(remove_result.is_ok());
        
        auto get_result = repo.get_workspace(workspace.id);
        REQUIRE_FALSE(get_result.unwrap().has_value());
    }
}

TEST_CASE("PageRepository", "[storage]") {
    auto db = Database::open_memory().unwrap();
    initialize_database(db);
    
    WorkspaceRepository workspace_repo(db);
    PageRepository repo(db);
    
    auto workspace = create_workspace(Uuid::generate(), "Test");
    workspace_repo.save_workspace(workspace);
    
    auto page = create_page(Uuid::generate(), workspace.id, "Test Page");
    
    SECTION("Save and get page") {
        auto save_result = repo.save(page);
        REQUIRE(save_result.is_ok());
        
        auto get_result = repo.get(page.id);
        REQUIRE(get_result.is_ok());
        REQUIRE(get_result.unwrap().has_value());
        REQUIRE(get_result.unwrap()->title == "Test Page");
    }
    
    SECTION("Get root pages") {
        repo.save(page);
        
        auto result = repo.get_root_pages(workspace.id);
        REQUIRE(result.is_ok());
        REQUIRE(result.unwrap().size() == 1);
    }
    
    SECTION("Child pages") {
        repo.save(page);
        
        auto child = create_page(Uuid::generate(), workspace.id, "Child", 0, page.id);
        repo.save(child);
        
        auto children = repo.get_children(workspace.id, page.id);
        REQUIRE(children.is_ok());
        REQUIRE(children.unwrap().size() == 1);
        REQUIRE(children.unwrap()[0].title == "Child");
    }
}

TEST_CASE("BlockRepository", "[storage]") {
    auto db = Database::open_memory().unwrap();
    initialize_database(db);
    
    WorkspaceRepository workspace_repo(db);
    PageRepository page_repo(db);
    BlockRepository repo(db);
    
    auto workspace = create_workspace(Uuid::generate(), "Test");
    workspace_repo.save_workspace(workspace);
    
    auto page = create_page(Uuid::generate(), workspace.id, "Test Page");
    page_repo.save(page);
    
    SECTION("Save and get block") {
        auto block = create(
            Uuid::generate(), 
            page.id, 
            Paragraph{"Hello"}, 
            FractionalIndex::first()
        );
        
        auto save_result = repo.save(block);
        REQUIRE(save_result.is_ok());
        
        auto get_result = repo.get(block.id);
        REQUIRE(get_result.is_ok());
        REQUIRE(get_result.unwrap().has_value());
        
        auto& retrieved = *get_result.unwrap();
        REQUIRE(get_text(retrieved.content) == "Hello");
        REQUIRE(get_type(retrieved.content) == BlockType::Paragraph);
    }
    
    SECTION("Different block types") {
        std::vector<Block> blocks = {
            create(Uuid::generate(), page.id, Paragraph{"Para"}, FractionalIndex("a")),
            create(Uuid::generate(), page.id, Heading{2, "Head"}, FractionalIndex("b")),
            create(Uuid::generate(), page.id, Todo{true, "Task"}, FractionalIndex("c")),
            create(Uuid::generate(), page.id, Code{"cpp", "code"}, FractionalIndex("d")),
            create(Uuid::generate(), page.id, Quote{"Quote"}, FractionalIndex("e")),
            create(Uuid::generate(), page.id, Divider{}, FractionalIndex("f")),
            create(Uuid::generate(), page.id, Toggle{false, "Toggle"}, FractionalIndex("g")),
        };
        
        for (const auto& block : blocks) {
            repo.save(block);
        }
        
        auto result = repo.get_by_page(page.id);
        REQUIRE(result.is_ok());
        REQUIRE(result.unwrap().size() == 7);
        
        // Verify types
        auto& retrieved = result.unwrap();
        REQUIRE(get_type(retrieved[0].content) == BlockType::Paragraph);
        REQUIRE(get_type(retrieved[1].content) == BlockType::Heading);
        REQUIRE(std::get<Heading>(retrieved[1].content).level == 2);
        REQUIRE(get_type(retrieved[2].content) == BlockType::Todo);
        REQUIRE(std::get<Todo>(retrieved[2].content).checked == true);
        REQUIRE(get_type(retrieved[3].content) == BlockType::Code);
        REQUIRE(std::get<Code>(retrieved[3].content).language == "cpp");
    }
    
    SECTION("Block nesting") {
        auto parent = create(Uuid::generate(), page.id, Paragraph{"Parent"}, 
                            FractionalIndex("a"));
        auto child = create(Uuid::generate(), page.id, Paragraph{"Child"}, 
                           FractionalIndex("a"), parent.id);
        
        repo.save(parent);
        repo.save(child);
        
        auto roots = repo.get_root_blocks(page.id);
        REQUIRE(roots.is_ok());
        REQUIRE(roots.unwrap().size() == 1);
        
        auto children = repo.get_children(parent.id);
        REQUIRE(children.is_ok());
        REQUIRE(children.unwrap().size() == 1);
    }
    
    SECTION("Update block") {
        auto block = create(Uuid::generate(), page.id, Paragraph{"Original"}, 
                           FractionalIndex::first());
        repo.save(block);
        
        auto updated = with_content(block, Paragraph{"Updated"});
        repo.save(updated);
        
        auto result = repo.get(block.id);
        REQUIRE(get_text(result.unwrap()->content) == "Updated");
    }
    
    SECTION("Delete block") {
        auto block = create(Uuid::generate(), page.id, Paragraph{"Delete me"}, 
                           FractionalIndex::first());
        repo.save(block);
        
        repo.remove(block.id);
        
        auto result = repo.get(block.id);
        REQUIRE_FALSE(result.unwrap().has_value());
    }
    
    SECTION("Count blocks") {
        repo.save(create(Uuid::generate(), page.id, Paragraph{""}, FractionalIndex("a")));
        repo.save(create(Uuid::generate(), page.id, Paragraph{""}, FractionalIndex("b")));
        repo.save(create(Uuid::generate(), page.id, Paragraph{""}, FractionalIndex("c")));
        
        auto count = repo.count_by_page(page.id);
        REQUIRE(count.is_ok());
        REQUIRE(count.unwrap() == 3);
    }
}

