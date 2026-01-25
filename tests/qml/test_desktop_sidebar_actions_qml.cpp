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

TEST_CASE("QML: Desktop sidebar actions are grouped and responsive", "[qml][sidebar]") {
    const auto actions = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/DesktopSidebarActions.qml"));
    REQUIRE(!actions.isEmpty());
    REQUIRE(actions.contains(QStringLiteral("Flow {")));
    REQUIRE(actions.contains(QStringLiteral("twoColumns")));
    REQUIRE(actions.contains(QStringLiteral("primaryButtonWidth")));
    REQUIRE(actions.contains(QStringLiteral("secondaryButtonWidth")));
    REQUIRE(actions.contains(QStringLiteral("desktopNewPageButton")));
    REQUIRE(actions.contains(QStringLiteral("desktopFindButton")));
    REQUIRE(actions.contains(QStringLiteral("desktopNewNotebookButton")));
    REQUIRE(actions.contains(QStringLiteral("desktopSortButton")));

    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());
    REQUIRE(main.contains(QStringLiteral("DesktopSidebarActions {")));

    // Desktop pageTree should hide its own top controls to avoid duplicating the actions.
    const auto pageTreeMarker = QStringLiteral("objectName: \"pageTree\"");
    const auto pageTreePos = main.indexOf(pageTreeMarker);
    REQUIRE(pageTreePos >= 0);
    const auto local = main.mid(pageTreePos, 1200);
    REQUIRE(containsRegex(local, QRegularExpression(QStringLiteral(R"(showNewNotebookButton:\s*false)"))));
    REQUIRE(containsRegex(local, QRegularExpression(QStringLiteral(R"(showSortButton:\s*false)"))));

    const auto pageTreeQml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/PageTree.qml"));
    REQUIRE(!pageTreeQml.isEmpty());
    REQUIRE(pageTreeQml.contains(QStringLiteral("property bool showSortButton")));
    REQUIRE(containsRegex(pageTreeQml,
        QRegularExpression(QStringLiteral(
            R"(visible:\s*root\.showNewPageButton\s*\|\|\s*root\.showNewNotebookButton\s*\|\|\s*root\.showSortButton)"))));
}
