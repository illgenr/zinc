#include <catch2/catch_test_macros.hpp>

#include <QSettings>

#include "ui/DataStore.hpp"

namespace {

constexpr auto kKeyStartupMode = "ui/startup_mode";
constexpr auto kKeyLastViewedCursorPageId = "ui/last_viewed_cursor_page_id";
constexpr auto kKeyLastViewedCursorBlockIndex = "ui/last_viewed_cursor_block_index";
constexpr auto kKeyLastViewedCursorPos = "ui/last_viewed_cursor_pos";

} // namespace

TEST_CASE("Startup cursor settings: defaults empty", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyStartupMode));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorPageId));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorBlockIndex));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorPos));

    zinc::ui::DataStore store;

    const auto cursor = store.lastViewedCursor();
    REQUIRE(cursor.value(QStringLiteral("pageId")).toString().isEmpty());
    REQUIRE(cursor.value(QStringLiteral("blockIndex")).toInt() == -1);
    REQUIRE(cursor.value(QStringLiteral("cursorPos")).toInt() == -1);
}

TEST_CASE("Startup cursor settings: persists last viewed cursor", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyStartupMode));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorPageId));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorBlockIndex));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorPos));

    zinc::ui::DataStore store;
    store.setLastViewedCursor(QStringLiteral("page-1"), 4, 12);

    REQUIRE(settings.value(QString::fromLatin1(kKeyLastViewedCursorPageId)).toString() == QStringLiteral("page-1"));
    REQUIRE(settings.value(QString::fromLatin1(kKeyLastViewedCursorBlockIndex)).toInt() == 4);
    REQUIRE(settings.value(QString::fromLatin1(kKeyLastViewedCursorPos)).toInt() == 12);
}

TEST_CASE("Startup cursor settings: resolves startup cursor hint", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyStartupMode));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorPageId));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorBlockIndex));
    settings.remove(QString::fromLatin1(kKeyLastViewedCursorPos));

    zinc::ui::DataStore store;

    SECTION("Last viewed mode uses saved cursor when page matches") {
        store.setStartupPageMode(0);
        store.setLastViewedCursor(QStringLiteral("page-1"), 2, 9);

        const auto hint = store.resolveStartupCursorHint(QStringLiteral("page-1"));
        REQUIRE(hint.value(QStringLiteral("pageId")).toString() == QStringLiteral("page-1"));
        REQUIRE(hint.value(QStringLiteral("blockIndex")).toInt() == 2);
        REQUIRE(hint.value(QStringLiteral("cursorPos")).toInt() == 9);
    }

    SECTION("Last viewed mode falls back to start when cursor is missing or mismatched") {
        store.setStartupPageMode(0);
        store.setLastViewedCursor(QStringLiteral("page-2"), 2, 9);

        const auto hint = store.resolveStartupCursorHint(QStringLiteral("page-1"));
        REQUIRE(hint.value(QStringLiteral("pageId")).toString() == QStringLiteral("page-1"));
        REQUIRE(hint.value(QStringLiteral("blockIndex")).toInt() == 0);
        REQUIRE(hint.value(QStringLiteral("cursorPos")).toInt() == 0);
    }

    SECTION("Fixed mode always focuses start") {
        store.setStartupPageMode(1);
        store.setLastViewedCursor(QStringLiteral("page-1"), 2, 9);

        const auto hint = store.resolveStartupCursorHint(QStringLiteral("page-1"));
        REQUIRE(hint.value(QStringLiteral("pageId")).toString() == QStringLiteral("page-1"));
        REQUIRE(hint.value(QStringLiteral("blockIndex")).toInt() == 0);
        REQUIRE(hint.value(QStringLiteral("cursorPos")).toInt() == 0);
    }
}

