#include <catch2/catch_test_macros.hpp>

#include <QSettings>

#include "ui/controllers/SyncController.hpp"

TEST_CASE("SyncController: configure persists workspace and name", "[qml][sync]") {
    QSettings settings;
    settings.remove(QStringLiteral("sync/workspace_id"));
    settings.remove(QStringLiteral("sync/device_name"));

    zinc::ui::SyncController controller;
    REQUIRE(controller.configure(QStringLiteral("00000000-0000-0000-0000-000000000001"),
                                 QStringLiteral("Test Device")));

    REQUIRE(settings.value(QStringLiteral("sync/workspace_id")).toString() ==
            QStringLiteral("00000000-0000-0000-0000-000000000001"));
    REQUIRE(settings.value(QStringLiteral("sync/device_name")).toString() ==
            QStringLiteral("Test Device"));
}

