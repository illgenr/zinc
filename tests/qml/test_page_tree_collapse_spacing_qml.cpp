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

QObject* findOrNull(QObject* root, const char* objectName) {
    if (!root) return nullptr;
    return root->findChild<QObject*>(QString::fromLatin1(objectName));
}

} // namespace

TEST_CASE("QML: Collapsing a notebook does not leave blank spacing rows", "[qml][pagetree][notebook][layout]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "    width: 800\n"
        "    height: 1200\n"
        "    visible: true\n"
        "    property string firstNotebookId: \"\"\n"
        "    property string secondNotebookId: \"\"\n"
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            resetToDefaults()\n"
        "            Qt.callLater(() => {\n"
        "                const nbs = DataStore ? DataStore.getAllNotebooks() : []\n"
        "                for (let i = 0; i < nbs.length; i++) {\n"
        "                    if (nbs[i].name === \"My Notebook\") firstNotebookId = nbs[i].notebookId\n"
        "                }\n"
        "                if (DataStore) secondNotebookId = DataStore.createNotebook(\"Second Notebook\")\n"
        "            })\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeCollapseSpacingHost.qml")));

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

    REQUIRE(waitUntil([&]() {
        return !root->property("firstNotebookId").toString().isEmpty()
            && !root->property("secondNotebookId").toString().isEmpty();
    }));
    const auto firstId = root->property("firstNotebookId").toString();
    const auto secondId = root->property("secondNotebookId").toString();

    QVariant firstIndexVar;
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "indexOfNotebookId",
        Q_RETURN_ARG(QVariant, firstIndexVar),
        Q_ARG(QVariant, firstId)));
    QVariant secondIndexVar;
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "indexOfNotebookId",
        Q_RETURN_ARG(QVariant, secondIndexVar),
        Q_ARG(QVariant, secondId)));

    const int firstIndex = firstIndexVar.toInt();
    REQUIRE(firstIndex >= 0);
    const int secondIndex = secondIndexVar.toInt();
    REQUIRE(secondIndex >= 0);
    REQUIRE(firstIndex < secondIndex);

    auto* pageList = findOrNull(pageTree, "pageTree_list");
    REQUIRE(pageList);

    // Collapse the first notebook and wait for the second notebook row to "snap" directly below it.
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "toggleExpandedAtIndex",
        Q_ARG(QVariant, firstIndex)));

    QQuickItem* firstRow = nullptr;
    QQuickItem* secondRow = nullptr;
    REQUIRE(waitUntil([&]() {
        if (pageList) {
            // Force creation of delegates for the indices we care about.
            QMetaObject::invokeMethod(pageList, "positionViewAtIndex", Q_ARG(int, firstIndex), Q_ARG(int, 3));
            QMetaObject::invokeMethod(pageList, "positionViewAtIndex", Q_ARG(int, secondIndex), Q_ARG(int, 3));
            QMetaObject::invokeMethod(pageList, "forceLayout");
        }
        if (!QMetaObject::invokeMethod(pageList, "itemAtIndex", Q_RETURN_ARG(QQuickItem*, firstRow), Q_ARG(int, firstIndex))) {
            return false;
        }
        if (!QMetaObject::invokeMethod(pageList, "itemAtIndex", Q_RETURN_ARG(QQuickItem*, secondRow), Q_ARG(int, secondIndex))) {
            return false;
        }
        return firstRow && secondRow;
    }));

    const bool snapped = waitUntil([&]() {
        if (pageList) {
            QMetaObject::invokeMethod(pageList, "forceLayout");
        }
        const qreal delta = secondRow->y() - (firstRow->y() + firstRow->height());
        return std::abs(delta) <= 0.5;
    });

    const qreal finalDelta = secondRow->y() - (firstRow->y() + firstRow->height());
    CAPTURE(pageList->property("spacing").toInt());
    CAPTURE(firstIndex, secondIndex);
    CAPTURE(firstRow->y(), firstRow->height());
    CAPTURE(secondRow->y(), secondRow->height());
    CAPTURE(firstRow->property("rowHeight").toInt(), firstRow->property("rowGap").toInt());
    CAPTURE(secondRow->property("rowHeight").toInt(), secondRow->property("rowGap").toInt());
    CAPTURE(finalDelta);
    REQUIRE(snapped);
}
