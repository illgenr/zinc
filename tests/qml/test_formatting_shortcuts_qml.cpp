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

bool containsRegex(const QString& text, const QRegularExpression& re) {
    return re.match(text).hasMatch();
}

} // namespace

TEST_CASE("QML: BlockEditor defines inline formatting shortcuts", "[qml][editor][shortcuts]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/BlockEditor.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(contents.contains(QStringLiteral("Ctrl+B")));
    REQUIRE(contents.contains(QStringLiteral("Ctrl+I")));
    REQUIRE(contents.contains(QStringLiteral("Ctrl+U")));
    REQUIRE(contents.contains(QStringLiteral("Ctrl+L")));
    REQUIRE(contents.contains(QStringLiteral("Ctrl+Shift+M")));

    REQUIRE(containsRegex(contents, QRegularExpression(QStringLiteral(R"(onActivated:\s*formatBar\.bold\(\))"))));
    REQUIRE(containsRegex(contents, QRegularExpression(QStringLiteral(R"(onActivated:\s*formatBar\.italic\(\))"))));
    REQUIRE(containsRegex(contents, QRegularExpression(QStringLiteral(R"(onActivated:\s*formatBar\.underline\(\))"))));
    REQUIRE(containsRegex(contents, QRegularExpression(QStringLiteral(R"(onActivated:\s*formatBar\.link\(\))"))));
    REQUIRE(containsRegex(
        contents, QRegularExpression(QStringLiteral(R"(onActivated:\s*formatBar\.collapsed\s*=\s*!\s*formatBar\.collapsed)"))));
}

TEST_CASE("QML: ShortcutsDialog lists inline formatting shortcuts", "[qml][shortcuts]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/ShortcutsDialog.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(contents.contains(QStringLiteral("{ key: \"Ctrl+B\"")));
    REQUIRE(contents.contains(QStringLiteral("{ key: \"Ctrl+I\"")));
    REQUIRE(contents.contains(QStringLiteral("{ key: \"Ctrl+U\"")));
    REQUIRE(contents.contains(QStringLiteral("{ key: \"Ctrl+L\"")));
    REQUIRE(contents.contains(QStringLiteral("{ key: \"Ctrl+Shift+M\"")));
}
