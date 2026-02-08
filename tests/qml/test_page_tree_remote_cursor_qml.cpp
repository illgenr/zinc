#include <catch2/catch_test_macros.hpp>

#include <QFile>
#include <QString>

namespace {

QString readAllText(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

} // namespace

TEST_CASE("QML: PageTree supports remote cursor title suffix", "[qml][cursor][sync]") {
    const auto pageTreeQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/PageTree.qml"));
    REQUIRE(!pageTreeQml.isEmpty());
    REQUIRE(pageTreeQml.contains(QStringLiteral("property var remoteCursors: []")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("property int remoteCursorsRevision: 0")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("onRemoteCursorsChanged: remoteCursorsRevision++")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("function cursorTitleSuffixForPage(pageId)")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("function remoteTitlePreviewForPage(pageId)")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("function titleWithCursorSuffix(pageId, title)")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("c.titlePreview")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("const _presenceRevision = root.remoteCursorsRevision")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("return root.titleWithCursorSuffix(model.pageId || \"\", model.title || \"\")")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("wrapMode: Text.Wrap")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("readonly property int rowHeight: Math.max(baseRowHeight")));
}

TEST_CASE("QML: PageTree preserves scroll position when reloading pages", "[qml][pagetree]") {
    const auto pageTreeQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/PageTree.qml"));
    REQUIRE(!pageTreeQml.isEmpty());
    REQUIRE(pageTreeQml.contains(QStringLiteral("function clampPageListContentY(y)")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("const previousContentY = pageList ? pageList.contentY : 0")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("Qt.callLater(() => {")));
    REQUIRE(pageTreeQml.contains(QStringLiteral("pageList.contentY = clampPageListContentY(restoreY)")));
}
