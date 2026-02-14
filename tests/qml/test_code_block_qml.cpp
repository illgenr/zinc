#include <catch2/catch_test_macros.hpp>

#include <QClipboard>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QSignalSpy>
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

std::unique_ptr<QObject> createCodeBlock(QQmlEngine& engine) {
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "import \"qrc:/qt/qml/zinc/qml/components/blocks\"\n"
        "CodeBlock {\n"
        "    objectName: \"codeBlockRoot\"\n"
        "    content: \"line1\\nline2\"\n"
        "    codeLanguage: \"\"\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/CodeBlockHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);
    return std::unique_ptr<QObject>(component.create());
}

} // namespace

TEST_CASE("QML: CodeBlock copy button copies full code content", "[qml][codeblock]") {
    registerTypesOnce();

    QQmlEngine engine;
    auto root = createCodeBlock(engine);
    REQUIRE(root);

    auto* copyButton = root->findChild<QObject*>(QStringLiteral("codeBlockCopyButton"));
    REQUIRE(copyButton);

    const bool clicked = QMetaObject::invokeMethod(copyButton, "click");
    REQUIRE(clicked);
    REQUIRE(QGuiApplication::clipboard()->text() == QStringLiteral("line1\nline2"));
}

TEST_CASE("QML: CodeBlock emits languageEdited when language field changes", "[qml][codeblock]") {
    registerTypesOnce();

    QQmlEngine engine;
    auto root = createCodeBlock(engine);
    REQUIRE(root);

    QSignalSpy spy(root.get(), SIGNAL(languageEdited(QString)));
    REQUIRE(spy.isValid());

    auto* languageField = root->findChild<QObject*>(QStringLiteral("codeBlockLanguageField"));
    REQUIRE(languageField);

    languageField->setProperty("text", QStringLiteral("python"));

    REQUIRE(spy.count() == 1);
    const QList<QVariant> args = spy.takeFirst();
    REQUIRE(args.size() == 1);
    REQUIRE(args.at(0).toString() == QStringLiteral("python"));
}
