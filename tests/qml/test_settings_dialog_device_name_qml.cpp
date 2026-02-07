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

TEST_CASE("QML: SettingsDialog supports renaming paired devices", "[qml][settings]") {
    const auto qml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    REQUIRE(!qml.isEmpty());
    REQUIRE(qml.contains(QStringLiteral("objectName: \"deviceNameEditDialog\"")));
    REQUIRE(qml.contains(QStringLiteral("DataStore.setPairedDeviceName(")));
}
