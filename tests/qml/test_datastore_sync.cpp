#include <catch2/catch_test_macros.hpp>

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include "ui/DataStore.hpp"

namespace {

QVariantMap makePage(const QString& pageId, const QVariant& title) {
    QVariantMap page;
    page.insert("pageId", pageId);
    page.insert("title", title);
    page.insert("parentId", "");
    page.insert("depth", 0);
    page.insert("sortOrder", 0);
    return page;
}

QVariantMap makeBlock(const QString& pageId,
                      const QString& blockId,
                      const QString& content,
                      const QString& updatedAt) {
    QVariantMap block;
    block.insert("blockId", blockId);
    block.insert("pageId", pageId);
    block.insert("blockType", "paragraph");
    block.insert("content", content);
    block.insert("depth", 0);
    block.insert("checked", false);
    block.insert("collapsed", false);
    block.insert("language", "");
    block.insert("headingLevel", 0);
    block.insert("sortOrder", 0);
    block.insert("updatedAt", updatedAt);
    return block;
}

QString titleForPage(zinc::ui::DataStore& store, const QString& pageId) {
    const auto pages = store.getAllPages();
    for (const auto& entry : pages) {
        const auto page = entry.toMap();
        if (page.value("pageId").toString() == pageId) {
            return page.value("title").toString();
        }
    }
    return {};
}

QString contentForBlock(zinc::ui::DataStore& store,
                        const QString& pageId,
                        const QString& blockId) {
    const auto blocks = store.getBlocksForPage(pageId);
    for (const auto& entry : blocks) {
        const auto block = entry.toMap();
        if (block.value("blockId").toString() == blockId) {
            return block.value("content").toString();
        }
    }
    return {};
}

} // namespace

TEST_CASE("DataStore: saveAllPages coerces null title to Untitled", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantList first;
    first.append(makePage("p1", QStringLiteral("Hello")));
    store.saveAllPages(first);
    REQUIRE(titleForPage(store, "p1") == QStringLiteral("Hello"));

    QVariantList second;
    second.append(makePage("p1", QVariant()));
    store.saveAllPages(second);
    REQUIRE(titleForPage(store, "p1") == QStringLiteral("Untitled"));
}

TEST_CASE("DataStore: applyPageUpdates coerces null title to Untitled", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantMap incoming = makePage("p2", QVariant());
    incoming.insert("updatedAt", QStringLiteral("2026-01-11 00:00:00"));

    QVariantList pages;
    pages.append(incoming);
    store.applyPageUpdates(pages);

    REQUIRE(titleForPage(store, "p2") == QStringLiteral("Untitled"));
}

TEST_CASE("DataStore: applyBlockUpdates updates content", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantList pages;
    pages.append(makePage("p3", QStringLiteral("Page")));
    store.saveAllPages(pages);

    QVariantList blocks1;
    blocks1.append(makeBlock("p3", "b1", "Hello", "2026-01-11 00:00:00"));
    store.applyBlockUpdates(blocks1);
    REQUIRE(contentForBlock(store, "p3", "b1") == QStringLiteral("Hello"));

    QVariantList blocks2;
    blocks2.append(makeBlock("p3", "b1", "World", "2026-01-11 00:00:01"));
    store.applyBlockUpdates(blocks2);
    REQUIRE(contentForBlock(store, "p3", "b1") == QStringLiteral("World"));
}

TEST_CASE("DataStore: applyPageUpdates allows equal updatedAt to overwrite", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const QString timestamp = QStringLiteral("2026-01-11 00:00:00");

    QVariantMap first = makePage("p4", QStringLiteral("H"));
    first.insert("updatedAt", timestamp);
    QVariantList pages1;
    pages1.append(first);
    store.applyPageUpdates(pages1);
    REQUIRE(titleForPage(store, "p4") == QStringLiteral("H"));

    QVariantMap second = makePage("p4", QStringLiteral("He"));
    second.insert("updatedAt", timestamp);
    QVariantList pages2;
    pages2.append(second);
    store.applyPageUpdates(pages2);
    REQUIRE(titleForPage(store, "p4") == QStringLiteral("He"));
}

TEST_CASE("DataStore: applyBlockUpdates allows equal updatedAt to overwrite", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantList pages;
    pages.append(makePage("p5", QStringLiteral("Page")));
    store.saveAllPages(pages);

    const QString timestamp = QStringLiteral("2026-01-11 00:00:00");

    QVariantList blocks1;
    blocks1.append(makeBlock("p5", "b2", "Hello", timestamp));
    store.applyBlockUpdates(blocks1);
    REQUIRE(contentForBlock(store, "p5", "b2") == QStringLiteral("Hello"));

    QVariantList blocks2;
    blocks2.append(makeBlock("p5", "b2", "World", timestamp));
    store.applyBlockUpdates(blocks2);
    REQUIRE(contentForBlock(store, "p5", "b2") == QStringLiteral("World"));
}

TEST_CASE("DataStore: paired device endpoint round-trip", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    store.savePairedDevice("dev1", "Device 1", "ws1");
    store.updatePairedDeviceEndpoint("dev1", "192.168.1.2", 4242);

    const auto devices = store.getPairedDevices();
    REQUIRE(devices.size() == 1);
    const auto device = devices[0].toMap();
    REQUIRE(device.value("deviceId").toString() == QStringLiteral("dev1"));
    REQUIRE(device.value("host").toString() == QStringLiteral("192.168.1.2"));
    REQUIRE(device.value("port").toInt() == 4242);
}
