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

TEST_CASE("QML: BlockEditorEnterLogic chooses insert-above at cursor 0 with content", "[qml][blockeditor][logic]") {
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQml\n"
        "import \"qrc:/qt/qml/zinc/qml/components/BlockEditorEnterLogic.js\" as Logic\n"
        "QtObject {\n"
        "  property var action: Logic.enterAction({ blockIndex: 5, cursorPos: 0, blockType: \"paragraph\", content: \"Hello\" })\n"
        "  property string kind: action.kind\n"
        "  property int insertIndex: action.insertIndex\n"
        "  property string newBlockType: action.newBlockType\n"
        "  property int focusCursorPos: action.focusCursorPos\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/BlockEditorEnterLogicAboveHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    REQUIRE(root->property("kind").toString() == QStringLiteral("insert"));
    REQUIRE(root->property("insertIndex").toInt() == 5);
    REQUIRE(root->property("newBlockType").toString() == QStringLiteral("paragraph"));
    REQUIRE(root->property("focusCursorPos").toInt() == 0);
}

TEST_CASE("QML: BlockEditorEnterLogic inserts below when cursor not at 0", "[qml][blockeditor][logic]") {
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQml\n"
        "import \"qrc:/qt/qml/zinc/qml/components/BlockEditorEnterLogic.js\" as Logic\n"
        "QtObject {\n"
        "  property var action: Logic.enterAction({ blockIndex: 5, cursorPos: 3, blockType: \"paragraph\", content: \"Hello\" })\n"
        "  property int insertIndex: action.insertIndex\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/BlockEditorEnterLogicBelowHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    REQUIRE(root->property("insertIndex").toInt() == 6);
}

TEST_CASE("QML: BlockEditorEnterLogic converts empty todo to paragraph", "[qml][blockeditor][logic]") {
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQml\n"
        "import \"qrc:/qt/qml/zinc/qml/components/BlockEditorEnterLogic.js\" as Logic\n"
        "QtObject {\n"
        "  property var action: Logic.enterAction({ blockIndex: 1, cursorPos: 0, blockType: \"todo\", content: \"\" })\n"
        "  property string kind: action.kind\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/BlockEditorEnterLogicTodoEmptyHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    REQUIRE(root->property("kind").toString() == QStringLiteral("convertTodoToParagraph"));
}

