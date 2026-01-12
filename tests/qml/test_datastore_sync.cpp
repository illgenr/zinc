#include <catch2/catch_test_macros.hpp>

#include <QObject>
#include <QString>
#include <QSettings>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QVariantList>
#include <QVariantMap>

#include "ui/DataStore.hpp"
#include "ui/MarkdownBlocks.hpp"

namespace {

QVariantMap makePage(const QString& pageId,
                     const QVariant& title,
                     const QString& updatedAt = QString(),
                     const QString& contentMarkdown = QString()) {
    QVariantMap page;
    page.insert("pageId", pageId);
    page.insert("title", title);
    page.insert("parentId", "");
    page.insert("depth", 0);
    page.insert("sortOrder", 0);
    if (!updatedAt.isEmpty()) {
        page.insert("updatedAt", updatedAt);
    }
    if (!contentMarkdown.isEmpty()) {
        page.insert("contentMarkdown", contentMarkdown);
    }
    return page;
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

bool deletedPagePresent(zinc::ui::DataStore& store, const QString& pageId) {
    const auto deleted = store.getDeletedPagesForSync();
    for (const auto& entry : deleted) {
        const auto row = entry.toMap();
        if (row.value("pageId").toString() == pageId) {
            return true;
        }
    }
    return false;
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

    QVariantMap incoming = makePage("p2", QVariant(), QStringLiteral("2026-01-11 00:00:00"));
    QVariantList pages;
    pages.append(incoming);
    store.applyPageUpdates(pages);

    REQUIRE(titleForPage(store, "p2") == QStringLiteral("Untitled"));
}

TEST_CASE("DataStore: applyPageUpdates updates contentMarkdown", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto t0 = QStringLiteral("2026-01-11 00:00:00");
    const auto t1 = QStringLiteral("2026-01-11 00:00:01");

    QVariantList pages1;
    pages1.append(makePage("p3", QStringLiteral("Page"), t0, QStringLiteral("Hello")));
    store.applyPageUpdates(pages1);
    REQUIRE(store.getPageContentMarkdown(QStringLiteral("p3")) == QStringLiteral("Hello"));

    QVariantList pages2;
    pages2.append(makePage("p3", QStringLiteral("Page"), t1, QStringLiteral("World")));
    store.applyPageUpdates(pages2);
    REQUIRE(store.getPageContentMarkdown(QStringLiteral("p3")) == QStringLiteral("World"));
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

TEST_CASE("DataStore: applyPageUpdates allows equal updatedAt to overwrite contentMarkdown", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const QString timestamp = QStringLiteral("2026-01-11 00:00:00");

    QVariantList pages1;
    pages1.append(makePage("p5", QStringLiteral("Page"), timestamp, QStringLiteral("Hello")));
    store.applyPageUpdates(pages1);
    REQUIRE(store.getPageContentMarkdown(QStringLiteral("p5")) == QStringLiteral("Hello"));

    QVariantList pages2;
    pages2.append(makePage("p5", QStringLiteral("Page"), timestamp, QStringLiteral("World")));
    store.applyPageUpdates(pages2);
    REQUIRE(store.getPageContentMarkdown(QStringLiteral("p5")) == QStringLiteral("World"));
}

TEST_CASE("DataStore: saveAllPages records deleted pages tombstones", "[qml][datastore]") {
    QSettings settings;
    settings.remove(QStringLiteral("sync/deleted_pages_retention"));

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantList initial;
    initial.append(makePage("del1", QStringLiteral("A")));
    initial.append(makePage("del2", QStringLiteral("B")));
    store.saveAllPages(initial);

    QVariantList after;
    after.append(makePage("del1", QStringLiteral("A")));
    store.saveAllPages(after);

    REQUIRE_FALSE(deletedPagePresent(store, "del1"));
    REQUIRE(deletedPagePresent(store, "del2"));
}

TEST_CASE("DataStore: applyDeletedPageUpdates removes pages", "[qml][datastore]") {
    QSettings settings;
    settings.remove(QStringLiteral("sync/deleted_pages_retention"));

    QVariantList deleted;
    QVariantList pages;
    pages.append(makePage("del3", QStringLiteral("Page")));

    {
        zinc::ui::DataStore author;
        REQUIRE(author.initialize());
        REQUIRE(author.resetDatabase());
        author.saveAllPages(pages);
        author.deletePage(QStringLiteral("del3"));
        REQUIRE(deletedPagePresent(author, "del3"));
        deleted = author.getDeletedPagesForSync();
    }

    zinc::ui::DataStore peer;
    REQUIRE(peer.initialize());
    REQUIRE(peer.resetDatabase());
    peer.saveAllPages(pages);
    REQUIRE(titleForPage(peer, "del3") == QStringLiteral("Page"));

    peer.applyDeletedPageUpdates(deleted);
    REQUIRE(titleForPage(peer, "del3").isEmpty());
    REQUIRE(deletedPagePresent(peer, "del3"));
}

TEST_CASE("DataStore: migration populates contentMarkdown from legacy blocks", "[qml][datastore]") {
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const auto dbPath = dir.filePath(QStringLiteral("zinc_migration.db"));

    {
        const auto connectionName = QStringLiteral("zinc_migration_seed");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(dbPath);
            REQUIRE(db.open());

            QSqlQuery q(db);
            REQUIRE(q.exec(QStringLiteral("PRAGMA user_version = 3")));
            REQUIRE(q.exec(QStringLiteral(
                "CREATE TABLE pages ("
                "id TEXT PRIMARY KEY,"
                "title TEXT NOT NULL DEFAULT 'Untitled',"
                "parent_id TEXT,"
                "depth INTEGER DEFAULT 0,"
                "sort_order INTEGER DEFAULT 0,"
                "created_at TEXT DEFAULT CURRENT_TIMESTAMP,"
                "updated_at TEXT DEFAULT CURRENT_TIMESTAMP"
                ")")));
            REQUIRE(q.exec(QStringLiteral(
                "CREATE TABLE blocks ("
                "id TEXT PRIMARY KEY,"
                "page_id TEXT NOT NULL,"
                "block_type TEXT NOT NULL DEFAULT 'paragraph',"
                "content TEXT DEFAULT '',"
                "depth INTEGER DEFAULT 0,"
                "checked INTEGER DEFAULT 0,"
                "collapsed INTEGER DEFAULT 0,"
                "language TEXT DEFAULT '',"
                "heading_level INTEGER DEFAULT 0,"
                "sort_order INTEGER DEFAULT 0,"
                "created_at TEXT DEFAULT CURRENT_TIMESTAMP,"
                "updated_at TEXT DEFAULT CURRENT_TIMESTAMP"
                ")")));

            QSqlQuery insertPage(db);
            insertPage.prepare(QStringLiteral(
                "INSERT INTO pages (id, title, parent_id, depth, sort_order, updated_at) VALUES (?, ?, ?, ?, ?, ?)"));
            insertPage.addBindValue(QStringLiteral("p_legacy"));
            insertPage.addBindValue(QStringLiteral("Legacy"));
            insertPage.addBindValue(QString());
            insertPage.addBindValue(0);
            insertPage.addBindValue(0);
            insertPage.addBindValue(QStringLiteral("2026-01-11 00:00:00"));
            REQUIRE(insertPage.exec());

            QSqlQuery insertBlock(db);
            insertBlock.prepare(QStringLiteral(
                "INSERT INTO blocks (id, page_id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"));
            insertBlock.addBindValue(QStringLiteral("b1"));
            insertBlock.addBindValue(QStringLiteral("p_legacy"));
            insertBlock.addBindValue(QStringLiteral("paragraph"));
            insertBlock.addBindValue(QStringLiteral("Hello"));
            insertBlock.addBindValue(0);
            insertBlock.addBindValue(0);
            insertBlock.addBindValue(0);
            insertBlock.addBindValue(QString());
            insertBlock.addBindValue(0);
            insertBlock.addBindValue(0);
            insertBlock.addBindValue(QStringLiteral("2026-01-11 00:00:00"));
            REQUIRE(insertBlock.exec());

            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }

    qputenv("ZINC_DB_PATH", dbPath.toUtf8());
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.schemaVersion() >= 4);

    REQUIRE(store.getPageContentMarkdown(QStringLiteral("p_legacy")) ==
            QStringLiteral("Hello\n"));
}

TEST_CASE("DataStore: deleted pages retention limit is enforced", "[qml][datastore]") {
    QSettings settings;
    settings.remove(QStringLiteral("sync/deleted_pages_retention"));

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());
    store.setDeletedPagesRetentionLimit(2);

    QVariantList pages;
    pages.append(makePage("d1", QStringLiteral("P1")));
    pages.append(makePage("d2", QStringLiteral("P2")));
    pages.append(makePage("d3", QStringLiteral("P3")));
    store.saveAllPages(pages);

    store.deletePage(QStringLiteral("d1"));
    store.deletePage(QStringLiteral("d2"));
    store.deletePage(QStringLiteral("d3"));

    REQUIRE(store.getDeletedPagesForSync().size() == 2);
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
