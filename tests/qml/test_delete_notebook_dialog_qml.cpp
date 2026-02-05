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

QQuickWindow* requireWindow(QObject* root) {
    auto* window = qobject_cast<QQuickWindow*>(root);
    REQUIRE(window);
    return window;
}

QObject* findOrNull(QObject* root, const char* objectName) {
    if (!root) return nullptr;
    return root->findChild<QObject*>(QString::fromLatin1(objectName));
}

} // namespace

TEST_CASE("QML: deleting a notebook prompts and can delete notebook pages", "[qml][pagetree][notebooks]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "    width: 700\n"
        "    height: 700\n"
        "    visible: true\n"
        "    property string nbId: \"\"\n"
        "    PageTree {\n"
        "        id: pageTree\n"
        "        objectName: \"pageTree\"\n"
        "        anchors.fill: parent\n"
        "        Component.onCompleted: {\n"
        "            if (DataStore) DataStore.resetDatabase()\n"
        "            const id = DataStore.createNotebook(\"Temp\")\n"
        "            nbId = id\n"
        "            DataStore.savePage({ pageId: \"p1\", notebookId: id, title: \"A\", parentId: \"\", depth: 0, sortOrder: 0, updatedAt: \"2026-01-01 00:00:00.000\", contentMarkdown: \"\" })\n"
        "            loadPagesFromStorage()\n"
        "        }\n"
        "    }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/DeleteNotebookDialogHost.qml")));

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

    REQUIRE(waitUntil([&]() { return !root->property("nbId").toString().isEmpty(); }));
    const auto nbId = root->property("nbId").toString();

    QVariant nbIndexVar;
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "indexOfNotebookId",
        Q_RETURN_ARG(QVariant, nbIndexVar),
        Q_ARG(QVariant, nbId)));
    REQUIRE(nbIndexVar.toInt() >= 0);

    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "requestDeleteNotebook",
        Q_ARG(QVariant, nbId),
        Q_ARG(QVariant, QStringLiteral("Temp"))));

    auto* dialogObj = findOrNull(pageTree, "deleteNotebookDialog");
    REQUIRE(dialogObj);
    REQUIRE(waitUntil([&]() { return dialogObj->property("visible").toBool(); }));

    // Opening the dialog should not delete the notebook yet.
    REQUIRE(QMetaObject::invokeMethod(pageTree,
        "indexOfNotebookId",
        Q_RETURN_ARG(QVariant, nbIndexVar),
        Q_ARG(QVariant, nbId)));
    REQUIRE(nbIndexVar.toInt() >= 0);

    auto* checkboxObj = findOrNull(pageTree, "deleteNotebookDeletePages");
    REQUIRE(checkboxObj);
    checkboxObj->setProperty("checked", true);

    auto* confirmObj = qobject_cast<QQuickItem*>(findOrNull(pageTree, "deleteNotebookConfirmButton"));
    REQUIRE(confirmObj);

    const auto clickPoint = centerPointInWindow(confirmObj);
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, clickPoint, 1);

    REQUIRE(waitUntil([&]() {
        QVariant idx;
        if (!QMetaObject::invokeMethod(pageTree,
                "indexOfNotebookId",
                Q_RETURN_ARG(QVariant, idx),
                Q_ARG(QVariant, nbId))) {
            return false;
        }
        return idx.toInt() < 0;
    }));

    QVariant pagesVar;
    REQUIRE(QMetaObject::invokeMethod(pageTree, "getAllPages", Q_RETURN_ARG(QVariant, pagesVar)));
    const auto pages = pagesVar.toList();
    bool hasP1 = false;
    for (const auto& v : pages) {
        const auto m = v.toMap();
        if (m.value(QStringLiteral("pageId")).toString() == QStringLiteral("p1")) {
            hasP1 = true;
            break;
        }
    }
    REQUIRE_FALSE(hasP1);
}
