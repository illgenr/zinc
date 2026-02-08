#include <catch2/catch_test_macros.hpp>

#include <QFile>
#include <QRegularExpression>
#include <QString>

namespace {

QString readAllText(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

bool handlerSchedulesRelay(const QString& qml, const QString& handlerName) {
    const auto marker = QStringLiteral("function ") + handlerName + QStringLiteral("(");
    const auto markerPos = qml.indexOf(marker);
    if (markerPos < 0) {
        return false;
    }
    const auto local = qml.mid(markerPos, 700);
    const auto applyRe = QRegularExpression(QStringLiteral(R"(DataStore\.apply[A-Za-z]+Updates\()"));
    const auto relayRe = QRegularExpression(QStringLiteral(R"(root\.scheduleOutgoingSnapshot\(\))"));
    return applyRe.match(local).hasMatch() && relayRe.match(local).hasMatch();
}

} // namespace

TEST_CASE("QML: Main relays incoming snapshots after applying updates", "[qml][sync]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());

    REQUIRE(handlerSchedulesRelay(main, QStringLiteral("onAttachmentSnapshotReceivedAttachments")));
    REQUIRE(handlerSchedulesRelay(main, QStringLiteral("onPageSnapshotReceivedPages")));
    REQUIRE(handlerSchedulesRelay(main, QStringLiteral("onDeletedPageSnapshotReceivedPages")));
    REQUIRE(handlerSchedulesRelay(main, QStringLiteral("onNotebookSnapshotReceivedNotebooks")));
    REQUIRE(handlerSchedulesRelay(main, QStringLiteral("onDeletedNotebookSnapshotReceivedNotebooks")));
    REQUIRE(handlerSchedulesRelay(main, QStringLiteral("onBlockSnapshotReceivedBlocks")));
}

TEST_CASE("QML: Main title preview helper guards mobile tree on desktop", "[qml][sync][title]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());

    const auto fnPos = main.indexOf(QStringLiteral("function previewPageTitleInTrees("));
    REQUIRE(fnPos >= 0);
    const auto fnBlock = main.mid(fnPos, 600);
    REQUIRE(fnBlock.contains(QStringLiteral("typeof mobilePageTree !== \"undefined\"")));
}

TEST_CASE("QML: Main keeps title edits as preview until commit", "[qml][sync][title]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());

    REQUIRE(main.contains(QStringLiteral("root.previewPageTitleInTrees(")));
    REQUIRE(main.contains(QStringLiteral("root.commitPageTitleInTrees(pageId, newTitle)")));
    REQUIRE(!main.contains(QStringLiteral("function schedulePageTitleSync(pageId, newTitle)")));
    REQUIRE(!main.contains(QStringLiteral("id: pageTitleSyncTimer")));
}

TEST_CASE("QML: Main presence includes title fallback from current page", "[qml][sync][title]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());

    REQUIRE(main.contains(QStringLiteral("function presenceTitlePreviewForPage(pageId)")));
    REQUIRE(main.contains(QStringLiteral("if (currentPage && currentPage.id === pageId)")));
    REQUIRE(main.contains(QStringLiteral("return currentPage.title || \"\"")));
    REQUIRE(main.contains(QStringLiteral("const titlePreview = root.presenceTitlePreviewForPage(presencePageId)")));
}

TEST_CASE("QML: Main displays remote title preview in active page title", "[qml][sync][title]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());

    REQUIRE(main.contains(QStringLiteral("function remoteTitlePreviewForPage(pageId)")));
    REQUIRE(main.contains(QStringLiteral("function displayPageTitle(pageId, fallbackTitle)")));
    REQUIRE(main.contains(QStringLiteral("pageTitle: currentPage ? root.displayPageTitle(currentPage.id, currentPage.title) : \"\"")));
}

TEST_CASE("QML: Main does not persist title cursor as block cursor", "[qml][sync][title]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());
    REQUIRE(main.contains(QStringLiteral("if (blockIndex >= 0) {")));
    REQUIRE(main.contains(QStringLiteral("root.scheduleCursorPersist(pageId, blockIndex, cursorPos)")));
}
