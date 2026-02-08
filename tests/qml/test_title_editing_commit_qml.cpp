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

TEST_CASE("QML: Title editing commits on focus loss", "[qml][editor][title]") {
    const auto blockEditor = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/BlockEditor.qml"));
    REQUIRE(!blockEditor.isEmpty());

    REQUIRE(blockEditor.contains(QStringLiteral("signal titleEditingFinished(")));
    REQUIRE(containsRegex(blockEditor, QRegularExpression(QStringLiteral(R"(Keys\.onPressed:\s*function\s*\(event\).*\bQt\.Key_Tab\b)"),
                                                         QRegularExpression::DotMatchesEverythingOption)));
    REQUIRE(containsRegex(blockEditor, QRegularExpression(QStringLiteral(R"(Keys\.onPressed:\s*function\s*\(event\).*\b(Qt\.Key_Return|Qt\.Key_Enter)\b)"),
                                                         QRegularExpression::DotMatchesEverythingOption)));
    REQUIRE(blockEditor.contains(QStringLiteral("focusContent()")));
    REQUIRE(blockEditor.contains(QStringLiteral("function remoteTitleCursorPos()")));
    REQUIRE(blockEditor.contains(QStringLiteral("visible: root.showRemoteCursor && remotePos >= 0 && !titleInput.activeFocus")));
    REQUIRE(blockEditor.contains(QStringLiteral("root.cursorMoved(-1, cursorPosition)")));
    REQUIRE(blockEditor.contains(QStringLiteral("wrapMode: TextEdit.Wrap")));

    const auto markdownEditor = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/MarkdownEditor.qml"));
    REQUIRE(!markdownEditor.isEmpty());

    REQUIRE(markdownEditor.contains(QStringLiteral("signal titleEditingFinished(")));
    REQUIRE(containsRegex(markdownEditor, QRegularExpression(QStringLiteral(R"(Keys\.onPressed:\s*function\s*\(event\).*\bQt\.Key_Tab\b)"),
                                                           QRegularExpression::DotMatchesEverythingOption)));
    REQUIRE(containsRegex(markdownEditor, QRegularExpression(QStringLiteral(R"(Keys\.onPressed:\s*function\s*\(event\).*\b(Qt\.Key_Return|Qt\.Key_Enter)\b)"),
                                                           QRegularExpression::DotMatchesEverythingOption)));
    REQUIRE(markdownEditor.contains(QStringLiteral("focusContent()")));
    REQUIRE(markdownEditor.contains(QStringLiteral("function remoteTitleCursorPos()")));
    REQUIRE(markdownEditor.contains(QStringLiteral("visible: root.showRemoteCursor && remotePos >= 0 && !titleInput.activeFocus")));
    REQUIRE(markdownEditor.contains(QStringLiteral("signal cursorMoved(int blockIndex, int cursorPos)")));
    REQUIRE(markdownEditor.contains(QStringLiteral("root.cursorMoved(-1, cursorPosition)")));
}
