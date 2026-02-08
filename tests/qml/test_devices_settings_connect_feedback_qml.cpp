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

TEST_CASE("QML: Devices settings connect action reports reachability", "[qml][settings][devices]") {
    const auto settingsDialogQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    REQUIRE(!settingsDialogQml.isEmpty());
    REQUIRE(settingsDialogQml.contains(QStringLiteral("id: connectResultDialog")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("function startConnectProbe(")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("function resolveConnectProbe(")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("connectResultDialog.title = \"Checking Device\"")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("connectToPeer: function(deviceId, deviceName, host, port)")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("syncController: root.syncController")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("function onPeerDisconnected(deviceId)")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("function logConnectProbe(eventName, details)")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("function onPageSnapshotReceived(")));
    REQUIRE(settingsDialogQml.contains(QStringLiteral("function onPageSnapshotReceivedPages(")));
}

TEST_CASE("QML: Available devices prefer paired device names", "[qml][settings][devices]") {
    const auto settingsDialogQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    const auto devicesPageQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/settings/DevicesSettingsPage.qml"));
    REQUIRE(!settingsDialogQml.isEmpty());
    REQUIRE(!devicesPageQml.isEmpty());
    REQUIRE(settingsDialogQml.contains(QStringLiteral("pairedDeviceName: pairedNames[d.deviceId] ? pairedNames[d.deviceId] : \"\"")));
    REQUIRE(devicesPageQml.contains(QStringLiteral("if (pairedName && pairedName !== \"\") return pairedName")));
}
