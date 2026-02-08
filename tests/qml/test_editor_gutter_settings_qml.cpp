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
    const auto dialogContents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    const auto editorContents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/settings/EditorSettingsPage.qml"));
    REQUIRE(!dialogContents.isEmpty());
    REQUIRE(!editorContents.isEmpty());

    REQUIRE(dialogContents.contains(QStringLiteral("Editor")));
    REQUIRE(editorContents.contains(QStringLiteral("Gutter position")));
    REQUIRE(editorContents.contains(QStringLiteral("gutterPositionPx")));
}

TEST_CASE("QML: SettingsDialog exposes jump-to-new-page setting", "[qml][settings][general]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/settings/GeneralSettingsPage.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(contents.contains(QStringLiteral("Jump to new page on creation")));
    REQUIRE(contents.contains(QStringLiteral("jumpToNewPageOnCreate")));
}
