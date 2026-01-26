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

TEST_CASE("QML: Destroying a ParagraphBlock does not abort", "[qml][paragraph]") {
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
        "    Loader {\n"
        "        id: loader\n"
        "        objectName: \"loader\"\n"
        "        active: true\n"
        "        anchors.fill: parent\n"
        "        sourceComponent: ParagraphBlock {\n"
        "            objectName: \"paragraph\"\n"
        "            content: \"\"\n"
        "            editor: null\n"
        "            blockIndex: 0\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/ParagraphBlockDestroyHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(150);

    SUCCEED();
}
