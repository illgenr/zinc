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

TEST_CASE("QML: SlashMenu uses 'Page' command label", "[qml][slashmenu]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/SlashMenu.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(contents.contains(QStringLiteral("label: \"Page\"")));
    REQUIRE(!contents.contains(QStringLiteral("Link to page")));
}

