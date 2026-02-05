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

TEST_CASE("DataStore: createFolder creates a child directory", "[qml][settings][export]") {
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());

    zinc::ui::DataStore store;
    const auto created = store.createFolder(QUrl::fromLocalFile(tmp.path()), QStringLiteral("Child Folder"));
    REQUIRE(created.isValid());
    REQUIRE(created.isLocalFile());
    REQUIRE(QDir(created.toLocalFile()).exists());
}

TEST_CASE("DataStore: createNewDatabase + openDatabaseFile + closeDatabase", "[qml][settings][export]") {
    // Tests run with ZINC_DB_PATH set; disable env override for this test.
    const auto had = qEnvironmentVariableIsSet("ZINC_DB_PATH");
    const auto old = qEnvironmentVariable("ZINC_DB_PATH");
    if (had) qunsetenv("ZINC_DB_PATH");

    QSettings settings;
    settings.remove(QStringLiteral("storage/database_path"));

    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());

    const auto okCreate = store.createNewDatabase(QUrl::fromLocalFile(tmp.path()), QStringLiteral("test.db"));
    REQUIRE(okCreate);
    REQUIRE(QFile::exists(QDir(tmp.path()).filePath(QStringLiteral("test.db"))));

    store.closeDatabase();
    REQUIRE(store.schemaVersion() == -1);

    REQUIRE(store.openDatabaseFile(QUrl::fromLocalFile(QDir(tmp.path()).filePath(QStringLiteral("test.db")))));
    REQUIRE(store.schemaVersion() >= 0);

    if (had) qputenv("ZINC_DB_PATH", old.toUtf8());
}
