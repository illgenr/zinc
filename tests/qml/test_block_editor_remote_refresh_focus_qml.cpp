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

TEST_CASE("QML: BlockEditor remote refresh does not force focus when editor is unfocused", "[qml][sync][mobile]") {
    const auto qml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/BlockEditor.qml"));
    REQUIRE(!qml.isEmpty());
    REQUIRE(qml.contains(QStringLiteral("item.textControl.activeFocus")));
    REQUIRE(qml.contains(QStringLiteral("mergeBlocksFromStorage({ preserveFocus: false })")));
    REQUIRE(qml.contains(QStringLiteral("Qt.inputMethod.visible")));
}
