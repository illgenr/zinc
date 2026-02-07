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

QString syncReconnectTimerBlock(const QString& mainQml) {
    const auto marker = QStringLiteral("id: syncReconnectTimer");
    const auto pos = mainQml.indexOf(marker);
    if (pos < 0) return {};
    return mainQml.mid(pos, 1400);
}

} // namespace

TEST_CASE("QML: reconnect timer attempts missing peers even when one peer is connected", "[qml][sync]") {
    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());

    const auto block = syncReconnectTimerBlock(main);
    REQUIRE(!block.isEmpty());

    // Regression guard: don't stop reconnect attempts solely because at least one peer is connected.
    REQUIRE_FALSE(block.contains(QStringLiteral("if (appSyncController.peerCount > 0) return")));
    REQUIRE(block.contains(QStringLiteral("appSyncController.isPeerConnected")));
}
