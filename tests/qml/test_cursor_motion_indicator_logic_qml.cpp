#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QStringList>
#include <QUrl>
#include <memory>

namespace {

QString formatErrors(const QList<QQmlError>& errors) {
    QStringList lines;
    lines.reserve(errors.size());
    for (const auto& error : errors) {
        lines.append(error.toString());
    }
    return lines.join('\n');
}

} // namespace

TEST_CASE("QML: CursorMotionIndicatorLogic arms on arrow keys", "[qml][cursor]") {
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQml\n"
        "import \"qrc:/qt/qml/zinc/qml/components/CursorMotionIndicatorLogic.js\" as Logic\n"
        "QtObject {\n"
        "  property bool up: Logic.shouldArm(0, Qt.Key_Up)\n"
        "  property bool down: Logic.shouldArm(0, Qt.Key_Down)\n"
        "  property bool left: Logic.shouldArm(0, Qt.Key_Left)\n"
        "  property bool right: Logic.shouldArm(0, Qt.Key_Right)\n"
        "  property bool ctrlUp: Logic.shouldArm(Qt.ControlModifier, Qt.Key_Up)\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/CursorMotionIndicatorLogicHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    REQUIRE(root->property("up").toBool() == true);
    REQUIRE(root->property("down").toBool() == true);
    REQUIRE(root->property("left").toBool() == true);
    REQUIRE(root->property("right").toBool() == true);
    REQUIRE(root->property("ctrlUp").toBool() == false);
}

