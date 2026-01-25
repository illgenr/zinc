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

TEST_CASE("QML: Mobile sidebar actions are consolidated", "[qml][sidebar]") {
    const auto actions = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/MobileSidebarActions.qml"));
    REQUIRE(!actions.isEmpty());
    REQUIRE(actions.contains(QStringLiteral("GridLayout {")));
    REQUIRE(containsRegex(actions, QRegularExpression(QStringLiteral(R"(columns:\s*2)"))));
    REQUIRE(actions.contains(QStringLiteral("mobileNewPageButton")));
    REQUIRE(actions.contains(QStringLiteral("mobileFindButton")));
    REQUIRE(actions.contains(QStringLiteral("mobileNewNotebookButton")));
    REQUIRE(actions.contains(QStringLiteral("mobileSortButton")));

    const auto main = readAllText(QStringLiteral(":/qt/qml/zinc/qml/Main.qml"));
    REQUIRE(!main.isEmpty());
    REQUIRE(main.contains(QStringLiteral("MobileSidebarActions {")));

    // Mobile pageTree should hide its own top controls to avoid duplicating the actions.
    const auto marker = QStringLiteral("objectName: \"mobilePageTree\"");
    const auto pos = main.indexOf(marker);
    REQUIRE(pos >= 0);
    const auto local = main.mid(pos, 1200);
    REQUIRE(containsRegex(local, QRegularExpression(QStringLiteral(R"(showNewNotebookButton:\s*false)"))));
    REQUIRE(containsRegex(local, QRegularExpression(QStringLiteral(R"(showSortButton:\s*false)"))));
}

