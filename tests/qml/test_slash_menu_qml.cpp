#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
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

bool commandsContainLabel(const QVariant& commandsVariant, const QString& label) {
    const auto list = commandsVariant.toList();
    for (const auto& entry : list) {
        const auto map = entry.toMap();
        if (map.value(QStringLiteral("label")).toString() == label) {
            return true;
        }
    }
    return false;
}

} // namespace

TEST_CASE("QML: SlashMenu includes Date and Now commands", "[qml]") {
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
        "    SlashMenu { id: menu; objectName: \"slashMenu\" }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SlashMenuHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    std::unique_ptr<QObject> root(component.create());
    REQUIRE(root);

    auto* menu = root->findChild<QObject*>(QStringLiteral("slashMenu"));
    REQUIRE(menu);

    const auto commands = menu->property("commands");
    REQUIRE(commands.isValid());

    REQUIRE(commandsContainLabel(commands, QStringLiteral("Date")));
    REQUIRE(commandsContainLabel(commands, QStringLiteral("Date/Time")));
    REQUIRE(commandsContainLabel(commands, QStringLiteral("Now")));
}
