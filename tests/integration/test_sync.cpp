#include <catch2/catch_test_macros.hpp>
#include "storage/database.hpp"
#include "storage/migrations.hpp"
#include "storage/block_repository.hpp"
#include "storage/page_repository.hpp"
#include "storage/workspace_repository.hpp"
#include "storage/crdt_repository.hpp"

using namespace zinc;
using namespace zinc::storage;
using namespace zinc::blocks;

// Placeholder integration tests for sync functionality
// These will be expanded when network layer is complete

TEST_CASE("Sync: CRDT document persistence", "[integration][sync]") {
    auto db = Database::open_memory().unwrap();
    initialize_database(db);
    
    WorkspaceRepository ws_repo(db);
    PageRepository page_repo(db);
    CrdtRepository crdt_repo(db);
    
    auto workspace = create_workspace(Uuid::generate(), "Sync Test");
    ws_repo.save_workspace(workspace);
    
    auto page = create_page(Uuid::generate(), workspace.id, "Test Page");
    page_repo.save(page);
    
    SECTION("Save and retrieve CRDT document") {
        CrdtDocument doc{
            .doc_id = page.crdt_doc_id,
            .page_id = page.id,
            .snapshot = {0x01, 0x02, 0x03},  // Placeholder binary
            .vector_clock_json = R"({"device1": 5})",
            .updated_at = Timestamp::now()
        };
        
        auto save_result = crdt_repo.save_document(doc);
        REQUIRE(save_result.is_ok());
        
        auto get_result = crdt_repo.get_document(doc.doc_id);
        REQUIRE(get_result.is_ok());
        REQUIRE(get_result.unwrap().has_value());
        REQUIRE(get_result.unwrap()->snapshot == doc.snapshot);
    }
    
    SECTION("Save and retrieve CRDT changes") {
        CrdtDocument doc{
            .doc_id = page.crdt_doc_id,
            .page_id = page.id,
            .snapshot = {},
            .vector_clock_json = "{}",
            .updated_at = Timestamp::now()
        };
        crdt_repo.save_document(doc);
        
        CrdtChange change{
            .id = 0,
            .doc_id = doc.doc_id,
            .change_bytes = {0xAA, 0xBB, 0xCC},
            .actor_id = "device1",
            .seq_num = 1,
            .created_at = Timestamp::now(),
            .synced_to_json = "{}"
        };
        
        auto save_result = crdt_repo.save_change(change);
        REQUIRE(save_result.is_ok());
        
        auto changes = crdt_repo.get_changes(doc.doc_id);
        REQUIRE(changes.is_ok());
        REQUIRE(changes.unwrap().size() == 1);
        REQUIRE(changes.unwrap()[0].actor_id == "device1");
    }
    
    SECTION("Get unsynced changes") {
        CrdtDocument doc{
            .doc_id = page.crdt_doc_id,
            .page_id = page.id,
            .snapshot = {},
            .vector_clock_json = "{}",
            .updated_at = Timestamp::now()
        };
        crdt_repo.save_document(doc);
        
        // Save a change that hasn't been synced
        CrdtChange change{
            .id = 0,
            .doc_id = doc.doc_id,
            .change_bytes = {0x01},
            .actor_id = "device1",
            .seq_num = 1,
            .created_at = Timestamp::now(),
            .synced_to_json = "{}"
        };
        crdt_repo.save_change(change);
        
        auto unsynced = crdt_repo.get_unsynced_changes(doc.doc_id, "device2");
        REQUIRE(unsynced.is_ok());
        REQUIRE(unsynced.unwrap().size() == 1);
    }
}

TEST_CASE("Sync: Simulated multi-device scenario", "[integration][sync]") {
    // Create two separate databases simulating two devices
    auto db1 = Database::open_memory().unwrap();
    auto db2 = Database::open_memory().unwrap();
    
    initialize_database(db1);
    initialize_database(db2);
    
    // Device 1 creates a workspace and page
    WorkspaceRepository ws_repo1(db1);
    PageRepository page_repo1(db1);
    BlockRepository block_repo1(db1);
    
    auto workspace_id = Uuid::generate();
    auto page_id = Uuid::generate();
    
    auto workspace = create_workspace(workspace_id, "Shared Workspace");
    ws_repo1.save_workspace(workspace);
    
    auto page = create_page(page_id, workspace_id, "Shared Page");
    page_repo1.save(page);
    
    auto block1 = create(
        Uuid::generate(), 
        page_id, 
        Paragraph{"Hello from device 1"}, 
        FractionalIndex("a")
    );
    block_repo1.save(block1);
    
    // Simulate sync: Copy workspace, page, and blocks to device 2
    WorkspaceRepository ws_repo2(db2);
    PageRepository page_repo2(db2);
    BlockRepository block_repo2(db2);
    
    ws_repo2.save_workspace(workspace);
    page_repo2.save(page);
    block_repo2.save(block1);
    
    // Device 2 adds a new block
    auto block2 = create(
        Uuid::generate(),
        page_id,
        Paragraph{"Hello from device 2"},
        FractionalIndex("b")
    );
    block_repo2.save(block2);
    
    // Verify device 2 has both blocks
    auto blocks_on_2 = block_repo2.get_by_page(page_id);
    REQUIRE(blocks_on_2.is_ok());
    REQUIRE(blocks_on_2.unwrap().size() == 2);
    
    // Simulate sync back: Device 1 receives block2
    block_repo1.save(block2);
    
    // Both devices should now have the same content
    auto blocks_on_1 = block_repo1.get_by_page(page_id);
    REQUIRE(blocks_on_1.is_ok());
    REQUIRE(blocks_on_1.unwrap().size() == 2);
    
    // Verify order is preserved
    REQUIRE(get_text(blocks_on_1.unwrap()[0].content) == "Hello from device 1");
    REQUIRE(get_text(blocks_on_1.unwrap()[1].content) == "Hello from device 2");
}

