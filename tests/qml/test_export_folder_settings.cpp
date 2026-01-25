#include <catch2/catch_test_macros.hpp>

#include <QDir>
#include <QSettings>
#include <QTemporaryDir>
#include <QUrl>

#include "ui/DataStore.hpp"

namespace {

constexpr auto kKeyExportLastFolder = "ui/export_last_folder";

} // namespace

TEST_CASE("Export folder setting: defaults to home directory", "[qml][settings][export]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyExportLastFolder));

    zinc::ui::DataStore store;
    REQUIRE(store.exportLastFolder().isValid());
    REQUIRE(store.exportLastFolder().isLocalFile());
    REQUIRE(store.exportLastFolder().toLocalFile() == QDir::homePath());
}

TEST_CASE("Export folder setting: persists selected folder", "[qml][settings][export]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyExportLastFolder));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    const auto url = QUrl::fromLocalFile(tmp.path());

    {
        zinc::ui::DataStore store;
        store.setExportLastFolder(url);
        REQUIRE(settings.value(QString::fromLatin1(kKeyExportLastFolder)).toString() == tmp.path());
        REQUIRE(store.exportLastFolder().toLocalFile() == tmp.path());
    }

    {
        zinc::ui::DataStore store2;
        REQUIRE(store2.exportLastFolder().toLocalFile() == tmp.path());
    }
}

