#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStringList>
#include <QTest>
#include <QUrl>
#include <chrono>
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

QQuickWindow* requireWindow(QObject* root) {
    auto* window = qobject_cast<QQuickWindow*>(root);
    REQUIRE(window);
    return window;
}

QQuickItem* requireItem(QObject* root, const QString& objectName) {
    auto* item = root->findChild<QQuickItem*>(objectName);
    if (!item) {
        FAIL(("Missing QQuickItem: " + objectName).toStdString());
        return nullptr;
    }
    return item;
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

QPoint centerPointInWindow(QQuickItem* item) {
    const auto center = item->mapToScene(QPointF(item->width() * 0.5, item->height() * 0.5));
    return QPoint(static_cast<int>(std::lround(center.x())), static_cast<int>(std::lround(center.y())));
}

QObject* findOrNull(QObject* root, const char* objectName) {
    if (!root) return nullptr;
    return root->findChild<QObject*>(QString::fromLatin1(objectName));
}

} // namespace

TEST_CASE("QML: Hovering a collapsed folder row stays highlighted (no periodic hover flicker)", "[qml][pagetree][hover]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "    width: 800\n"
        "    height: 900\n"
        "    visible: true\n"
        "    property string notebookId: \"\"\n"
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
        "                    if (nbs[i].name === \"My Notebook\") notebookId = nbs[i].notebookId\n"
        "                }\n"
        "            })\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PageTreeHoverStabilityHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(80);

    auto* pageTree = findOrNull(root.get(), "pageTree");
    REQUIRE(pageTree);

    REQUIRE(waitUntil([&]() { return !root->property("notebookId").toString().isEmpty(); }));
    const auto notebookId = root->property("notebookId").toString();

    QVariant notebookIndexVar;
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "indexOfNotebookId",
        Q_RETURN_ARG(QVariant, notebookIndexVar),
        Q_ARG(QVariant, notebookId)));
    const int notebookIndex = notebookIndexVar.toInt();
    REQUIRE(notebookIndex >= 0);

    QVariant hasKidsVar;
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "hasChildrenAtIndex",
        Q_RETURN_ARG(QVariant, hasKidsVar),
        Q_ARG(QVariant, notebookIndex)));
    REQUIRE(hasKidsVar.toBool());

    // Collapse the notebook so it becomes a "collapsed folder" row.
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "toggleExpandedAtIndex",
        Q_ARG(QVariant, notebookIndex)));

    auto* pageList = findOrNull(pageTree, "pageTree_list");
    REQUIRE(pageList);

    QQuickItem* notebookRow = nullptr;
    REQUIRE(waitUntil([&]() {
        if (pageList) {
            QMetaObject::invokeMethod(pageList, "positionViewAtIndex", Q_ARG(int, notebookIndex), Q_ARG(int, 3));
            QMetaObject::invokeMethod(pageList, "forceLayout");
        }
        return QMetaObject::invokeMethod(pageList, "itemAtIndex", Q_RETURN_ARG(QQuickItem*, notebookRow), Q_ARG(int, notebookIndex))
            && notebookRow;
    }));

    auto* addButton = requireItem(notebookRow, QStringLiteral("pageTreeAddChildButton_%1").arg(notebookIndex));
    REQUIRE(addButton->property("visible").toBool() == false);

    auto* menuButton = requireItem(notebookRow, QStringLiteral("pageTreeMenuButton_%1").arg(notebookIndex));
    const auto initialHover = notebookRow->mapToScene(QPointF(notebookRow->width() - 6.0, notebookRow->height() * 0.5));
    QTest::mouseMove(window,
        QPoint(static_cast<int>(std::lround(initialHover.x())), static_cast<int>(std::lround(initialHover.y()))),
        1);
    REQUIRE(waitUntil([&]() { return notebookRow->property("rowHovered").toBool(); }));
    REQUIRE(waitUntil([&]() { return menuButton->property("visible").toBool(); }));

    const auto hoverPoint = centerPointInWindow(menuButton);

    QTest::mouseMove(window, hoverPoint, 1);
    REQUIRE(waitUntil([&]() { return notebookRow->property("rowHovered").toBool(); }));

    // The historic bug presented as ~1Hz hover on/off. Sample for >1s to catch periodic toggles.
    for (int i = 0; i < 13; i++) {
        QTest::qWait(100);
        CAPTURE(i);
        REQUIRE(notebookRow->property("rowHovered").toBool());
    }
}
