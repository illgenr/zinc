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

TEST_CASE("QML: SettingsDialog exposes editor gutter setting", "[qml][settings][editor]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(contents.contains(QStringLiteral("Editor")));
    REQUIRE(contents.contains(QStringLiteral("Gutter position")));
    REQUIRE(contents.contains(QStringLiteral("gutterPositionPx")));
}

TEST_CASE("QML: SettingsDialog exposes jump-to-new-page setting", "[qml][settings][general]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(contents.contains(QStringLiteral("Jump to new page on creation")));
    REQUIRE(contents.contains(QStringLiteral("jumpToNewPageOnCreate")));
}
