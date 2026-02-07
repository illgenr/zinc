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
