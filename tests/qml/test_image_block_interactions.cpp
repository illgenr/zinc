#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStringList>
#include <QTest>
#include <QUrl>
#include <cmath>
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

QQuickItem* requireItem(QObject* root, const QString& objectName) {
    auto* item = root->findChild<QQuickItem*>(objectName);
    if (!item) {
        FAIL(("Missing QQuickItem: " + objectName).toStdString());
        return nullptr;
    }
    return item;
}

QQuickWindow* requireWindow(QObject* root) {
    auto* window = qobject_cast<QQuickWindow*>(root);
    REQUIRE(window);
    return window;
}

QPoint centerPointInWindow(QQuickItem* item) {
    const auto center = item->mapToScene(QPointF(item->width() * 0.5, item->height() * 0.5));
    return QPoint(static_cast<int>(std::lround(center.x())), static_cast<int>(std::lround(center.y())));
}

} // namespace

TEST_CASE("QML: ImageBlock resize handle resizes smoothly", "[qml][image]") {
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
        "    property string imageContent: '{\"src\":\"does-not-exist\",\"w\":200,\"h\":150}'\n"
        "    ImageBlock {\n"
        "        id: img\n"
        "        objectName: \"imageBlock\"\n"
        "        anchors.fill: parent\n"
        "        selected: true\n"
        "        content: imageContent\n"
        "        onContentEdited: (newContent) => imageContent = newContent\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/ImageBlockResizeHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(100);

    auto* imageBlock = root->findChild<QObject*>(QStringLiteral("imageBlock"));
    REQUIRE(imageBlock);

    auto* handle = requireItem(root.get(), QStringLiteral("resizeHandle_se"));
    const auto start = centerPointInWindow(handle);

    const auto initialWidth = imageBlock->property("desiredWidth").toReal();
    const auto initialHeight = imageBlock->property("desiredHeight").toReal();
    REQUIRE(initialWidth == 200.0);
    REQUIRE(initialHeight == 150.0);

    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
    for (int i = 1; i <= 10; i++) {
        QTest::mouseMove(window, start + QPoint(8 * i, 6 * i), 1);
    }
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, start + QPoint(80, 60));
    QTest::qWait(120);

    const auto resizedWidth = imageBlock->property("desiredWidth").toReal();
    const auto resizedHeight = imageBlock->property("desiredHeight").toReal();
    REQUIRE(resizedWidth >= 240.0);
    REQUIRE(resizedHeight >= 190.0);
}

TEST_CASE("QML: ImageBlock selection border matches painted size", "[qml][image]") {
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
        "    property string imageContent: '{\"src\":\"does-not-exist\",\"w\":300,\"h\":200}'\n"
        "    ImageBlock {\n"
        "        objectName: \"imageBlock\"\n"
        "        anchors.fill: parent\n"
        "        selected: true\n"
        "        content: imageContent\n"
        "        onContentEdited: (newContent) => imageContent = newContent\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/ImageBlockBorderHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(100);

    auto* frame = requireItem(root.get(), QStringLiteral("imageFrame"));
    auto* border = requireItem(root.get(), QStringLiteral("paintedBox"));
    REQUIRE(border->width() <= frame->width());
    REQUIRE(border->height() <= frame->height());
}

TEST_CASE("QML: Dragging an image calls editor reorder hooks", "[qml][image][reorder]") {
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
        "    Item {\n"
        "        id: editorStub\n"
        "        objectName: \"editorStub\"\n"
        "        anchors.fill: parent\n"
        "        property int startCalls: 0\n"
        "        property int updateCalls: 0\n"
        "        property int endCalls: 0\n"
        "        function startReorderBlock(index) { startCalls++ }\n"
        "        function updateReorderBlockByEditorY(editorY) { updateCalls++ }\n"
        "        function endReorderBlock() { endCalls++ }\n"
        "    }\n"
        "    property string imageContent: '{\"src\":\"does-not-exist\",\"w\":200,\"h\":150}'\n"
        "    ImageBlock {\n"
        "        objectName: \"imageBlock\"\n"
        "        anchors.fill: parent\n"
        "        editor: editorStub\n"
        "        blockIndex: 0\n"
        "        selected: true\n"
        "        content: imageContent\n"
        "        onContentEdited: (newContent) => imageContent = newContent\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/ImageBlockReorderHooksHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(100);

    auto* editorStub = root->findChild<QObject*>(QStringLiteral("editorStub"));
    REQUIRE(editorStub);

    auto* imageFrame = requireItem(root.get(), QStringLiteral("imageFrame"));
    const auto start = centerPointInWindow(imageFrame);

    REQUIRE(editorStub->property("startCalls").toInt() == 0);
    REQUIRE(editorStub->property("endCalls").toInt() == 0);

    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
    QTest::mouseMove(window, start + QPoint(0, 80), 1);
    QTest::qWait(25);

    REQUIRE(editorStub->property("startCalls").toInt() == 1);
    REQUIRE(editorStub->property("updateCalls").toInt() >= 1);

    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, start + QPoint(0, 80));
    QTest::qWait(25);
    REQUIRE(editorStub->property("endCalls").toInt() == 1);
}
