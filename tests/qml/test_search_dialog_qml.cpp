#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
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

QObject* requireObject(QObject* root, const QString& objectName) {
    auto* obj = root->findChild<QObject*>(objectName);
    if (!obj) {
        FAIL(("Missing QObject: " + objectName).toStdString());
        return nullptr;
    }
    return obj;
}

QQuickItem* requireItem(QObject* root, const QString& objectName) {
    auto* item = root->findChild<QQuickItem*>(objectName);
    if (!item) {
        FAIL(("Missing QQuickItem: " + objectName).toStdString());
        return nullptr;
    }
    return item;
}

} // namespace

TEST_CASE("QML: SearchDialog does not overflow small windows", "[qml]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "    width: 320\n"
        "    height: 480\n"
        "    visible: true\n"
        "    SearchDialog {\n"
        "        id: dialog\n"
        "        objectName: \"searchDialog\"\n"
        "        parent: Overlay.overlay\n"
        "        Component.onCompleted: dialog.open()\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SearchDialogSmallHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(100);

    auto* dialog = requireObject(root.get(), QStringLiteral("searchDialog"));
    const auto dialogWidth = dialog->property("width").toReal();
    const auto dialogHeight = dialog->property("height").toReal();

    REQUIRE(dialogWidth > 0.0);
    REQUIRE(dialogHeight > 0.0);
    REQUIRE(dialogWidth <= window->width());
    REQUIRE(dialogHeight <= window->height());
}

TEST_CASE("QML: SearchDialog uses desktop size when possible", "[qml]") {
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
        "    SearchDialog {\n"
        "        id: dialog\n"
        "        objectName: \"searchDialog\"\n"
        "        parent: Overlay.overlay\n"
        "        Component.onCompleted: dialog.open()\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SearchDialogDesktopHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(100);

    auto* dialog = requireObject(root.get(), QStringLiteral("searchDialog"));
    REQUIRE(dialog->property("width").toReal() == 560.0);
    REQUIRE(dialog->property("height").toReal() == 400.0);
}

TEST_CASE("QML: SearchDialog searches titles and content as you type", "[qml]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "    width: 420\n"
        "    height: 640\n"
        "    visible: true\n"
        "    Component.onCompleted: {\n"
        "        DataStore.resetDatabase()\n"
        "        DataStore.savePage({ pageId: \"p1\", title: \"Alpha\", parentId: \"\", contentMarkdown: \"\" })\n"
        "        DataStore.savePageContentMarkdown(\"p1\", \"# SpecialHeading42\\n\\nHello world\")\n"
        "        DataStore.savePage({ pageId: \"p2\", title: \"Beta\", parentId: \"\", contentMarkdown: \"\" })\n"
        "        DataStore.savePageContentMarkdown(\"p2\", \"Zebra stripes\")\n"
        "    }\n"
        "    SearchDialog {\n"
        "        id: dialog\n"
        "        parent: Overlay.overlay\n"
        "        Component.onCompleted: dialog.open()\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SearchDialogSearchHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(150);

    auto* searchField = requireObject(root.get(), QStringLiteral("searchField"));
    auto* resultsList = requireItem(root.get(), QStringLiteral("resultsList"));

    searchField->setProperty("text", QStringLiteral("Alpha"));
    QTest::qWait(300);
    REQUIRE(resultsList->property("count").toInt() == 1);

    searchField->setProperty("text", QStringLiteral("world"));
    QTest::qWait(300);
    REQUIRE(resultsList->property("count").toInt() == 1);

    searchField->setProperty("text", QStringLiteral("SpecialHeading42"));
    QTest::qWait(300);
    REQUIRE(resultsList->property("count").toInt() == 1);

    searchField->setProperty("text", QStringLiteral("Zebra"));
    QTest::qWait(300);
    REQUIRE(resultsList->property("count").toInt() == 1);

    searchField->setProperty("text", QStringLiteral("nope"));
    QTest::qWait(300);
    REQUIRE(resultsList->property("count").toInt() == 0);
}
