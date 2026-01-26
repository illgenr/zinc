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

TEST_CASE("QML: Rendered paragraph replaces task markers with checkbox glyphs", "[qml][render]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/blocks/ParagraphBlock.qml"));
    REQUIRE(!contents.isEmpty());

    REQUIRE(containsRegex(contents, QRegularExpression(QStringLiteral(R"(\\[(\\s|x|X)\\])"))));
    REQUIRE(contents.contains(QString::fromUtf8(u8"☐")));
    REQUIRE(contents.contains(QString::fromUtf8(u8"☑")));
}

