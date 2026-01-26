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

TEST_CASE("QML: Rendered blocks support ctrl+click external links with delayed tooltip", "[qml][editor][links]") {
    const auto paragraph = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/blocks/ParagraphBlock.qml"));
    REQUIRE(!paragraph.isEmpty());

    REQUIRE(paragraph.contains(QStringLiteral("externalLinkRequested")));
    REQUIRE(paragraph.contains(QStringLiteral("interval: 1500")));
    REQUIRE(containsRegex(paragraph,
                          QRegularExpression(QStringLiteral(R"(mouse\.modifiers\s*&\s*Qt\.ControlModifier)"))));
    REQUIRE(containsRegex(paragraph, QRegularExpression(QStringLiteral(R"(\bhttps?://)"))));
}

