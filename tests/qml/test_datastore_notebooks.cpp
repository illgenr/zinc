#include <catch2/catch_test_macros.hpp>

#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include "ui/DataStore.hpp"

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

QString notebookNameById(const QVariantList& notebooks, const QString& notebookId) {
    for (const auto& entry : notebooks) {
        const auto nb = entry.toMap();
        if (nb.value("notebookId").toString() == notebookId) {
            return nb.value("name").toString();
        }
    }
    return {};
}

} // namespace

TEST_CASE("DataStore: seedDefaultPages creates My Notebook and assigns pages", "[qml][datastore][notebooks]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto defaultNotebookId = store.defaultNotebookId();
    REQUIRE_FALSE(defaultNotebookId.isEmpty());

    const auto notebooks = store.getAllNotebooks();
    REQUIRE(notebookNameById(notebooks, defaultNotebookId) == QStringLiteral("My Notebook"));

    const auto pagesInDefault = store.getPagesForNotebook(defaultNotebookId);
    REQUIRE(pagesInDefault.size() >= 4);
    for (const auto& entry : pagesInDefault) {
        const auto page = entry.toMap();
        REQUIRE(page.value("notebookId").toString() == defaultNotebookId);
    }

    // "Loose notes" (empty notebookId) remain empty, not forced into the default notebook.
    QVariantMap loose = makePage("p_loose",
                                 QStringLiteral("Loose"),
                                 QStringLiteral("2026-01-01 00:00:00.000"),
                                 QStringLiteral("Body"));
    loose.insert("notebookId", QStringLiteral(""));
    QVariantList incoming;
    incoming.append(loose);
    store.applyPageUpdates(incoming);

    const auto looseRetrieved = store.getPage(QStringLiteral("p_loose"));
    REQUIRE(looseRetrieved.value("notebookId").toString() == QStringLiteral(""));
}

TEST_CASE("DataStore: applyPageUpdates defaults notebookId when absent", "[qml][datastore][notebooks]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto defaultNotebookId = store.defaultNotebookId();
    REQUIRE_FALSE(defaultNotebookId.isEmpty());

    QVariantList incoming;
    incoming.append(makePage("p_no_nb", QStringLiteral("Hello"), QStringLiteral("2026-01-01 00:00:00.000"), QStringLiteral("Body")));
    store.applyPageUpdates(incoming);

    const auto page = store.getPage(QStringLiteral("p_no_nb"));
    REQUIRE(page.value("notebookId").toString() == defaultNotebookId);
}

TEST_CASE("DataStore: applyPageUpdates keeps explicit empty notebookId", "[qml][datastore][notebooks]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantMap page = makePage("p_empty_nb",
                                QStringLiteral("Loose"),
                                QStringLiteral("2026-01-01 00:00:00.000"),
                                QStringLiteral("Body"));
    page.insert("notebookId", QStringLiteral(""));
    QVariantList incoming;
    incoming.append(page);
    store.applyPageUpdates(incoming);

    const auto retrieved = store.getPage(QStringLiteral("p_empty_nb"));
    REQUIRE(retrieved.value("notebookId").toString() == QStringLiteral(""));
}

TEST_CASE("DataStore: can rename and delete the initial My Notebook", "[qml][datastore][notebooks]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto defaultNotebookId = store.defaultNotebookId();
    REQUIRE_FALSE(defaultNotebookId.isEmpty());

    store.renameNotebook(defaultNotebookId, QStringLiteral("Renamed"));
    {
        const auto notebooks = store.getAllNotebooks();
        REQUIRE(notebookNameById(notebooks, defaultNotebookId) == QStringLiteral("Renamed"));
    }

    store.deleteNotebook(defaultNotebookId);
    {
        const auto notebooks = store.getAllNotebooks();
        REQUIRE(notebookNameById(notebooks, defaultNotebookId).isEmpty());
    }

    QVariantList incoming;
    incoming.append(makePage("p_no_nb_after_delete",
                             QStringLiteral("Hello"),
                             QStringLiteral("2026-01-01 00:00:00.000"),
                             QStringLiteral("Body")));
    store.applyPageUpdates(incoming);

    const auto page = store.getPage(QStringLiteral("p_no_nb_after_delete"));
    REQUIRE(page.value("notebookId").toString() == QStringLiteral(""));
}

TEST_CASE("DataStore: deleteNotebook(deletePages=true) deletes pages and tombstones them", "[qml][datastore][notebooks]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto notebookId = store.createNotebook(QStringLiteral("Work"));
    REQUIRE_FALSE(notebookId.isEmpty());

    QVariantMap page1 = makePage(QStringLiteral("p_nb_1"),
                                 QStringLiteral("One"),
                                 QStringLiteral("2026-01-01 00:00:00.000"),
                                 QStringLiteral("Body"));
    page1.insert(QStringLiteral("notebookId"), notebookId);
    store.savePage(page1);

    QVariantMap page2 = makePage(QStringLiteral("p_nb_2"),
                                 QStringLiteral("Two"),
                                 QStringLiteral("2026-01-01 00:00:01.000"),
                                 QStringLiteral("Body"));
    page2.insert(QStringLiteral("notebookId"), notebookId);
    store.savePage(page2);

    REQUIRE(store.getPage(QStringLiteral("p_nb_1")).value("notebookId").toString() == notebookId);
    REQUIRE(store.getPage(QStringLiteral("p_nb_2")).value("notebookId").toString() == notebookId);

    store.deleteNotebook(notebookId, true);

    {
        const auto notebooks = store.getAllNotebooks();
        REQUIRE(notebookNameById(notebooks, notebookId).isEmpty());
    }

    REQUIRE(store.getPage(QStringLiteral("p_nb_1")).isEmpty());
    REQUIRE(store.getPage(QStringLiteral("p_nb_2")).isEmpty());

    const auto deleted = store.getDeletedPagesForSync();
    bool has1 = false;
    bool has2 = false;
    for (const auto& entry : deleted) {
        const auto m = entry.toMap();
        const auto id = m.value(QStringLiteral("pageId")).toString();
        if (id == QStringLiteral("p_nb_1")) has1 = true;
        if (id == QStringLiteral("p_nb_2")) has2 = true;
    }
    REQUIRE(has1);
    REQUIRE(has2);
}
