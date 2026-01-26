#include <catch2/catch_test_macros.hpp>

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QUrl>

#include "ui/DataStore.hpp"

namespace {

QVariantMap makePage(const QString& pageId,
                     const QString& notebookId,
                     const QVariant& title,
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

QString readAllText(const QString& filePath) {
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return QString::fromUtf8(f.readAll());
}

QStringList listFilesRecursively(const QString& rootPath) {
    QStringList files;
    QDir root(rootPath);
    const auto entries = root.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot);
    for (const auto& info : entries) {
        if (info.isDir()) {
            for (const auto& child : listFilesRecursively(info.absoluteFilePath())) {
                files.append(child);
            }
        } else {
            files.append(info.absoluteFilePath());
        }
    }
    return files;
}

} // namespace

TEST_CASE("DataStore: export notebooks as markdown", "[qml][datastore][export]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto workId = store.createNotebook(QStringLiteral("Work"));
    REQUIRE_FALSE(workId.isEmpty());

    store.savePage(makePage(QStringLiteral("p1"), workId, QStringLiteral("Meeting Notes"), QStringLiteral("# Meeting\n\nAgenda")));
    store.savePage(makePage(QStringLiteral("p2"), workId, QStringLiteral("Todo"), QStringLiteral("- A\n- B")));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());

    const QVariantList notebookIds{workId};
    const auto ok = store.exportNotebooks(notebookIds, QUrl::fromLocalFile(tmp.path()), QStringLiteral("markdown"), false);
    REQUIRE(ok);

    const auto files = listFilesRecursively(tmp.path());
    REQUIRE(files.size() == 2);
    REQUIRE(readAllText(files[0]).size() > 0);
    REQUIRE(readAllText(files[1]).size() > 0);

    const auto allText = readAllText(files[0]) + "\n" + readAllText(files[1]);
    REQUIRE(allText.contains(QStringLiteral("# Meeting")));
    REQUIRE(allText.contains(QStringLiteral("- A")));
}

TEST_CASE("DataStore: export notebooks as html", "[qml][datastore][export]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto nbId = store.createNotebook(QStringLiteral("Personal"));
    REQUIRE_FALSE(nbId.isEmpty());

    store.savePage(makePage(QStringLiteral("p_html"),
                            nbId,
                            QStringLiteral("Hello"),
                            QStringLiteral("# Hello\n\n- [ ] Todo\n- [x] Done\n")));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());

    const auto ok = store.exportNotebooks(QVariantList{nbId}, QUrl::fromLocalFile(tmp.path()), QStringLiteral("html"), false);
    REQUIRE(ok);

    const auto files = listFilesRecursively(tmp.path());
    REQUIRE(files.size() == 1);
    const auto html = readAllText(files[0]);
    REQUIRE(html.contains(QStringLiteral("Hello")));
    REQUIRE(html.contains(QStringLiteral("<")));
    REQUIRE(html.contains(QStringLiteral("<style>")));
    REQUIRE(html.contains(QStringLiteral("input type=\"checkbox\"")));
    REQUIRE(html.contains(QStringLiteral("onclick=\"return false\"")));
    REQUIRE(html.contains(QStringLiteral("disabled")));
    REQUIRE(html.contains(QStringLiteral("checked")));
}

TEST_CASE("DataStore: html export rewrites zinc page links", "[qml][datastore][export]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto nbId = store.createNotebook(QStringLiteral("Links"));
    REQUIRE_FALSE(nbId.isEmpty());

    const auto pageA = QStringLiteral("00000000-0000-0000-0000-0000000000aa");
    const auto pageB = QStringLiteral("00000000-0000-0000-0000-0000000000bb");

    store.savePage(makePage(pageB, nbId, QStringLiteral("Target"), QStringLiteral("B")));
    store.savePage(makePage(pageA,
                            nbId,
                            QStringLiteral("Source"),
                            QStringLiteral("[Go](zinc://page/%1)\n").arg(pageB)));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());

    const auto ok = store.exportNotebooks(QVariantList{nbId}, QUrl::fromLocalFile(tmp.path()), QStringLiteral("html"), false);
    REQUIRE(ok);

    const auto files = listFilesRecursively(tmp.path());
    REQUIRE(files.size() == 2);

    QString sourceHtml;
    for (const auto& f : files) {
        if (f.contains(pageA.left(8))) {
            sourceHtml = readAllText(f);
            break;
        }
    }
    REQUIRE_FALSE(sourceHtml.isEmpty());

    const auto expectedTarget = QStringLiteral("0000-Target-%1.html").arg(pageB.left(8));
    REQUIRE(sourceHtml.contains(expectedTarget));
    REQUIRE_FALSE(sourceHtml.contains(QStringLiteral("zinc://page/")));
}

TEST_CASE("DataStore: export respects selected notebooks", "[qml][datastore][export]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto aId = store.createNotebook(QStringLiteral("A"));
    const auto bId = store.createNotebook(QStringLiteral("B"));
    REQUIRE_FALSE(aId.isEmpty());
    REQUIRE_FALSE(bId.isEmpty());

    store.savePage(makePage(QStringLiteral("pA"), aId, QStringLiteral("NoteA"), QStringLiteral("A")));
    store.savePage(makePage(QStringLiteral("pB"), bId, QStringLiteral("NoteB"), QStringLiteral("B")));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());

    REQUIRE(store.exportNotebooks(QVariantList{aId}, QUrl::fromLocalFile(tmp.path()), QStringLiteral("markdown"), false));
    const auto files = listFilesRecursively(tmp.path());
    REQUIRE(files.size() == 1);
    const auto text = readAllText(files[0]);
    REQUIRE(text.contains(QStringLiteral("A")));
    REQUIRE_FALSE(text.contains(QStringLiteral("B")));
}

TEST_CASE("DataStore: export rewrites attachment URLs and copies bytes", "[qml][datastore][export][attachments]") {
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

    REQUIRE(store.exportNotebooks(QVariantList{nbId}, QUrl::fromLocalFile(tmp.path()), QStringLiteral("markdown"), true));

    const auto files = listFilesRecursively(tmp.path());
    REQUIRE(files.size() == 2); // one page + one attachment

    QString pagePath;
    QString attachmentPath;
    for (const auto& p : files) {
        if (p.endsWith(QStringLiteral(".md"))) pagePath = p;
        if (p.contains(QStringLiteral("/attachments/")) && p.endsWith(QStringLiteral(".png"))) attachmentPath = p;
    }
    REQUIRE_FALSE(pagePath.isEmpty());
    REQUIRE_FALSE(attachmentPath.isEmpty());

    const auto exportedMd = readAllText(pagePath);
    REQUIRE_FALSE(exportedMd.contains(QStringLiteral("image://attachments/")));
    REQUIRE(exportedMd.contains(QStringLiteral("attachments/")));
}
