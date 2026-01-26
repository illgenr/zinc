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

TEST_CASE("QML: InlineFormatBar mobile is full-width and shows font controls", "[qml][formatting]") {
    const auto qml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/InlineFormatBar.qml"));
    REQUIRE(!qml.isEmpty());

    // Qt QML's JS subset doesn't guarantee ES2021 APIs like String.prototype.replaceAll.
    REQUIRE(!qml.contains(QStringLiteral("replaceAll(")));

    // Ensure we generate valid HTML for span style wrappers:
    // - Use single quotes around the HTML attribute so CSS can use double quotes (e.g. font-family with spaces).
    REQUIRE(qml.contains(QStringLiteral("<span style='")));
    REQUIRE(!qml.contains(QStringLiteral("<span style=\\\"")));

    REQUIRE(qml.contains(QStringLiteral("id: mobileContent")));
    REQUIRE(qml.contains(QStringLiteral("sourceComponent: root._isMobile ? mobileContent : desktopContent")));
    REQUIRE(qml.contains(QStringLiteral("id: fontCombo")));
    REQUIRE(qml.contains(QStringLiteral("id: sizeCombo")));

    // Mobile layout should be multi-row, not purely horizontally scrolled.
    REQUIRE(qml.contains(QStringLiteral("ColumnLayout {")));
    REQUIRE(containsRegex(qml, QRegularExpression(QStringLiteral(R"(implicitHeight:\s*root\._isMobile)"))));

    const auto blockEditor = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/BlockEditor.qml"));
    REQUIRE(!blockEditor.isEmpty());
    REQUIRE(!blockEditor.contains(QStringLiteral("replaceAll(")));
    REQUIRE(blockEditor.contains(QStringLiteral("id: formatBarContainer")));
    REQUIRE(containsRegex(blockEditor, QRegularExpression(QStringLiteral(R"(width:\s*\(AndroidUtils\.isAndroid\(\)\s*\|\|\s*Qt\.platform\.os\s*===\s*\"ios\"\))"))));
}
