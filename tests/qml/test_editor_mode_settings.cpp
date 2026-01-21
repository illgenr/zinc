#include <catch2/catch_test_macros.hpp>

#include <QSettings>

#include "ui/DataStore.hpp"

namespace {

constexpr auto kKeyEditorMode = "ui/editor_mode";

} // namespace

TEST_CASE("Editor mode setting: defaults to hybrid", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyEditorMode));

    zinc::ui::DataStore store;
    REQUIRE(store.editorMode() == 0);
}

TEST_CASE("Editor mode setting: persists and normalizes", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyEditorMode));

    zinc::ui::DataStore store;

    store.setEditorMode(1);
    REQUIRE(settings.value(QString::fromLatin1(kKeyEditorMode)).toInt() == 1);
    REQUIRE(store.editorMode() == 1);

    store.setEditorMode(999);
    REQUIRE(store.editorMode() == 0);
}

