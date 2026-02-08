#include <catch2/catch_test_macros.hpp>

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QUrl>

#include "ui/DataStore.hpp"

namespace {

QVariantMap makePage(const QString& pageId,
                     const QString& notebookId,
                     const QString& title,
                     const QString& parentId) {
    QVariantMap page;
    page.insert("pageId", pageId);
    page.insert("notebookId", notebookId);
    page.insert("title", title);
    page.insert("parentId", parentId);
    page.insert("depth", parentId.isEmpty() ? 0 : 1);
    page.insert("sortOrder", 0);
    page.insert("contentMarkdown", QStringLiteral(""));
    return page;
}

bool writeTextFile(const QString& path, const QString& text) {
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    return file.write(text.toUtf8()) >= 0;
}

bool writeBytesFile(const QString& path, const QByteArray& bytes) {
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly)) return false;
    return file.write(bytes) == bytes.size();
}

QVariantMap pageById(zinc::ui::DataStore& store, const QString& pageId) {
    const auto pages = store.getAllPages();
    for (const auto& v : pages) {
        const auto page = v.toMap();
        if (page.value(QStringLiteral("pageId")).toString() == pageId) return page;
    }
    return {};
}

} // namespace

TEST_CASE("DataStore: importPagesFromFiles imports txt/md/html into target parent", "[qml][datastore][import]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto notebookId = store.createNotebook(QStringLiteral("Imported"));
    REQUIRE_FALSE(notebookId.isEmpty());

    const auto parentPageId = QStringLiteral("11111111-1111-1111-1111-111111111111");
    store.savePage(makePage(parentPageId, notebookId, QStringLiteral("Parent"), QStringLiteral("")));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    const QDir root(tmp.path());
    REQUIRE(writeTextFile(root.filePath(QStringLiteral("Alpha.md")), QStringLiteral("# Alpha\n\nBody\n")));
    REQUIRE(writeTextFile(root.filePath(QStringLiteral("README")), QStringLiteral("No extension text")));
    REQUIRE(writeTextFile(root.filePath(QStringLiteral("Ideas.txt")), QStringLiteral("plain text note")));
    REQUIRE(writeTextFile(root.filePath(QStringLiteral("debug.log")), QStringLiteral("log line 1\nlog line 2")));
    REQUIRE(writeTextFile(root.filePath(QStringLiteral("Clip.html")), QStringLiteral("<h1>Imported HTML</h1>\n<p>x</p>")));
    REQUIRE(writeBytesFile(root.filePath(QStringLiteral("skip.bin")), QByteArray::fromHex("000102414243ff")));

    QVariantList urls;
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("Alpha.md"))));
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("README"))));
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("Ideas.txt"))));
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("debug.log"))));
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("Clip.html"))));
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("skip.bin"))));

    const auto imported = store.importPagesFromFiles(urls, parentPageId, notebookId);
    REQUIRE(imported.size() == 6);

    for (const auto& idValue : imported) {
        const auto id = idValue.toString();
        REQUIRE_FALSE(id.isEmpty());
        const auto page = pageById(store, id);
        REQUIRE_FALSE(page.isEmpty());
        REQUIRE(page.value(QStringLiteral("notebookId")).toString() == notebookId);
        REQUIRE(page.value(QStringLiteral("parentId")).toString() == parentPageId);
    }

    bool foundAlpha = false;
    bool foundReadme = false;
    bool foundIdeas = false;
    bool foundLog = false;
    bool foundClip = false;
    bool foundBin = false;
    for (const auto& idValue : imported) {
        const auto id = idValue.toString();
        const auto page = pageById(store, id);
        const auto title = page.value(QStringLiteral("title")).toString();
        const auto markdown = store.getPageContentMarkdown(id);
        if (title == QStringLiteral("Alpha.md")) {
            foundAlpha = true;
            REQUIRE(markdown.contains(QStringLiteral("# Alpha")));
        } else if (title == QStringLiteral("README")) {
            foundReadme = true;
            REQUIRE(markdown == QStringLiteral("No extension text"));
        } else if (title == QStringLiteral("Ideas.txt")) {
            foundIdeas = true;
            REQUIRE(markdown == QStringLiteral("plain text note"));
        } else if (title == QStringLiteral("debug.log")) {
            foundLog = true;
            REQUIRE(markdown.contains(QStringLiteral("log line 1")));
        } else if (title == QStringLiteral("Clip.html")) {
            foundClip = true;
            REQUIRE(markdown.contains(QStringLiteral("<h1>Imported HTML</h1>")));
        } else if (title == QStringLiteral("skip.bin")) {
            foundBin = true;
            REQUIRE(markdown == QStringLiteral("...ABC."));
        }
    }
    REQUIRE(foundAlpha);
    REQUIRE(foundReadme);
    REQUIRE(foundIdeas);
    REQUIRE(foundLog);
    REQUIRE(foundClip);
    REQUIRE(foundBin);
}

TEST_CASE("DataStore: importPagesFromFiles extracts embedded markdown from Zinc HTML export", "[qml][datastore][import]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    const QDir root(tmp.path());
    REQUIRE(writeTextFile(
        root.filePath(QStringLiteral("Embedded.html")),
        QStringLiteral(
            "<html><body>"
            "<textarea id=\"zinc-markdown\"># Embedded\\n\\n- A\\n- B</textarea>"
            "</body></html>")));

    QVariantList urls;
    urls.append(QUrl::fromLocalFile(root.filePath(QStringLiteral("Embedded.html"))));

    const auto imported = store.importPagesFromFiles(urls, QStringLiteral(""), QStringLiteral(""));
    REQUIRE(imported.size() == 1);

    const auto pageId = imported.front().toString();
    REQUIRE_FALSE(pageId.isEmpty());
    REQUIRE(pageById(store, pageId).value(QStringLiteral("title")).toString() == QStringLiteral("Embedded.html"));
    REQUIRE(store.getPageContentMarkdown(pageId) == QStringLiteral("# Embedded\\n\\n- A\\n- B"));
}
