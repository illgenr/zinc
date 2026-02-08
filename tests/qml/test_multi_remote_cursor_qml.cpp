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

TEST_CASE("QML: Block supports multiple remote cursor indicators", "[qml][cursor][sync]") {
    const auto blockQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/Block.qml"));
    REQUIRE(!blockQml.isEmpty());
    REQUIRE(blockQml.contains(QStringLiteral("property var activeRemoteCursors")));
    REQUIRE(blockQml.contains(QStringLiteral("id: remoteCursorRepeater")));
    REQUIRE(blockQml.contains(QStringLiteral("function onRemoteCursorsChanged()")));
}

TEST_CASE("QML: Main passes remoteCursors into block editors", "[qml][cursor][sync]") {
    const auto mainQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!mainQml.isEmpty());
    REQUIRE(mainQml.contains(QStringLiteral("remoteCursors: appSyncController ? appSyncController.remoteCursors : []")));
    REQUIRE(mainQml.contains(QStringLiteral("showRemoteCursor: root.bothAutoSyncEnabled")));
}

TEST_CASE("QML: Main passes remoteCursors into page trees", "[qml][cursor][sync]") {
    const auto mainQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!mainQml.isEmpty());
    REQUIRE(mainQml.contains(QStringLiteral("id: pageTree")));
    REQUIRE(mainQml.contains(QStringLiteral("id: mobilePageTree")));
    REQUIRE(mainQml.contains(QStringLiteral("remoteCursors: appSyncController ? appSyncController.remoteCursors : []")));
}
