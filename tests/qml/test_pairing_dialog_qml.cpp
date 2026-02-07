#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QFile>
#include <QStringList>
#include <QUrl>

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

QString readAllText(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

} // namespace

TEST_CASE("QML: PairingDialog loads", "[qml]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc\n"
        "import Zinc 1.0\n"
        "ApplicationWindow {\n"
        "    width: 800\n"
        "    height: 600\n"
        "    visible: false\n"
        "    PairingDialog { anchors.centerIn: parent }\n"
        "}\n",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/PairingDialogHost.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }

    REQUIRE(component.status() == QQmlComponent::Ready);

    // Component load is enough to catch QML compile errors.
}

TEST_CASE("QML: PairingDialog exposes add via hostname option", "[qml]") {
    const auto contents = readAllText(QStringLiteral(":/qt/qml/zinc/qml/dialogs/PairingDialog.qml"));
    REQUIRE(!contents.isEmpty());
    REQUIRE(contents.contains(QStringLiteral("Add via Hostname (Tailscale)")));
}
