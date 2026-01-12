#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickTextDocument>
#include <QStringList>
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

} // namespace

TEST_CASE("QML: MarkdownEditor loads", "[qml]") {
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
        "    visible: false\n"
        "    MarkdownEditor { anchors.fill: parent }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/MarkdownEditorHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }

    REQUIRE(component.status() == QQmlComponent::Ready);
}

TEST_CASE("QML: MarkdownEditor treats HTML as plain text", "[qml]") {
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
        "    visible: false\n"
        "    MarkdownEditor { id: editor; objectName: \"markdownEditor\"; anchors.fill: parent }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/MarkdownEditorPlainTextHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* editor = root->findChild<QObject*>(QStringLiteral("markdownEditor"));
    REQUIRE(editor);

    auto* textArea = editor->findChild<QObject*>(QStringLiteral("markdownEditorTextArea"));
    REQUIRE(textArea);

    textArea->setProperty("text", QStringLiteral("<b>Hi</b>"));

    auto* quickDocObj = qvariant_cast<QObject*>(textArea->property("textDocument"));
    REQUIRE(quickDocObj);

    auto* quickDoc = qobject_cast<QQuickTextDocument*>(quickDocObj);
    REQUIRE(quickDoc);
    REQUIRE(quickDoc->textDocument());

    REQUIRE(quickDoc->textDocument()->toPlainText() == QStringLiteral("<b>Hi</b>"));
}
