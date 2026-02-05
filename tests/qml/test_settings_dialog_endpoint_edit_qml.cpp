#include <catch2/catch_test_macros.hpp>

#include <QCoreApplication>
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

QObject* requireChild(QObject& root, const char* name) {
    auto* child = root.findChild<QObject*>(QString::fromLatin1(name));
    REQUIRE(child != nullptr);
    return child;
}

QQuickWindow* requireWindow(QObject* root) {
    auto* window = qobject_cast<QQuickWindow*>(root);
    REQUIRE(window);
    return window;
}

} // namespace

TEST_CASE("QML: SettingsDialog endpoint editor does not throw ReferenceError", "[qml]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "  width: 800\n"
        "  height: 600\n"
        "  visible: true\n"
        "  SettingsDialog {\n"
        "    id: dialog\n"
        "    objectName: \"settingsDialog\"\n"
        "    parent: Overlay.overlay\n"
        "    Component.onCompleted: {\n"
        "      dialog.open()\n"
        "      endpointEditDialog.deviceId = \"dev\"\n"
        "      endpointEditDialog.deviceName = \"Dev\"\n"
        "      endpointEditDialog.hostText = \"example\"\n"
        "      endpointEditDialog.portText = \"47888\"\n"
        "      endpointEditDialog.open()\n"
        "    }\n"
        "  }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SettingsDialogEndpointEditHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    auto* endpointDialog = requireChild(*root, "endpointEditDialog");
    auto* saveButton = requireChild(*root, "endpointEditSaveButton");

    // Clicking save with an unpaired device should set a status message (and must not throw).
    REQUIRE(QMetaObject::invokeMethod(saveButton, "clicked"));
    QCoreApplication::processEvents();

    const auto status = endpointDialog->property("statusText").toString();
    REQUIRE(!status.isEmpty());
}
