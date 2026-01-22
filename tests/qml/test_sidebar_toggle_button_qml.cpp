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

TEST_CASE("QML: Desktop sidebar toggle button collapses left panel", "[qml][sidebar]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!contents.isEmpty());

    const auto marker = QStringLiteral("objectName: \"sidebarToggleButton\"");
    const auto markerPos = contents.indexOf(marker);
    REQUIRE(markerPos >= 0);

    // Keep this intentionally local to the specific button, since other parts of Main.qml
    // still use newNotebookDialog.open() (e.g. mobile header).
    const auto local = contents.mid(markerPos, 2500);
    REQUIRE(containsRegex(local, QRegularExpression(QStringLiteral(R"(onClicked:\s*sidebarCollapsed\s*=\s*!sidebarCollapsed)"))));
    REQUIRE(containsRegex(
        local,
        QRegularExpression(QStringLiteral(R"(text:\s*sidebarCollapsed\s*\?\s*"⟩"\s*:\s*"⟨")"))));
    REQUIRE(!local.contains(QStringLiteral("newNotebookDialog.open")));
}
