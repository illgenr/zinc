#include <catch2/catch_test_macros.hpp>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QUrl>

#include "ui/DataStore.hpp"

namespace {

QVariantMap makePage(const QString& pageId,
                     const QString& notebookId,
                     const QString& title,
                     const QString& contentMarkdown) {
    QVariantMap page;
    page.insert("pageId", pageId);
    page.insert("notebookId", notebookId);
    page.insert("title", title);
    page.insert("parentId", "");
    page.insert("depth", 0);
    page.insert("sortOrder", 0);
    page.insert("contentMarkdown", contentMarkdown);
    return page;
}

bool hasAnyNotebookNamed(const zinc::ui::DataStore& store, const QString& name) {
    const auto notebooks = const_cast<zinc::ui::DataStore&>(store).getAllNotebooks();
    for (const auto& v : notebooks) {
        const auto nb = v.toMap();
        if (nb.value(QStringLiteral("name")).toString() == name) {
            return true;
        }
    }
    return false;
}

QString notebookIdForName(const zinc::ui::DataStore& store, const QString& name) {
    const auto notebooks = const_cast<zinc::ui::DataStore&>(store).getAllNotebooks();
    for (const auto& v : notebooks) {
        const auto nb = v.toMap();
        if (nb.value(QStringLiteral("name")).toString() == name) {
            return nb.value(QStringLiteral("notebookId")).toString();
        }
    }
    return {};
}

bool hasPageId(const zinc::ui::DataStore& store, const QString& pageId) {
    const auto pages = const_cast<zinc::ui::DataStore&>(store).getAllPages();
    for (const auto& v : pages) {
        const auto p = v.toMap();
        if (p.value(QStringLiteral("pageId")).toString() == pageId) {
            return true;
        }
    }
    return false;
}

} // namespace

TEST_CASE("DataStore: import notebooks from markdown export (backup/restore)", "[qml][datastore][import]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto nbId = store.createNotebook(QStringLiteral("Pics"));
    REQUIRE_FALSE(nbId.isEmpty());

    const auto onePxPng = QStringLiteral(
        "data:image/png;base64,"
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5WZ4cAAAAASUVORK5CYII=");
    const auto attachmentId = store.saveAttachmentFromDataUrl(onePxPng);
    REQUIRE_FALSE(attachmentId.isEmpty());

    const auto pageId = QStringLiteral("00000000-0000-0000-0000-0000000000aa");
    const auto md = QStringLiteral("<img src=\"image://attachments/%1\" alt=\"\" title=\"t\">").arg(attachmentId);
    store.savePage(makePage(pageId, nbId, QStringLiteral("WithImage"), md));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    const auto exportRoot = QUrl::fromLocalFile(tmp.path());
    REQUIRE(store.exportNotebooks(QVariantList{nbId}, exportRoot, QStringLiteral("markdown"), true));

    REQUIRE(store.resetDatabase());
    REQUIRE(store.importNotebooks(exportRoot, QStringLiteral("auto"), true));

    REQUIRE(hasAnyNotebookNamed(store, QStringLiteral("Pics")));
    REQUIRE(hasPageId(store, pageId));

    const auto importedMd = store.getPageContentMarkdown(pageId);
    REQUIRE(importedMd.contains(QStringLiteral("image://attachments/")));

    const auto attachments = store.getAttachmentsForSync();
    bool found = false;
    for (const auto& v : attachments) {
        const auto a = v.toMap();
        if (a.value(QStringLiteral("attachmentId")).toString() == attachmentId) {
            found = true;
            REQUIRE_FALSE(a.value(QStringLiteral("dataBase64")).toString().isEmpty());
        }
    }
    REQUIRE(found);
}

TEST_CASE("DataStore: importing without replaceExisting duplicates notebooks", "[qml][datastore][import]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    // Existing notebook
    const auto existingId = store.createNotebook(QStringLiteral("Work"));
    REQUIRE_FALSE(existingId.isEmpty());

    // Export-like folder (no manifest)
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    const auto root = QDir(tmp.path());
    REQUIRE(root.mkpath(QStringLiteral("Work")));
    const auto nbDir = QDir(root.filePath(QStringLiteral("Work")));
    {
        QFile f(nbDir.filePath(QStringLiteral("Note.md")));
        REQUIRE(f.open(QIODevice::WriteOnly | QIODevice::Text));
        f.write("# Hello\n\nBody\n");
    }

    REQUIRE(store.importNotebooks(QUrl::fromLocalFile(tmp.path()), QStringLiteral("markdown"), false));

    REQUIRE(hasAnyNotebookNamed(store, QStringLiteral("Work (2)")));
    const auto importedNbId = notebookIdForName(store, QStringLiteral("Work (2)"));
    REQUIRE_FALSE(importedNbId.isEmpty());

    const auto pages = store.getPagesForNotebook(importedNbId);
    REQUIRE(pages.size() == 1);
    const auto pageId = pages[0].toMap().value(QStringLiteral("pageId")).toString();
    REQUIRE_FALSE(pageId.isEmpty());
    REQUIRE(store.getPageContentMarkdown(pageId).contains(QStringLiteral("# Hello")));
}

TEST_CASE("DataStore: importing a manifest export without replaceExisting duplicates notebooks", "[qml][datastore][import]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto nbId = store.createNotebook(QStringLiteral("Pics"));
    REQUIRE_FALSE(nbId.isEmpty());

    const auto onePxPng = QStringLiteral(
        "data:image/png;base64,"
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5WZ4cAAAAASUVORK5CYII=");
    const auto attachmentId = store.saveAttachmentFromDataUrl(onePxPng);
    REQUIRE_FALSE(attachmentId.isEmpty());

    const auto md = QStringLiteral("<img src=\"image://attachments/%1\" alt=\"\" title=\"t\">").arg(attachmentId);
    store.savePage(makePage(QStringLiteral("p_img"), nbId, QStringLiteral("WithImage"), md));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    const auto exportRoot = QUrl::fromLocalFile(tmp.path());
    REQUIRE(store.exportNotebooks(QVariantList{nbId}, exportRoot, QStringLiteral("markdown"), true));

    // Import into existing DB without replace; should create a second notebook.
    REQUIRE(store.importNotebooks(exportRoot, QStringLiteral("auto"), false));
    REQUIRE(hasAnyNotebookNamed(store, QStringLiteral("Pics (2)")));

    const auto importedNbId = notebookIdForName(store, QStringLiteral("Pics (2)"));
    REQUIRE_FALSE(importedNbId.isEmpty());

    const auto pages = store.getPagesForNotebook(importedNbId);
    REQUIRE(pages.size() == 1);
    const auto pageId = pages[0].toMap().value(QStringLiteral("pageId")).toString();
    REQUIRE_FALSE(pageId.isEmpty());

    const auto importedMd = store.getPageContentMarkdown(pageId);
    REQUIRE(importedMd.contains(QStringLiteral("image://attachments/")));
}
