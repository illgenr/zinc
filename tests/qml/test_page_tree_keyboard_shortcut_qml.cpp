#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickWindow>
#include <QStringList>
#include <QTest>
#include <QUrl>
#include <chrono>
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

template <typename Predicate>
bool waitUntil(Predicate&& predicate, int timeoutMs = 1500) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
    while (std::chrono::steady_clock::now() < deadline) {
        if (predicate()) {
            return true;
        }
        QTest::qWait(10);
    }
    return predicate();
}

} // namespace

TEST_CASE("QML: Enter on page triggers keyboard activation signal", "[qml][pagetree][shortcuts]") {
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
        "    property bool activatedByKeyboard: false\n"
        "    Shortcut {\n"
        "        context: Qt.ApplicationShortcut\n"
        "        sequence: \"Ctrl+E\"\n"
        "        onActivated: pageTree.focusTree()\n"
        "    }\n"
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "            selectPage(\"1\")\n"
        "        }\n"
        "        onPageActivatedByKeyboard: (pageId, title) => activatedByKeyboard = true\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeEnterActivationHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    // Focus the page tree via Ctrl+E.
    QTest::keyPress(window, Qt::Key_E, Qt::ControlModifier);

    // Enter should activate the current page and raise the keyboard-activation signal.
    QTest::keyClick(window, Qt::Key_Return);
    REQUIRE(waitUntil([&]() { return root->property("activatedByKeyboard").toBool(); }));
}

