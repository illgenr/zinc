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

TEST_CASE("QML: SettingsDialog exposes keyboard shortcuts settings page", "[qml][settings][shortcuts]") {
    const auto dialogContents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/SettingsDialog.qml"));
    REQUIRE(!dialogContents.isEmpty());

    REQUIRE(dialogContents.contains(QStringLiteral("{ label: \"Shortcuts\"")));
    REQUIRE(dialogContents.contains(QStringLiteral("SettingsPages.KeyboardShortcutsSettingsPage {}")));
}

TEST_CASE("QML: Keyboard shortcuts settings page supports modal key capture", "[qml][settings][shortcuts]") {
    const auto pageContents =
        readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/settings/KeyboardShortcutsSettingsPage.qml"));
    REQUIRE(!pageContents.isEmpty());

    REQUIRE(pageContents.contains(QStringLiteral("id: shortcutCaptureDialog")));
    REQUIRE(pageContents.contains(QStringLiteral("Keys.onPressed")));
    REQUIRE(pageContents.contains(QStringLiteral("ThemeManager.borderLight")));
    REQUIRE(pageContents.contains(QStringLiteral("Qt.Key_Escape")));
    REQUIRE(pageContents.contains(QStringLiteral("shortcutCaptureDialog.close()")));
    REQUIRE(pageContents.contains(QStringLiteral("text: \"Set\"")));
    REQUIRE(pageContents.contains(QStringLiteral("text: \"Cancel\"")));
    REQUIRE(pageContents.contains(QStringLiteral("ShortcutPreferences")));
}
