#include <catch2/catch_test_macros.hpp>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQmlError>
#include <QScopedPointer>
#include <QStringList>
#include <QUrl>

#include "ui/qml_types.hpp"

#ifndef ZINC_ENABLE_QR
#define ZINC_ENABLE_QR 0
#endif

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

TEST_CASE("QML: FeatureFlags exposes qrEnabled", "[qml]") {
    registerTypesOnce();

    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQml\nimport Zinc 1.0\nQtObject { property bool enabled: FeatureFlags.qrEnabled }",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/FeatureFlags.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }

    REQUIRE(component.status() == QQmlComponent::Ready);

    QScopedPointer<QObject> instance(component.create());
    REQUIRE(instance);

    auto enabled = instance->property("enabled");
    REQUIRE(enabled.isValid());
    REQUIRE(enabled.toBool() == (ZINC_ENABLE_QR != 0));
}
