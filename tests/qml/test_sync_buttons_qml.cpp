#include <catch2/catch_test_macros.hpp>

#include <QCoreApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QScopedPointer>
#include <QStringList>
#include <QUrl>

namespace {

QString formatErrors(const QList<QQmlError>& errors) {
    QStringList lines;
    lines.reserve(errors.size());
    for (const auto& error : errors) {
        lines.append(error.toString());
    }
    return lines.join('\n');
}

QObject* findRequired(QObject& root, const char* name) {
    auto* child = root.findChild<QObject*>(QString::fromLatin1(name));
    REQUIRE(child != nullptr);
    return child;
}

} // namespace

TEST_CASE("QML: SyncButtons shows manual sync only when auto-sync disabled", "[qml][sync]") {
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(
        "import QtQuick\n"
        "import QtQuick.Controls\n"
        "import zinc 1.0\n"
        "SyncButtons { autoSyncEnabled: true }",
        QUrl(QStringLiteral("qrc:/qt/qml/zinc/tests/SyncButtons.qml")));

    if (component.status() == QQmlComponent::Error) {
        FAIL(formatErrors(component.errors()).toStdString());
    }
    REQUIRE(component.status() == QQmlComponent::Ready);

    QScopedPointer<QObject> instance(component.create());
    REQUIRE(instance);

    auto* manual = findRequired(*instance, "manualSyncButton");
    REQUIRE(manual->property("visible").toBool() == false);

    instance->setProperty("autoSyncEnabled", false);
    QCoreApplication::processEvents();
    REQUIRE(manual->property("visible").toBool() == true);
}

