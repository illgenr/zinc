#include <catch2/catch_test_macros.hpp>

#include <QQmlEngine>

#include "ui/DataStore.hpp"

TEST_CASE("DataStore singleton is parented to the QQmlEngine", "[qml][datastore]") {
    QQmlEngine engine;
    auto* store = zinc::ui::DataStore::create(&engine, nullptr);
    REQUIRE(store != nullptr);
    REQUIRE(store->parent() == &engine);
}

