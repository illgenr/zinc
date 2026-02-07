#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickWindow>
#include <QTest>
#include <QUrl>
#include <atomic>
#include <memory>

#include "ui/qml_types.hpp"

namespace {

std::atomic<bool>* gSawBindingLoop = nullptr;
QtMessageHandler gPreviousHandler = nullptr;

void messageHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg) {
    if (type == QtWarningMsg &&
        msg.contains(QStringLiteral("Binding loop detected for property \"runs\""))) {
        if (gSawBindingLoop) {
            gSawBindingLoop->store(true);
        }
    }
    if (gPreviousHandler) {
        gPreviousHandler(type, ctx, msg);
    }
}

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

} // namespace

TEST_CASE("QML: InlineRichTextHighlighter does not cause runs binding loop warnings", "[qml][inlinerichtext]") {
    registerTypesOnce();

    std::atomic<bool> sawBindingLoop{false};
    gSawBindingLoop = &sawBindingLoop;
    gPreviousHandler = qInstallMessageHandler(messageHandler);

    auto restoreHandler = [&]() {
        qInstallMessageHandler(gPreviousHandler);
        gPreviousHandler = nullptr;
        gSawBindingLoop = nullptr;
    };

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
        "  ParagraphBlock {\n"
        "    id: p\n"
        "    objectName: \"paragraph\"\n"
        "    anchors.fill: parent\n"
        "    content: \"Hello **world**\"\n"
        "    editor: null\n"
        "    blockIndex: 0\n"
        "  }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/InlineHighlighterBindingLoopHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        restoreHandler();
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* window = requireWindow(root.get());
    window->show();
    QTest::qWait(50);

    // Stress a few content changes to drive runs updates.
    auto* paragraph = root->findChild<QObject*>(QStringLiteral("paragraph"));
    REQUIRE(paragraph);
    paragraph->setProperty("content", QStringLiteral("Hello *there*"));
    QTest::qWait(10);
    paragraph->setProperty("content", QStringLiteral("Hello **again**"));
    QTest::qWait(10);
    paragraph->setProperty("content", QStringLiteral("Plain text"));
    QTest::qWait(50);

    restoreHandler();
    REQUIRE_FALSE(sawBindingLoop.load());
}
