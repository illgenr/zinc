#include <catch2/catch_test_macros.hpp>

#include "ui/controllers/sync_presence.hpp"

TEST_CASE("SyncPresence: parses cursor payload", "[qml][sync]") {
    const auto payload = QByteArray(
        R"({"autoSyncEnabled":true,"pageId":"p1","blockIndex":3,"cursorPos":7,"titlePreview":"Draft"})");

    const auto parsed = zinc::ui::parseSyncPresence(payload);
    REQUIRE(parsed.has_value());
    REQUIRE(parsed->auto_sync_enabled == true);
    REQUIRE(parsed->page_id == QStringLiteral("p1"));
    REQUIRE(parsed->block_index == 3);
    REQUIRE(parsed->cursor_pos == 7);
    REQUIRE(parsed->title_preview == QStringLiteral("Draft"));
}

TEST_CASE("SyncPresence: serializes title preview payload", "[qml][sync]") {
    zinc::ui::SyncPresence presence;
    presence.auto_sync_enabled = true;
    presence.page_id = QStringLiteral("p1");
    presence.block_index = 1;
    presence.cursor_pos = 2;
    presence.title_preview = QStringLiteral("Live title");

    const auto payload = zinc::ui::serializeSyncPresence(presence);
    const auto parsed = zinc::ui::parseSyncPresence(payload);
    REQUIRE(parsed.has_value());
    REQUIRE(parsed->title_preview == QStringLiteral("Live title"));
    REQUIRE(parsed->page_id == QStringLiteral("p1"));
}
