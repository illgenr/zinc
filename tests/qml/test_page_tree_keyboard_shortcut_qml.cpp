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

TEST_CASE("QML: Enter activates selected page even when single-tap activation is disabled", "[qml][pagetree][shortcuts]") {
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
        "    property string activatedPageId: \"\"\n"
        "    Shortcut {\n"
        "        context: Qt.ApplicationShortcut\n"
        "        sequence: \"Ctrl+E\"\n"
        "        onActivated: pageTree.focusTree()\n"
        "    }\n"
        "    PageTree {\n"
        "        id: pageTree\n"
        "        anchors.fill: parent\n"
        "        activateOnSingleTap: false\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "            selectPage(\"1\")\n"
        "        }\n"
        "        onPageSelected: (pageId, title) => activatedPageId = pageId\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeEnterAlwaysActivatesHost.qml")));

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

    // Move selection down to the next page; this should not activate the page yet
    // since activateOnSingleTap is false.
    QTest::keyClick(window, Qt::Key_Down);
    QTest::qWait(20);
    REQUIRE(root->property("activatedPageId").toString() == QStringLiteral("1"));

    // Enter should activate the selected page.
    QTest::keyClick(window, Qt::Key_Return);
    REQUIRE(waitUntil([&]() { return root->property("activatedPageId").toString() == QStringLiteral("4"); }));
}

namespace {

QObject* findOrNull(QObject* root, const char* objectName) {
    if (!root) return nullptr;
    return root->findChild<QObject*>(QString::fromLatin1(objectName));
}

QVariantList requireAllPagesEventually(QObject* pageTree) {
    QVariant value;
    REQUIRE(waitUntil([&]() {
        value = {};
        const bool ok = QMetaObject::invokeMethod(pageTree, "getAllPages", Q_RETURN_ARG(QVariant, value));
        if (!ok) {
            return false;
        }
        const auto pages = value.toList();
        return pages.size() >= 4;
    }));
    return value.toList();
}

} // namespace

TEST_CASE("QML: PageTree sortMode alphabetical orders siblings by title", "[qml][pagetree][sort]") {
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
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        sortMode: \"alphabetical\"\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeSortAlphaHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);
    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    auto* pageTree = findOrNull(root.get(), "pageTree");
    REQUIRE(pageTree);
    const auto pages = requireAllPagesEventually(pageTree);

    // With defaults inside "My Notebook", the notebook's root pages should be alphabetical:
    // Getting Started (1), Personal (4), Projects (2) with Work Project (3) under Projects.
    REQUIRE(pages[0].toMap().value("pageId").toString() == QStringLiteral("1"));
    REQUIRE(pages[1].toMap().value("pageId").toString() == QStringLiteral("4"));
    REQUIRE(pages[2].toMap().value("pageId").toString() == QStringLiteral("2"));
    REQUIRE(pages[3].toMap().value("pageId").toString() == QStringLiteral("3"));
}

TEST_CASE("QML: PageTree sortMode updatedAt puts recently updated pages first", "[qml][pagetree][sort]") {
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
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        sortMode: \"updatedAt\"\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "            Qt.callLater(() => {\n"
        "                const pages = DataStore ? DataStore.getAllPages() : []\n"
        "                for (let i = 0; i < pages.length; i++) {\n"
        "                    if (pages[i].pageId === \"4\") pages[i].title = \"Personal (edited)\"\n"
        "                }\n"
        "                if (DataStore) DataStore.saveAllPages(pages)\n"
        "            })\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeSortUpdatedHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);
    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    auto* pageTree = findOrNull(root.get(), "pageTree");
    REQUIRE(pageTree);
    REQUIRE(pageTree->property("sortMode").toString() == QStringLiteral("updatedAt"));
    REQUIRE(waitUntil([&]() {
        QVariant value;
        if (!QMetaObject::invokeMethod(pageTree, "getAllPages", Q_RETURN_ARG(QVariant, value))) {
            return false;
        }
        const auto pages = value.toList();
        if (pages.isEmpty()) return false;
        return pages[0].toMap().value("pageId").toString() == QStringLiteral("4");
    }));
}

TEST_CASE("QML: PageTree sortMode createdAt puts newly created pages first", "[qml][pagetree][sort]") {
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
        "    property string newPageId: \"\"\n"
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        sortMode: \"createdAt\"\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "            newPageId = createPage(\"\")\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeSortCreatedHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);
    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    REQUIRE(waitUntil([&]() { return !root->property("newPageId").toString().isEmpty(); }));
    const auto newId = root->property("newPageId").toString();

    auto* pageTree = findOrNull(root.get(), "pageTree");
    REQUIRE(pageTree);
    REQUIRE(waitUntil([&]() {
        QVariant value;
        if (!QMetaObject::invokeMethod(pageTree, "getAllPages", Q_RETURN_ARG(QVariant, value))) {
            return false;
        }
        const auto pages = value.toList();
        if (pages.isEmpty()) return false;
        return pages[0].toMap().value("pageId").toString() == newId;
    }));
}

TEST_CASE("QML: Ctrl+N creates a new page", "[qml][pagetree][shortcuts]") {
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
        "    property int pageCount: 0\n"
        "    Shortcut {\n"
        "        context: Qt.ApplicationShortcut\n"
        "        sequence: \"Ctrl+N\"\n"
        "        onActivated: pageTree.createPage(\"\")\n"
        "    }\n"
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "            pageCount = getAllPages().length\n"
        "        }\n"
        "        onPagesChanged: pageCount = getAllPages().length\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeCtrlNHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    REQUIRE(waitUntil([&]() { return root->property("pageCount").toInt() >= 4; }));
    const auto before = root->property("pageCount").toInt();

    QTest::keyPress(window, Qt::Key_N, Qt::ControlModifier);
    REQUIRE(waitUntil([&]() { return root->property("pageCount").toInt() == before + 1; }));
}
