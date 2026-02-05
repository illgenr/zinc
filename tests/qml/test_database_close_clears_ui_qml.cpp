#include <catch2/catch_test_macros.hpp>

#include <QCoreApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QMetaObject>
#include <QStringList>
#include <QUrl>
#include <memory>

#include "ui/qml_types.hpp"

namespace {

void registerTypesOnce() {
    static bool registered = false;
    if (registered) return;
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

QVariant call(QObject& obj, const char* method) {
    QVariant out;
    const bool ok = QMetaObject::invokeMethod(&obj, method, Q_RETURN_ARG(QVariant, out));
    REQUIRE(ok);
    return out;
}

void callVoid(QObject& obj, const char* method) {
    const bool ok = QMetaObject::invokeMethod(&obj, method);
    REQUIRE(ok);
}

void pumpEvents(int times = 5) {
    for (int i = 0; i < times; i++) {
        QCoreApplication::processEvents();
    }
}

QObject* findRequired(QObject& root, const char* name) {
    auto* child = root.findChild<QObject*>(QString::fromLatin1(name));
    REQUIRE(child != nullptr);
    return child;
}

} // namespace

TEST_CASE("QML: Closing database clears navigation and disables editor", "[qml][datastore][ui]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "ApplicationWindow {\n"
        "  id: root\n"
        "  width: 800\n"
        "  height: 600\n"
        "  visible: false\n"
        "  function getPages() { return pageTree.getAllPages() }\n"
        "  function closeDb() {\n"
        "    if (!DataStore) return\n"
        "    DataStore.closeDatabase()\n"
        "    if (editor && editor.clearPage) editor.clearPage()\n"
        "  }\n"
        "  PageTree {\n"
        "    id: pageTree\n"
        "    objectName: \"pageTree\"\n"
        "    anchors.left: parent.left\n"
        "    anchors.top: parent.top\n"
        "    width: 280\n"
        "    height: parent.height\n"
        "    onPageSelected: function(pageId, title) { editor.loadPage(pageId) }\n"
        "  }\n"
        "  BlockEditor {\n"
        "    id: editor\n"
        "    objectName: \"blockEditor\"\n"
        "    anchors.left: pageTree.right\n"
        "    anchors.top: parent.top\n"
        "    anchors.right: parent.right\n"
        "    anchors.bottom: parent.bottom\n"
        "    enabled: DataStore && DataStore.schemaVersion >= 0\n"
        "    availablePages: pageTree.getAllPages()\n"
        "  }\n"
        "  Component.onCompleted: {\n"
        "    if (DataStore) DataStore.initialize()\n"
        "    Qt.callLater(function() {\n"
        "      pageTree.createPage(\"\", { selectAfterCreate: true })\n"
        "    })\n"
        "  }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/DatabaseCloseHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    pumpEvents();

    auto* pageTree = findRequired(*root, "pageTree");
    auto* editor = findRequired(*root, "blockEditor");

    const auto beforePages = call(*root, "getPages").toList();
    REQUIRE(beforePages.size() > 0);
    REQUIRE(editor->property("pageId").toString() != QString());

    callVoid(*root, "closeDb");
    pumpEvents();

    const auto afterPages = call(*root, "getPages").toList();
    REQUIRE(afterPages.size() == 0);
    REQUIRE(editor->property("pageId").toString() == QString());
    REQUIRE(editor->property("enabled").toBool() == false);
}
