#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QFile>
#include <QRegularExpression>
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

QString readAllText(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

bool containsRegex(const QString& text, const QRegularExpression& re) {
    return re.match(text).hasMatch();
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

TEST_CASE("QML: SlashMenu mobile layout avoids keyboard and respects theme", "[qml]") {
    const auto qml = readAllText(QStringLiteral(":/qt/qml/zinc/qml/components/SlashMenu.qml"));
    REQUIRE(!qml.isEmpty());

    // Dark mode: ensure TextField uses theme text colors (avoid default black-on-dark).
    REQUIRE(qml.contains(QStringLiteral("placeholderTextColor: ThemeManager.textMuted")));
    REQUIRE(qml.contains(QStringLiteral("color: ThemeManager.text")));

    // Mobile UX: list is above the filter input so the input stays visible above IME.
    const auto listPos = qml.indexOf(QStringLiteral("ListView {"));
    const auto inputPos = qml.indexOf(QStringLiteral("TextField {"));
    REQUIRE(listPos >= 0);
    REQUIRE(inputPos >= 0);
    REQUIRE(listPos < inputPos);

    // Mobile positioning: prefer anchoring above the caret/block.
    REQUIRE(containsRegex(qml, QRegularExpression(QStringLiteral(R"(desiredTopY\s*=\s*root\._isMobile\s*\?\s*\(root\.desiredY\s*-\s*root\.height\)\s*:\s*root\.desiredY)"))));
}
