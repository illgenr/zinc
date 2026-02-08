#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickWindow>
#include <QStringList>
#include <QTest>
#include <QUrl>
#include <memory>

#include "ui/qml_types.hpp"

namespace {

void registerTypesOnce() {
    static bool registered = false;
    if (registered) {
        return;
    }
    zinc::ui::registerQmlTypes();
    registered = true;
}

QString formatErrors(const QList<QQmlError>& errors) {
    QStringList lines;
    lines.reserve(errors.size());
    for (const auto& error : errors) {
        lines.append(error.toString());
    }
    return lines.join('\n');
}

QQuickWindow* requireWindow(QObject* root) {
    auto* window = qobject_cast<QQuickWindow*>(root);
    REQUIRE(window);
    return window;
}

} // namespace

TEST_CASE("QML: BlockEditor Home/End stay in block while Ctrl+Home/Ctrl+End move document",
          "[qml][blockeditor][homeend]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "    width: 800\n"
        "    height: 600\n"
        "    visible: true\n"
        "    BlockEditor {\n"
        "        id: editor\n"
        "        objectName: \"blockEditor\"\n"
        "        anchors.fill: parent\n"
        "    }\n"
        "    Component.onCompleted: {\n"
        "        editor.blocksModel.clear()\n"
        "        editor.blocksModel.append({\n"
        "            blockId: \"a\",\n"
        "            blockType: \"paragraph\",\n"
        "            content: \"First\",\n"
        "            depth: 0,\n"
        "            checked: false,\n"
        "            collapsed: false,\n"
        "            language: \"\",\n"
        "            headingLevel: 0\n"
        "        })\n"
        "        editor.blocksModel.append({\n"
        "            blockId: \"b\",\n"
        "            blockType: \"paragraph\",\n"
        "            content: \"Middle\",\n"
        "            depth: 0,\n"
        "            checked: false,\n"
        "            collapsed: false,\n"
        "            language: \"\",\n"
        "            headingLevel: 0\n"
        "        })\n"
        "        editor.blocksModel.append({\n"
        "            blockId: \"c\",\n"
        "            blockType: \"paragraph\",\n"
        "            content: \"Last\",\n"
        "            depth: 0,\n"
        "            checked: false,\n"
        "            collapsed: false,\n"
        "            language: \"\",\n"
        "            headingLevel: 0\n"
        "        })\n"
        "        editor.focusBlockAt(1, 2)\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/BlockEditorHomeEndShortcutsHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(150);

    auto* editor = root->findChild<QObject*>(QStringLiteral("blockEditor"));
    REQUIRE(editor);

    REQUIRE(editor->property("currentBlockIndex").toInt() == 1);

    QTest::keyClick(window, Qt::Key_End);
    QTest::qWait(80);
    REQUIRE(editor->property("currentBlockIndex").toInt() == 1);

    QTest::keyClick(window, Qt::Key_Home);
    QTest::qWait(80);
    REQUIRE(editor->property("currentBlockIndex").toInt() == 1);

    QTest::keyClick(window, Qt::Key_End, Qt::ControlModifier);
    QTest::qWait(80);
    REQUIRE(editor->property("currentBlockIndex").toInt() == 2);

    QTest::keyClick(window, Qt::Key_Home, Qt::ControlModifier);
    QTest::qWait(80);
    REQUIRE(editor->property("currentBlockIndex").toInt() == 0);
}
