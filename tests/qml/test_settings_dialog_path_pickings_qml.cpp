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

QList<QObject*> requireObjects(QObject* root, const QString& objectName) {
    const auto objects = root->findChildren<QObject*>(objectName);
    if (objects.isEmpty()) {
        FAIL(("Missing QObject(s): " + objectName).toStdString());
    }
    return objects;
}

void requireAllBoolProperty(const QList<QObject*>& objects, const char* propertyName, bool expected) {
    REQUIRE(!objects.isEmpty());
    for (auto* obj : objects) {
        REQUIRE(obj);
        REQUIRE(obj->property(propertyName).toBool() == expected);
    }
}

} // namespace

TEST_CASE("QML: SettingsDialog path pickers show hidden directories and have a path field", "[qml]") {
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
        "    SettingsDialog {\n"
        "        id: dialog\n"
        "        objectName: \"settingsDialog\"\n"
        "        parent: Overlay.overlay\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SettingsDialogPathPickersHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    requireAllBoolProperty(requireObjects(root.get(), QStringLiteral("exportFolderListModel")), "showHidden", true);
    requireAllBoolProperty(requireObjects(root.get(), QStringLiteral("importFolderListModel")), "showHidden", true);
    requireAllBoolProperty(requireObjects(root.get(), QStringLiteral("databaseFolderListModel")), "showHidden", true);
    requireAllBoolProperty(requireObjects(root.get(), QStringLiteral("databaseFileListModel")), "showHidden", true);

    REQUIRE(!requireObjects(root.get(), QStringLiteral("exportFolderPickerPathField")).isEmpty());
    REQUIRE(!requireObjects(root.get(), QStringLiteral("importFolderPickerPathField")).isEmpty());
    REQUIRE(!requireObjects(root.get(), QStringLiteral("databaseFolderPickerPathField")).isEmpty());
    REQUIRE(!requireObjects(root.get(), QStringLiteral("databaseFilePickerPathField")).isEmpty());
}

