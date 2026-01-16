#include <catch2/catch_test_macros.hpp>

#include <QDir>
#include <QFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTemporaryDir>
#include <QVariantList>
#include <QVariantMap>

#include "ui/DataStore.hpp"

namespace {

QByteArray png_1x1_bytes() {
    return QByteArray::fromBase64(
        QByteArrayLiteral("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+5rUAAAAASUVORK5CYII="),
        QByteArray::Base64Encoding);
}

QString png_1x1_data_url() {
    const auto b64 = png_1x1_bytes().toBase64();
    return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(b64);
}

QByteArray read_all(const QString& path) {
    QFile f(path);
    REQUIRE(f.open(QIODevice::ReadOnly));
    return f.readAll();
}

QString attachments_dir_for_db(const QString& dbPath) {
    QFileInfo info(dbPath);
    return QDir(info.absolutePath()).absoluteFilePath(QStringLiteral("attachments"));
}

} // namespace

TEST_CASE("DataStore: attachments are saved to disk (not SQLite blobs)", "[qml][attachments]") {
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const auto dbPath = dir.filePath(QStringLiteral("zinc_attachments.db"));
    qputenv("ZINC_DB_PATH", dbPath.toUtf8());
    qunsetenv("ZINC_ATTACHMENTS_DIR");

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto attachmentId = store.saveAttachmentFromDataUrl(png_1x1_data_url());
    REQUIRE_FALSE(attachmentId.isEmpty());

    const auto filePath =
        QDir(attachments_dir_for_db(dbPath)).absoluteFilePath(attachmentId);
    REQUIRE(QFile::exists(filePath));
    REQUIRE(read_all(filePath) == png_1x1_bytes());

    const auto attachments = store.getAttachmentsForSync();
    REQUIRE(attachments.size() == 1);
    const auto row = attachments[0].toMap();
    REQUIRE(row.value("attachmentId").toString() == attachmentId);
    REQUIRE(row.value("mimeType").toString() == QStringLiteral("image/png"));
    REQUIRE(row.value("dataBase64").toString().toLatin1() == png_1x1_bytes().toBase64());
    REQUIRE_FALSE(row.value("updatedAt").toString().isEmpty());
}

TEST_CASE("DataStore: applyAttachmentUpdates writes attachment bytes to disk", "[qml][attachments]") {
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const auto dbPath = dir.filePath(QStringLiteral("zinc_attachments_apply.db"));
    qputenv("ZINC_DB_PATH", dbPath.toUtf8());
    qunsetenv("ZINC_ATTACHMENTS_DIR");

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    QVariantMap incoming;
    incoming.insert("attachmentId", QStringLiteral("00000000-0000-0000-0000-000000000001"));
    incoming.insert("mimeType", QStringLiteral("image/png"));
    incoming.insert("dataBase64", QString::fromLatin1(png_1x1_bytes().toBase64()));
    incoming.insert("updatedAt", QStringLiteral("2026-01-12 00:00:00.000"));

    QVariantList batch;
    batch.append(incoming);
    store.applyAttachmentUpdates(batch);

    const auto filePath =
        QDir(attachments_dir_for_db(dbPath)).absoluteFilePath(incoming.value("attachmentId").toString());
    REQUIRE(QFile::exists(filePath));
    REQUIRE(read_all(filePath) == png_1x1_bytes());

    const auto attachments = store.getAttachmentsForSync();
    REQUIRE(attachments.size() == 1);
}

TEST_CASE("DataStore: getAttachmentsByIds returns requested rows", "[qml][attachments]") {
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const auto dbPath = dir.filePath(QStringLiteral("zinc_attachments_byid.db"));
    qputenv("ZINC_DB_PATH", dbPath.toUtf8());
    qunsetenv("ZINC_ATTACHMENTS_DIR");

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto firstId = store.saveAttachmentFromDataUrl(png_1x1_data_url());
    REQUIRE_FALSE(firstId.isEmpty());

    QVariantList ids;
    ids.append(firstId);
    ids.append(QStringLiteral("not-a-real-id"));

    const auto rows = store.getAttachmentsByIds(ids);
    REQUIRE(rows.size() == 1);
    const auto row = rows[0].toMap();
    REQUIRE(row.value("attachmentId").toString() == firstId);
    REQUIRE(row.value("dataBase64").toString().toLatin1() == png_1x1_bytes().toBase64());
}

TEST_CASE("DataStore: migration moves blob attachments to disk", "[qml][attachments]") {
    QTemporaryDir dir;
    REQUIRE(dir.isValid());
    const auto dbPath = dir.filePath(QStringLiteral("zinc_attachments_migrate.db"));

    {
        const auto connectionName = QStringLiteral("zinc_attachments_migrate_seed");
        {
            QSqlDatabase db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), connectionName);
            db.setDatabaseName(dbPath);
            REQUIRE(db.open());

            QSqlQuery q(db);
            REQUIRE(q.exec(QStringLiteral("PRAGMA user_version = 5")));
            REQUIRE(q.exec(QStringLiteral(
                "CREATE TABLE attachments ("
                "id TEXT PRIMARY KEY,"
                "mime_type TEXT NOT NULL,"
                "data BLOB NOT NULL,"
                "created_at TEXT DEFAULT CURRENT_TIMESTAMP,"
                "updated_at TEXT DEFAULT CURRENT_TIMESTAMP"
                ")")));

            QSqlQuery insert(db);
            insert.prepare(QStringLiteral(
                "INSERT INTO attachments (id, mime_type, data, updated_at) VALUES (?, ?, ?, ?)"));
            insert.addBindValue(QStringLiteral("00000000-0000-0000-0000-000000000002"));
            insert.addBindValue(QStringLiteral("image/png"));
            insert.addBindValue(png_1x1_bytes());
            insert.addBindValue(QStringLiteral("2026-01-12 00:00:00.000"));
            REQUIRE(insert.exec());

            db.close();
        }
        QSqlDatabase::removeDatabase(connectionName);
    }

    qputenv("ZINC_DB_PATH", dbPath.toUtf8());
    qunsetenv("ZINC_ATTACHMENTS_DIR");

    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.schemaVersion() >= 6);

    const auto filePath =
        QDir(attachments_dir_for_db(dbPath)).absoluteFilePath(QStringLiteral("00000000-0000-0000-0000-000000000002"));
    REQUIRE(QFile::exists(filePath));
    REQUIRE(read_all(filePath) == png_1x1_bytes());

    const auto attachments = store.getAttachmentsForSync();
    REQUIRE(attachments.size() == 1);
}
