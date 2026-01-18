#include "ui/DataStore.hpp"
#include "ui/MarkdownBlocks.hpp"
#include <QDateTime>
#include <QTimeZone>
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSettings>
#include <QSet>
#include <QDebug>
#include <QRegularExpression>
#include <QUuid>
#include <optional>

namespace zinc::ui {

namespace {

constexpr const char* kSettingsDeletedPagesRetention = "sync/deleted_pages_retention";
constexpr const char* kSettingsStartupMode = "ui/startup_mode";
constexpr const char* kSettingsStartupFixedPageId = "ui/startup_fixed_page_id";
constexpr const char* kSettingsLastViewedPageId = "ui/last_viewed_page_id";
constexpr int kDefaultDeletedPagesRetention = 100;
constexpr int kMaxDeletedPagesRetention = 10000;
constexpr auto kDefaultPagesSeedTimestamp = "1900-01-01 00:00:00.000";

QString now_timestamp_utc() {
    return QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd HH:mm:ss.zzz");
}

int normalize_startup_mode(int mode) {
    return (mode == 1) ? 1 : 0;
}

int normalize_retention_limit(int limit) {
    if (limit < 0) return 0;
    if (limit > kMaxDeletedPagesRetention) return kMaxDeletedPagesRetention;
    return limit;
}

int deleted_pages_retention_limit() {
    QSettings settings;
    return normalize_retention_limit(
        settings.value(QString::fromLatin1(kSettingsDeletedPagesRetention),
                       kDefaultDeletedPagesRetention).toInt());
}

int startup_page_mode() {
    QSettings settings;
    return normalize_startup_mode(settings.value(QString::fromLatin1(kSettingsStartupMode), 0).toInt());
}

QString startup_fixed_page_id() {
    QSettings settings;
    return settings.value(QString::fromLatin1(kSettingsStartupFixedPageId), QString{}).toString();
}

QString last_viewed_page_id() {
    QSettings settings;
    return settings.value(QString::fromLatin1(kSettingsLastViewedPageId), QString{}).toString();
}

QString page_id_from_variant_map(const QVariantMap& page) {
    const auto pageId = page.value(QStringLiteral("pageId")).toString();
    if (!pageId.isEmpty()) return pageId;
    return page.value(QStringLiteral("id")).toString();
}

QString first_page_id(const QVariantList& pages) {
    if (pages.isEmpty()) return {};
    const auto page = pages.first().toMap();
    return page_id_from_variant_map(page);
}

QSet<QString> page_ids_set(const QVariantList& pages) {
    QSet<QString> ids;
    ids.reserve(pages.size());
    for (const auto& v : pages) {
        const auto page = v.toMap();
        const auto id = page_id_from_variant_map(page);
        if (!id.isEmpty()) {
            ids.insert(id);
        }
    }
    return ids;
}

QString resolve_startup_page_id(int mode,
                               const QString& lastViewedId,
                               const QString& fixedId,
                               const QVariantList& pages) {
    const auto ids = page_ids_set(pages);
    const auto has = [&ids](const QString& id) { return !id.isEmpty() && ids.contains(id); };

    if (pages.isEmpty()) return {};

    if (mode == 1) {
        if (has(fixedId)) return fixedId;
        if (has(lastViewedId)) return lastViewedId;
        return first_page_id(pages);
    }

    if (has(lastViewedId)) return lastViewedId;
    return first_page_id(pages);
}

void prune_deleted_pages(QSqlDatabase& db, int keepLimit) {
    if (keepLimit <= 0) {
        QSqlQuery clear(db);
        clear.exec("DELETE FROM deleted_pages");
        return;
    }

    QSqlQuery prune(db);
    prune.prepare(R"SQL(
        DELETE FROM deleted_pages
        WHERE page_id NOT IN (
            SELECT page_id
            FROM deleted_pages
            ORDER BY deleted_at DESC, page_id DESC
            LIMIT ?
        )
    )SQL");
    prune.addBindValue(keepLimit);
    prune.exec();
}

void upsert_deleted_page(QSqlDatabase& db,
                         const QString& pageId,
                         const QString& deletedAt) {
    if (pageId.isEmpty()) return;

    QSqlQuery upsert(db);
    upsert.prepare(R"SQL(
        INSERT INTO deleted_pages (page_id, deleted_at)
        VALUES (?, ?)
        ON CONFLICT(page_id) DO UPDATE SET
            deleted_at = excluded.deleted_at;
    )SQL");
    upsert.addBindValue(pageId);
    upsert.addBindValue(deletedAt);
    upsert.exec();
}

QString resolve_database_path() {
    const auto overridePath = qEnvironmentVariable("ZINC_DB_PATH");
    if (!overridePath.isEmpty()) {
        QFileInfo info(overridePath);
        QDir dir(info.absolutePath());
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        return info.absoluteFilePath();
    }

    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir dir(dataPath);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dataPath + "/zinc.db";
}

QString resolve_attachments_dir() {
    const auto overrideDir = qEnvironmentVariable("ZINC_ATTACHMENTS_DIR");
    if (!overrideDir.isEmpty()) {
        QDir dir(overrideDir);
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        return dir.absolutePath();
    }

    const auto overrideDb = qEnvironmentVariable("ZINC_DB_PATH");
    if (!overrideDb.isEmpty()) {
        QFileInfo info(overrideDb);
        QDir dir(info.absolutePath() + "/attachments");
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        return dir.absolutePath();
    }

    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir dir(dataPath + "/attachments");
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dir.absolutePath();
}

QString normalize_attachment_id(QString id) {
    if (id.startsWith('/')) id.remove(0, 1);
    const auto queryIndex = id.indexOf('?');
    if (queryIndex >= 0) id = id.left(queryIndex);
    return id;
}

bool is_safe_attachment_id(const QString& id) {
    if (id.isEmpty()) return false;
    if (id.contains('/') || id.contains('\\')) return false;
    return true;
}

QString attachment_file_path_for_id(QString id) {
    id = normalize_attachment_id(std::move(id));
    return resolve_attachments_dir() + "/" + id;
}

bool write_bytes_atomic(const QString& path, const QByteArray& bytes) {
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        return false;
    }
    return file.commit();
}

std::optional<QByteArray> read_file_bytes(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        return std::nullopt;
    }
    return f.readAll();
}

QString normalize_parent_id(const QVariant& value) {
    const auto str = value.toString();
    return str.isNull() ? QString() : str;
}

QString normalize_title(const QVariant& value) {
    const auto raw = value.toString().trimmed();
    if (raw.isEmpty()) {
        return QStringLiteral("Untitled");
    }
    return raw;
}

QDateTime parse_timestamp(const QString& value) {
    QDateTime dt = QDateTime::fromString(value, "yyyy-MM-dd HH:mm:ss.zzz");
    if (!dt.isValid()) {
        dt = QDateTime::fromString(value, "yyyy-MM-dd HH:mm:ss");
    }
    if (!dt.isValid()) {
        dt = QDateTime::fromString(value, Qt::ISODate);
    }
    if (dt.isValid() && dt.timeSpec() == Qt::LocalTime) {
        // SQLite CURRENT_TIMESTAMP is UTC but parses as LocalTime; treat as UTC without shifting.
        dt.setTimeZone(QTimeZone::UTC);
    }
    return dt;
}

QString normalize_timestamp(const QVariant& value) {
    const auto raw = value.toString();
    if (!raw.isEmpty()) {
        return raw;
    }
    return now_timestamp_utc();
}

} // namespace

DataStore::DataStore(QObject* parent)
    : QObject(parent)
{
}

DataStore::~DataStore() {
    if (m_db.isOpen()) {
        m_db.close();
    }
    const auto connection = m_db.connectionName();
    m_db = {};
    if (!connection.isEmpty() && QSqlDatabase::contains(connection)) {
        QSqlDatabase::removeDatabase(connection);
    }
}

QString DataStore::getDatabasePath() {
    return resolve_database_path();
}

bool DataStore::initialize() {
    if (m_ready) return true;
    
    QString dbPath = getDatabasePath();
    qDebug() << "DataStore: Opening database at" << dbPath;
    
    const auto connectionName = QStringLiteral("zinc_datastore");
    if (QSqlDatabase::contains(connectionName)) {
        m_db = QSqlDatabase::database(connectionName, false);
        if (m_db.isValid() && m_db.isOpen() && m_db.databaseName() != dbPath) {
            m_db.close();
        }
    } else {
        m_db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
    }
    m_db.setDatabaseName(dbPath);
    
    if (!m_db.isOpen() && !m_db.open()) {
        qWarning() << "DataStore: Failed to open database:" << m_db.lastError().text();
        emit error("Failed to open database: " + m_db.lastError().text());
        return false;
    }
    
    createTables();
    m_ready = true;
    runMigrations();
    qDebug() << "DataStore: Database initialized successfully";
    return true;
}

void DataStore::createTables() {
    QSqlQuery query(m_db);
    
    // Pages table
    query.exec(R"(
        CREATE TABLE IF NOT EXISTS pages (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT 'Untitled',
            parent_id TEXT,
            content_markdown TEXT NOT NULL DEFAULT '',
            depth INTEGER DEFAULT 0,
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )");

    query.exec(R"(
        CREATE TABLE IF NOT EXISTS deleted_pages (
            page_id TEXT PRIMARY KEY,
            deleted_at TEXT NOT NULL
        )
    )");
    
    // Blocks table
    query.exec(R"(
        CREATE TABLE IF NOT EXISTS blocks (
            id TEXT PRIMARY KEY,
            page_id TEXT NOT NULL,
            block_type TEXT NOT NULL DEFAULT 'paragraph',
            content TEXT DEFAULT '',
            depth INTEGER DEFAULT 0,
            checked INTEGER DEFAULT 0,
            collapsed INTEGER DEFAULT 0,
            language TEXT DEFAULT '',
            heading_level INTEGER DEFAULT 0,
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE
        )
    )");

    // Paired devices table
    query.exec(R"(
        CREATE TABLE IF NOT EXISTS paired_devices (
            device_id TEXT PRIMARY KEY,
            device_name TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            host TEXT,
            port INTEGER,
            last_seen TEXT,
            paired_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )");

    // Attachments table (file-backed; bytes live on disk)
    query.exec(R"(
        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY,
            mime_type TEXT NOT NULL,
            file_name TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )");

    // Create index for faster lookups
    query.exec("CREATE INDEX IF NOT EXISTS idx_blocks_page_id ON blocks(page_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_pages_parent_id ON pages(parent_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_deleted_pages_deleted_at ON deleted_pages(deleted_at)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_paired_devices_workspace_id ON paired_devices(workspace_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_attachments_updated_at ON attachments(updated_at, id)");
}

QVariantList DataStore::getAllPages() {
    QVariantList pages;
    
    if (!m_ready) {
        qWarning() << "DataStore: Not initialized";
        return pages;
    }
    
    QSqlQuery query(m_db);
    query.exec("SELECT id, title, parent_id, depth, sort_order FROM pages ORDER BY sort_order, created_at");
    
    while (query.next()) {
        QVariantMap page;
        page["pageId"] = query.value(0).toString();
        page["title"] = query.value(1).toString();
        page["parentId"] = query.value(2).toString();
        page["depth"] = query.value(3).toInt();
        page["sortOrder"] = query.value(4).toInt();
        pages.append(page);
    }
    
    return pages;
}

QVariantList DataStore::getPagesForSync() {
    QVariantList pages;
    if (!m_ready) {
        qWarning() << "DataStore: Not initialized";
        return pages;
    }

    QSqlQuery query(m_db);
    query.exec("SELECT id, title, parent_id, content_markdown, depth, sort_order, updated_at FROM pages ORDER BY sort_order, created_at");

    while (query.next()) {
        QVariantMap page;
        page["pageId"] = query.value(0).toString();
        page["title"] = query.value(1).toString();
        page["parentId"] = query.value(2).toString();
        page["contentMarkdown"] = query.value(3).toString();
        page["depth"] = query.value(4).toInt();
        page["sortOrder"] = query.value(5).toInt();
        page["updatedAt"] = query.value(6).toString();
        pages.append(page);
    }

    qDebug() << "DataStore: getPagesForSync count=" << pages.size();
    return pages;
}

QVariantList DataStore::getPagesForSyncSince(const QString& updatedAtCursor,
                                             const QString& pageIdCursor) {
    if (updatedAtCursor.isEmpty()) {
        return getPagesForSync();
    }

    QVariantList pages;
    if (!m_ready) {
        qWarning() << "DataStore: Not initialized";
        return pages;
    }

    QSqlQuery query(m_db);
    query.prepare(R"SQL(
        SELECT id, title, parent_id, content_markdown, depth, sort_order, updated_at
        FROM pages
        WHERE updated_at > ?
           OR (updated_at = ? AND id > ?)
        ORDER BY updated_at, id
    )SQL");
    query.addBindValue(updatedAtCursor);
    query.addBindValue(updatedAtCursor);
    query.addBindValue(pageIdCursor);

    if (!query.exec()) {
        qWarning() << "DataStore: getPagesForSyncSince query failed:" << query.lastError().text();
        return pages;
    }

    while (query.next()) {
        QVariantMap page;
        page["pageId"] = query.value(0).toString();
        page["title"] = query.value(1).toString();
        page["parentId"] = query.value(2).toString();
        page["contentMarkdown"] = query.value(3).toString();
        page["depth"] = query.value(4).toInt();
        page["sortOrder"] = query.value(5).toInt();
        page["updatedAt"] = query.value(6).toString();
        pages.append(page);
    }

    qDebug() << "DataStore: getPagesForSyncSince count=" << pages.size()
             << "cursorAt=" << updatedAtCursor << "cursorId=" << pageIdCursor;
    return pages;
}

QVariantList DataStore::getDeletedPagesForSync() {
    QVariantList deletedPages;
    if (!m_ready) {
        return deletedPages;
    }

    QSqlQuery query(m_db);
    query.exec(R"SQL(
        SELECT page_id, deleted_at
        FROM deleted_pages
        ORDER BY deleted_at, page_id
    )SQL");

    while (query.next()) {
        QVariantMap entry;
        entry["pageId"] = query.value(0).toString();
        entry["deletedAt"] = query.value(1).toString();
        deletedPages.append(entry);
    }
    return deletedPages;
}

namespace {

struct ParsedDataUrl {
    QString mime;
    QByteArray bytes;
};

std::optional<ParsedDataUrl> parse_data_url(const QString& dataUrl) {
    // data:<mime>;base64,<payload>
    static const QRegularExpression re(R"(^data:([^;]+);base64,(.+)$)");
    const auto m = re.match(dataUrl);
    if (!m.hasMatch()) return std::nullopt;
    const auto mime = m.captured(1).trimmed();
    const auto b64 = m.captured(2).trimmed();
    if (mime.isEmpty() || b64.isEmpty()) return std::nullopt;

    const auto bytes = QByteArray::fromBase64(b64.toLatin1(), QByteArray::Base64Encoding);
    if (bytes.isEmpty()) return std::nullopt;
    return ParsedDataUrl{mime, bytes};
}

} // namespace

QString DataStore::saveAttachmentFromDataUrl(const QString& dataUrl) {
    if (!m_ready) return {};
    const auto parsed = parse_data_url(dataUrl);
    if (!parsed) return {};

    const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const auto updatedAt = now_timestamp_utc();

    if (!write_bytes_atomic(attachment_file_path_for_id(id), parsed->bytes)) {
        qWarning() << "DataStore: saveAttachmentFromDataUrl failed to write file id=" << id;
        return {};
    }

    QSqlQuery upsert(m_db);
    upsert.prepare(R"SQL(
        INSERT INTO attachments (id, mime_type, file_name, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            mime_type = excluded.mime_type,
            file_name = excluded.file_name,
            updated_at = excluded.updated_at;
    )SQL");
    upsert.addBindValue(id);
    upsert.addBindValue(parsed->mime);
    upsert.addBindValue(id);
    upsert.addBindValue(updatedAt);
    if (!upsert.exec()) {
        qWarning() << "DataStore: saveAttachmentFromDataUrl failed:" << upsert.lastError().text();
        return {};
    }

    emit attachmentsChanged();
    return id;
}

QVariantList DataStore::getAttachmentsForSync() {
    QVariantList out;
    if (!m_ready) return out;

    QSqlQuery query(m_db);
    query.exec(R"SQL(
        SELECT id, mime_type, file_name, updated_at
        FROM attachments
        ORDER BY updated_at, id
    )SQL");

    while (query.next()) {
        const auto id = query.value(0).toString();
        const auto fileName = query.value(2).toString().isEmpty() ? id : query.value(2).toString();
        const auto path = attachment_file_path_for_id(fileName);
        const auto bytes = read_file_bytes(path);
        if (!bytes || bytes->isEmpty()) {
            qWarning() << "DataStore: Missing attachment file id=" << id << "path=" << path;
            continue;
        }
        QVariantMap entry;
        entry["attachmentId"] = id;
        entry["mimeType"] = query.value(1).toString();
        entry["dataBase64"] = QString::fromLatin1(bytes->toBase64());
        entry["updatedAt"] = query.value(3).toString();
        out.append(entry);
    }
    return out;
}

QVariantList DataStore::getAttachmentsForSyncSince(const QString& updatedAtCursor,
                                                   const QString& attachmentIdCursor) {
    if (updatedAtCursor.isEmpty()) {
        return getAttachmentsForSync();
    }

    QVariantList out;
    if (!m_ready) return out;

    QSqlQuery query(m_db);
    query.prepare(R"SQL(
        SELECT id, mime_type, file_name, updated_at
        FROM attachments
        WHERE updated_at > ?
           OR (updated_at = ? AND id > ?)
        ORDER BY updated_at, id
    )SQL");
    query.addBindValue(updatedAtCursor);
    query.addBindValue(updatedAtCursor);
    query.addBindValue(attachmentIdCursor);
    if (!query.exec()) {
        qWarning() << "DataStore: getAttachmentsForSyncSince query failed:" << query.lastError().text();
        return out;
    }

    while (query.next()) {
        const auto id = query.value(0).toString();
        const auto fileName = query.value(2).toString().isEmpty() ? id : query.value(2).toString();
        const auto path = attachment_file_path_for_id(fileName);
        const auto bytes = read_file_bytes(path);
        if (!bytes || bytes->isEmpty()) {
            qWarning() << "DataStore: Missing attachment file id=" << id << "path=" << path;
            continue;
        }
        QVariantMap entry;
        entry["attachmentId"] = id;
        entry["mimeType"] = query.value(1).toString();
        entry["dataBase64"] = QString::fromLatin1(bytes->toBase64());
        entry["updatedAt"] = query.value(3).toString();
        out.append(entry);
    }
    return out;
}

QVariantList DataStore::getAttachmentsByIds(const QVariantList& attachmentIds) {
    QVariantList out;
    if (!m_ready) return out;
    if (attachmentIds.isEmpty()) return out;

    QSet<QString> ids;
    ids.reserve(attachmentIds.size());
    for (const auto& item : attachmentIds) {
        const auto id = normalize_attachment_id(item.toString());
        if (id.isEmpty() || !is_safe_attachment_id(id)) continue;
        ids.insert(id);
    }
    if (ids.isEmpty()) return out;

    QStringList placeholders;
    placeholders.reserve(ids.size());
    for (int i = 0; i < ids.size(); ++i) {
        placeholders.append(QStringLiteral("?"));
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT id, mime_type, file_name, updated_at "
        "FROM attachments "
        "WHERE id IN (%1) "
        "ORDER BY updated_at, id").arg(placeholders.join(',')));
    for (const auto& id : ids) {
        query.addBindValue(id);
    }
    if (!query.exec()) {
        qWarning() << "DataStore: getAttachmentsByIds query failed:" << query.lastError().text();
        return out;
    }

    while (query.next()) {
        const auto id = query.value(0).toString();
        const auto fileName = query.value(2).toString().isEmpty() ? id : query.value(2).toString();
        const auto path = attachment_file_path_for_id(fileName);
        const auto bytes = read_file_bytes(path);
        if (!bytes || bytes->isEmpty()) {
            qWarning() << "DataStore: Missing attachment file id=" << id << "path=" << path;
            continue;
        }
        QVariantMap entry;
        entry["attachmentId"] = id;
        entry["mimeType"] = query.value(1).toString();
        entry["dataBase64"] = QString::fromLatin1(bytes->toBase64());
        entry["updatedAt"] = query.value(3).toString();
        out.append(entry);
    }
    return out;
}

void DataStore::applyAttachmentUpdates(const QVariantList& attachments) {
    if (!m_ready) return;
    if (attachments.isEmpty()) return;

    const bool debugAttachments = qEnvironmentVariableIsSet("ZINC_DEBUG_ATTACHMENTS");
    const bool debugSync = qEnvironmentVariableIsSet("ZINC_DEBUG_SYNC");

    m_db.transaction();

    QSqlQuery upsert(m_db);
    upsert.prepare(R"SQL(
        INSERT INTO attachments (id, mime_type, file_name, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            mime_type = excluded.mime_type,
            file_name = excluded.file_name,
            updated_at = excluded.updated_at;
    )SQL");

    for (const auto& item : attachments) {
        const auto map = item.toMap();
        const auto id = map.value(QStringLiteral("attachmentId")).toString().isEmpty()
            ? map.value(QStringLiteral("id")).toString()
            : map.value(QStringLiteral("attachmentId")).toString();
        const auto mime = map.value(QStringLiteral("mimeType")).toString().isEmpty()
            ? map.value(QStringLiteral("mime_type")).toString()
            : map.value(QStringLiteral("mimeType")).toString();
        const auto b64 = map.value(QStringLiteral("dataBase64")).toString().isEmpty()
            ? (map.value(QStringLiteral("data_base64")).toString().isEmpty()
                ? map.value(QStringLiteral("data")).toString()
                : map.value(QStringLiteral("data_base64")).toString())
            : map.value(QStringLiteral("dataBase64")).toString();
        const auto updatedAt = map.value(QStringLiteral("updatedAt")).toString().isEmpty()
            ? map.value(QStringLiteral("updated_at")).toString()
            : map.value(QStringLiteral("updatedAt")).toString();
        if (id.isEmpty() || mime.isEmpty() || b64.isEmpty() || updatedAt.isEmpty()) continue;

        const auto bytes = QByteArray::fromBase64(b64.toLatin1(), QByteArray::Base64Encoding);
        if (bytes.isEmpty()) continue;
        const auto normalizedId = normalize_attachment_id(id);
        if (!is_safe_attachment_id(normalizedId)) continue;
        if (!write_bytes_atomic(attachment_file_path_for_id(normalizedId), bytes)) continue;

        upsert.bindValue(0, normalizedId);
        upsert.bindValue(1, mime);
        upsert.bindValue(2, normalizedId);
        upsert.bindValue(3, updatedAt);
        upsert.exec();
        upsert.finish();
    }

    m_db.commit();
    if (debugAttachments || debugSync) {
        int total = attachments.size();
        int insertedOrUpdated = 0;
        int skippedMissing = 0;
        int skippedDecode = 0;

        QSqlQuery countQuery(m_db);
        countQuery.exec(QStringLiteral("SELECT COUNT(*) FROM attachments"));
        const int afterCount = countQuery.next() ? countQuery.value(0).toInt() : -1;

        // Re-run the parsing logic cheaply for stats (no DB writes).
        for (const auto& item : attachments) {
            const auto map = item.toMap();
            const auto id = map.value(QStringLiteral("attachmentId")).toString().isEmpty()
                ? map.value(QStringLiteral("id")).toString()
                : map.value(QStringLiteral("attachmentId")).toString();
            const auto mime = map.value(QStringLiteral("mimeType")).toString().isEmpty()
                ? map.value(QStringLiteral("mime_type")).toString()
                : map.value(QStringLiteral("mimeType")).toString();
            const auto b64 = map.value(QStringLiteral("dataBase64")).toString().isEmpty()
                ? (map.value(QStringLiteral("data_base64")).toString().isEmpty()
                    ? map.value(QStringLiteral("data")).toString()
                    : map.value(QStringLiteral("data_base64")).toString())
                : map.value(QStringLiteral("dataBase64")).toString();
            const auto updatedAt = map.value(QStringLiteral("updatedAt")).toString().isEmpty()
                ? map.value(QStringLiteral("updated_at")).toString()
                : map.value(QStringLiteral("updatedAt")).toString();

            if (id.isEmpty() || mime.isEmpty() || b64.isEmpty() || updatedAt.isEmpty()) {
                skippedMissing++;
                continue;
            }
            const auto bytes = QByteArray::fromBase64(b64.toLatin1(), QByteArray::Base64Encoding);
            if (bytes.isEmpty()) {
                skippedDecode++;
                continue;
            }
            insertedOrUpdated++;
        }

        qInfo() << "DataStore: applyAttachmentUpdates total=" << total
                << "ok=" << insertedOrUpdated
                << "skippedMissing=" << skippedMissing
                << "skippedDecode=" << skippedDecode
                << "attachmentsCountAfter=" << afterCount;
    }
    emit attachmentsChanged();
}

QVariantList DataStore::getDeletedPagesForSyncSince(const QString& deletedAtCursor,
                                                    const QString& pageIdCursor) {
    if (deletedAtCursor.isEmpty()) {
        return getDeletedPagesForSync();
    }

    QVariantList deletedPages;
    if (!m_ready) {
        return deletedPages;
    }

    QSqlQuery query(m_db);
    query.prepare(R"SQL(
        SELECT page_id, deleted_at
        FROM deleted_pages
        WHERE deleted_at > ?
           OR (deleted_at = ? AND page_id > ?)
        ORDER BY deleted_at, page_id
    )SQL");
    query.addBindValue(deletedAtCursor);
    query.addBindValue(deletedAtCursor);
    query.addBindValue(pageIdCursor);

    if (!query.exec()) {
        qWarning() << "DataStore: getDeletedPagesForSyncSince query failed:" << query.lastError().text();
        return deletedPages;
    }

    while (query.next()) {
        QVariantMap entry;
        entry["pageId"] = query.value(0).toString();
        entry["deletedAt"] = query.value(1).toString();
        deletedPages.append(entry);
    }
    return deletedPages;
}

QVariantMap DataStore::getPage(const QString& pageId) {
    QVariantMap page;
    
    if (!m_ready) return page;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT id, title, parent_id, content_markdown, depth, sort_order FROM pages WHERE id = ?");
    query.addBindValue(pageId);
    
    if (query.exec() && query.next()) {
        page["pageId"] = query.value(0).toString();
        page["title"] = query.value(1).toString();
        page["parentId"] = query.value(2).toString();
        page["contentMarkdown"] = query.value(3).toString();
        page["depth"] = query.value(4).toInt();
        page["sortOrder"] = query.value(5).toInt();
    }
    
    return page;
}

void DataStore::savePage(const QVariantMap& page) {
    if (!m_ready) return;
    
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT OR REPLACE INTO pages (id, title, parent_id, content_markdown, depth, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    )");
    
    const QString updatedAt = now_timestamp_utc();
    query.addBindValue(page["pageId"].toString());
    query.addBindValue(normalize_title(page.value("title")));
    query.addBindValue(normalize_parent_id(page.value("parentId")));
    query.addBindValue(page.value("contentMarkdown").toString());
    query.addBindValue(page["depth"].toInt());
    query.addBindValue(page["sortOrder"].toInt());
    query.addBindValue(updatedAt);
    
    if (!query.exec()) {
        qWarning() << "DataStore: Failed to save page:" << query.lastError().text();
        emit error("Failed to save page: " + query.lastError().text());
    }
    
    emit pagesChanged();
}

void DataStore::deletePage(const QString& pageId) {
    if (!m_ready) return;
    
    const QString deletedAt = now_timestamp_utc();

    // Delete blocks for this page first
    deleteBlocksForPage(pageId);
    
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM pages WHERE id = ?");
    query.addBindValue(pageId);
    
    if (!query.exec()) {
        qWarning() << "DataStore: Failed to delete page:" << query.lastError().text();
        emit error("Failed to delete page: " + query.lastError().text());
    }

    upsert_deleted_page(m_db, pageId, deletedAt);
    prune_deleted_pages(m_db, deleted_pages_retention_limit());
    
    emit pagesChanged();
}

void DataStore::saveAllPages(const QVariantList& pages) {
    if (!m_ready) return;
    
    m_db.transaction();
    const QString updatedAt = now_timestamp_utc();
    const QString deletedAt = updatedAt;
    
    // Delete pages not present anymore (if any)
    QStringList ids;
    ids.reserve(pages.size());
    for (int i = 0; i < pages.size(); ++i) {
        const auto page = pages[i].toMap();
        const auto id = page.value("pageId").toString();
        if (!id.isEmpty()) {
            ids.push_back(id);
        }
    }
    QString placeholders;
    if (!ids.isEmpty()) {
        // Track which pages are being deleted so peers can remove them on sync/reconnect.
        placeholders.clear();
        placeholders.reserve(ids.size() * 2);
        for (int i = 0; i < ids.size(); ++i) {
            placeholders += (i == 0) ? "?" : ",?";
        }
        QSqlQuery removedQuery(m_db);
        removedQuery.prepare("SELECT id FROM pages WHERE id NOT IN (" + placeholders + ")");
        for (int i = 0; i < ids.size(); ++i) {
            removedQuery.addBindValue(ids[i]);
        }
        if (removedQuery.exec()) {
            while (removedQuery.next()) {
                const QString pageId = removedQuery.value(0).toString();
                deleteBlocksForPage(pageId);
                upsert_deleted_page(m_db, pageId, deletedAt);
            }
        }

        placeholders.clear();
        placeholders.reserve(ids.size() * 2);
        for (int i = 0; i < ids.size(); ++i) {
            placeholders += (i == 0) ? "?" : ",?";
        }
        QSqlQuery deleteQuery(m_db);
        deleteQuery.prepare("DELETE FROM pages WHERE id NOT IN (" + placeholders + ")");
        for (int i = 0; i < ids.size(); ++i) {
            deleteQuery.addBindValue(ids[i]);
        }
        deleteQuery.exec();
    } else {
        // Incoming page list is empty: treat as delete-all.
        QSqlQuery allIds(m_db);
        allIds.exec("SELECT id FROM pages");
        while (allIds.next()) {
            const QString pageId = allIds.value(0).toString();
            deleteBlocksForPage(pageId);
            upsert_deleted_page(m_db, pageId, deletedAt);
        }
        QSqlQuery deleteAll(m_db);
        deleteAll.exec("DELETE FROM pages");
    }

    prune_deleted_pages(m_db, deleted_pages_retention_limit());

    QSqlQuery selectQuery(m_db);
    selectQuery.prepare("SELECT title, parent_id, depth, sort_order FROM pages WHERE id = ?");

    QSqlQuery insertQuery(m_db);
    insertQuery.prepare(R"SQL(
        INSERT INTO pages (id, title, parent_id, content_markdown, depth, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    )SQL");

    QSqlQuery updateContentQuery(m_db);
    updateContentQuery.prepare(R"SQL(
        UPDATE pages
        SET title = ?, parent_id = ?, depth = ?, sort_order = ?, updated_at = ?
        WHERE id = ?
    )SQL");

    QSqlQuery updateOrderQuery(m_db);
    updateOrderQuery.prepare(R"SQL(
        UPDATE pages
        SET parent_id = ?, depth = ?, sort_order = ?, updated_at = ?
        WHERE id = ?
    )SQL");

    for (int i = 0; i < pages.size(); ++i) {
        const auto page = pages[i].toMap();
        const QString pageId = page.value("pageId").toString();
        if (pageId.isEmpty()) continue;

        const QString title = normalize_title(page.value("title"));
        const QString parentId = normalize_parent_id(page.value("parentId"));
        const int depth = page.value("depth").toInt();
        const int sortOrder = page.contains("sortOrder") ? page.value("sortOrder").toInt() : i;

        selectQuery.bindValue(0, pageId);
        bool exists = false;
        QString existingTitle;
        QString existingParent;
        int existingDepth = 0;
        int existingOrder = 0;
        if (selectQuery.exec() && selectQuery.next()) {
            exists = true;
            existingTitle = selectQuery.value(0).toString();
            existingParent = selectQuery.value(1).toString();
            existingDepth = selectQuery.value(2).toInt();
            existingOrder = selectQuery.value(3).toInt();
        }
        selectQuery.finish();

        if (!exists) {
            insertQuery.bindValue(0, pageId);
            insertQuery.bindValue(1, title);
            insertQuery.bindValue(2, parentId);
            insertQuery.bindValue(3, QStringLiteral(""));
            insertQuery.bindValue(4, depth);
            insertQuery.bindValue(5, sortOrder);
            insertQuery.bindValue(6, updatedAt);
            if (!insertQuery.exec()) {
                qWarning() << "DataStore: Failed to insert page:" << insertQuery.lastError().text();
            }
            insertQuery.finish();
            continue;
        }

        const bool contentChanged = (existingTitle != title) ||
                                    (existingParent != parentId) ||
                                    (existingDepth != depth);
        const bool orderChanged = (existingOrder != sortOrder);

        if (contentChanged) {
            updateContentQuery.bindValue(0, title);
            updateContentQuery.bindValue(1, parentId);
            updateContentQuery.bindValue(2, depth);
            updateContentQuery.bindValue(3, sortOrder);
            updateContentQuery.bindValue(4, updatedAt);
            updateContentQuery.bindValue(5, pageId);
            if (!updateContentQuery.exec()) {
                qWarning() << "DataStore: Failed to update page:" << updateContentQuery.lastError().text();
            }
            updateContentQuery.finish();
        } else if (orderChanged) {
            updateOrderQuery.bindValue(0, parentId);
            updateOrderQuery.bindValue(1, depth);
            updateOrderQuery.bindValue(2, sortOrder);
            updateOrderQuery.bindValue(3, updatedAt);
            updateOrderQuery.bindValue(4, pageId);
            if (!updateOrderQuery.exec()) {
                qWarning() << "DataStore: Failed to update page order:" << updateOrderQuery.lastError().text();
            }
            updateOrderQuery.finish();
        }
    }
    
    m_db.commit();
    emit pagesChanged();
}

void DataStore::applyPageUpdates(const QVariantList& pages) {
    if (!m_ready) return;
    qDebug() << "DataStore: applyPageUpdates incoming count=" << pages.size();

    bool changed = false;
    m_db.transaction();

    QSqlQuery tombstoneSelect(m_db);
    tombstoneSelect.prepare("SELECT deleted_at FROM deleted_pages WHERE page_id = ?");

    QSqlQuery tombstoneDelete(m_db);
    tombstoneDelete.prepare("DELETE FROM deleted_pages WHERE page_id = ?");

    QSqlQuery selectQuery(m_db);
    selectQuery.prepare("SELECT updated_at FROM pages WHERE id = ?");

    QSqlQuery upsertQuery(m_db);
    upsertQuery.prepare(R"SQL(
        INSERT INTO pages (id, title, parent_id, content_markdown, depth, sort_order, updated_at)
        VALUES (?, ?, ?, COALESCE(?, ''), ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            parent_id = excluded.parent_id,
            content_markdown = COALESCE(excluded.content_markdown, pages.content_markdown),
            depth = excluded.depth,
            sort_order = excluded.sort_order,
            updated_at = excluded.updated_at;
    )SQL");

    QSet<QString> contentChangedPages;

    for (const auto& entry : pages) {
        auto page = entry.toMap();
        const QString pageId = page.value("pageId").toString();
        if (pageId.isEmpty()) {
            continue;
        }

        const QString remoteUpdated = normalize_timestamp(page.value("updatedAt"));
        QDateTime remoteTime = parse_timestamp(remoteUpdated);

        tombstoneSelect.bindValue(0, pageId);
        QString deletedAt;
        if (tombstoneSelect.exec() && tombstoneSelect.next()) {
            deletedAt = tombstoneSelect.value(0).toString();
        }
        tombstoneSelect.finish();

        if (!deletedAt.isEmpty()) {
            QDateTime deletedTime = parse_timestamp(deletedAt);
            if (deletedTime.isValid() && remoteTime.isValid() && deletedTime > remoteTime) {
                continue;
            }
            if (deletedTime.isValid() && remoteTime.isValid() && deletedTime <= remoteTime) {
                tombstoneDelete.bindValue(0, pageId);
                tombstoneDelete.exec();
                tombstoneDelete.finish();
            }
        }

        selectQuery.bindValue(0, pageId);
        QString localUpdated;
        if (selectQuery.exec() && selectQuery.next()) {
            localUpdated = selectQuery.value(0).toString();
        }
        selectQuery.finish();

        if (!localUpdated.isEmpty()) {
            QDateTime localTime = parse_timestamp(localUpdated);
            if (localTime.isValid() && remoteTime.isValid() &&
                localTime > remoteTime) {
                qDebug() << "DataStore: skip page" << pageId << "local>remote";
                continue;
            }
        }

        upsertQuery.bindValue(0, pageId);
        upsertQuery.bindValue(1, normalize_title(page.value("title")));
        upsertQuery.bindValue(2, normalize_parent_id(page.value("parentId")));
        if (page.contains("contentMarkdown")) {
            upsertQuery.bindValue(3, page.value("contentMarkdown").toString());
            contentChangedPages.insert(pageId);
        } else {
            upsertQuery.bindValue(3, QVariant());
        }
        upsertQuery.bindValue(4, page.value("depth").toInt());
        upsertQuery.bindValue(5, page.value("sortOrder").toInt());
        upsertQuery.bindValue(6, remoteUpdated);
        if (!upsertQuery.exec()) {
            qWarning() << "DataStore: Failed to apply page update:" << upsertQuery.lastError().text();
        } else {
            changed = true;
        }
        upsertQuery.finish();
    }

    m_db.commit();
    if (changed) {
        qDebug() << "DataStore: applyPageUpdates changed";
        emit pagesChanged();
        for (const auto& pageId : contentChangedPages) {
            emit pageContentChanged(pageId);
        }
    }
}

QString DataStore::getPageContentMarkdown(const QString& pageId) {
    if (!m_ready || pageId.isEmpty()) {
        return {};
    }
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT content_markdown FROM pages WHERE id = ?"));
    query.addBindValue(pageId);
    if (!query.exec() || !query.next()) {
        return {};
    }
    return query.value(0).toString();
}

void DataStore::savePageContentMarkdown(const QString& pageId, const QString& markdown) {
    if (!m_ready || pageId.isEmpty()) {
        return;
    }

    const QString updatedAt = now_timestamp_utc();

    QSqlQuery query(m_db);
    query.prepare(R"SQL(
        INSERT INTO pages (id, title, parent_id, content_markdown, depth, sort_order, updated_at)
        VALUES (?, COALESCE((SELECT title FROM pages WHERE id = ?), 'Untitled'),
                COALESCE((SELECT parent_id FROM pages WHERE id = ?), ''),
                ?, COALESCE((SELECT depth FROM pages WHERE id = ?), 0),
                COALESCE((SELECT sort_order FROM pages WHERE id = ?), 0),
                ?)
        ON CONFLICT(id) DO UPDATE SET
            content_markdown = excluded.content_markdown,
            updated_at = excluded.updated_at;
    )SQL");
    query.addBindValue(pageId);
    query.addBindValue(pageId);
    query.addBindValue(pageId);
    query.addBindValue(markdown);
    query.addBindValue(pageId);
    query.addBindValue(pageId);
    query.addBindValue(updatedAt);

    if (!query.exec()) {
        qWarning() << "DataStore: Failed to save page content:" << query.lastError().text();
        emit error("Failed to save page content: " + query.lastError().text());
        return;
    }

    emit pageContentChanged(pageId);
}

void DataStore::applyDeletedPageUpdates(const QVariantList& deletedPages) {
    if (!m_ready) return;

    auto subtreePageIds = [&](const QString& rootId) {
        QStringList ids;
        if (rootId.isEmpty()) {
            return ids;
        }
        ids.append(rootId);
        for (int i = 0; i < ids.size(); ++i) {
            QSqlQuery children(m_db);
            children.prepare("SELECT id FROM pages WHERE parent_id = ?");
            children.addBindValue(ids[i]);
            if (!children.exec()) {
                continue;
            }
            while (children.next()) {
                const QString childId = children.value(0).toString();
                if (!childId.isEmpty() && !ids.contains(childId)) {
                    ids.append(childId);
                }
            }
        }
        return ids;
    };

    bool changed = false;
    m_db.transaction();

    QSqlQuery tombstoneSelect(m_db);
    tombstoneSelect.prepare("SELECT deleted_at FROM deleted_pages WHERE page_id = ?");

    QSqlQuery pageDelete(m_db);
    pageDelete.prepare("DELETE FROM pages WHERE id = ?");

    for (const auto& entry : deletedPages) {
        const auto deleted = entry.toMap();
        const QString pageId = deleted.value("pageId").toString();
        if (pageId.isEmpty()) {
            continue;
        }

        const QString remoteDeletedAt = normalize_timestamp(deleted.value("deletedAt"));
        QDateTime remoteDeletedTime = parse_timestamp(remoteDeletedAt);

        tombstoneSelect.bindValue(0, pageId);
        QString localDeletedAt;
        if (tombstoneSelect.exec() && tombstoneSelect.next()) {
            localDeletedAt = tombstoneSelect.value(0).toString();
        }
        tombstoneSelect.finish();

        if (!localDeletedAt.isEmpty()) {
            QDateTime localDeletedTime = parse_timestamp(localDeletedAt);
            if (localDeletedTime.isValid() && remoteDeletedTime.isValid() &&
                localDeletedTime > remoteDeletedTime) {
                continue;
            }
        }

        const auto ids = subtreePageIds(pageId);
        for (const auto& id : ids) {
            deleteBlocksForPage(id);
            pageDelete.bindValue(0, id);
            pageDelete.exec();
            pageDelete.finish();
            upsert_deleted_page(m_db, id, remoteDeletedAt);
            changed = true;
        }
    }

    prune_deleted_pages(m_db, deleted_pages_retention_limit());
    m_db.commit();
    if (changed) {
        emit pagesChanged();
    }
}

int DataStore::deletedPagesRetentionLimit() const {
    return deleted_pages_retention_limit();
}

void DataStore::setDeletedPagesRetentionLimit(int limit) {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kSettingsDeletedPagesRetention),
                      normalize_retention_limit(limit));
    if (m_ready) {
        prune_deleted_pages(m_db, deleted_pages_retention_limit());
    }
}

int DataStore::startupPageMode() const {
    return startup_page_mode();
}

void DataStore::setStartupPageMode(int mode) {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kSettingsStartupMode), normalize_startup_mode(mode));
}

QString DataStore::startupFixedPageId() const {
    return startup_fixed_page_id();
}

void DataStore::setStartupFixedPageId(const QString& pageId) {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kSettingsStartupFixedPageId), pageId);
}

QString DataStore::lastViewedPageId() const {
    return last_viewed_page_id();
}

void DataStore::setLastViewedPageId(const QString& pageId) {
    QSettings settings;
    settings.setValue(QString::fromLatin1(kSettingsLastViewedPageId), pageId);
}

QString DataStore::resolveStartupPageId(const QVariantList& pages) const {
    return resolve_startup_page_id(startup_page_mode(),
                                  last_viewed_page_id(),
                                  startup_fixed_page_id(),
                                  pages);
}

QVariantList DataStore::getBlocksForSync() {
    QVariantList blocks;
    if (!m_ready) {
        return blocks;
    }

    QSqlQuery query(m_db);
    query.exec(R"SQL(
        SELECT id, page_id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at
        FROM blocks
        ORDER BY page_id, sort_order, created_at
    )SQL");

    while (query.next()) {
        QVariantMap block;
        block["blockId"] = query.value(0).toString();
        block["pageId"] = query.value(1).toString();
        block["blockType"] = query.value(2).toString();
        block["content"] = query.value(3).toString();
        block["depth"] = query.value(4).toInt();
        block["checked"] = query.value(5).toBool();
        block["collapsed"] = query.value(6).toBool();
        block["language"] = query.value(7).toString();
        block["headingLevel"] = query.value(8).toInt();
        block["sortOrder"] = query.value(9).toInt();
        block["updatedAt"] = query.value(10).toString();
        blocks.append(block);
    }

    return blocks;
}

QVariantList DataStore::getBlocksForSyncSince(const QString& updatedAtCursor,
                                              const QString& blockIdCursor) {
    if (updatedAtCursor.isEmpty()) {
        return getBlocksForSync();
    }

    QVariantList blocks;
    if (!m_ready) {
        return blocks;
    }

    QSqlQuery query(m_db);
    query.prepare(R"SQL(
        SELECT id, page_id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at
        FROM blocks
        WHERE updated_at > ?
           OR (updated_at = ? AND id > ?)
        ORDER BY updated_at, id
    )SQL");
    query.addBindValue(updatedAtCursor);
    query.addBindValue(updatedAtCursor);
    query.addBindValue(blockIdCursor);

    if (!query.exec()) {
        qWarning() << "DataStore: getBlocksForSyncSince query failed:" << query.lastError().text();
        return blocks;
    }

    while (query.next()) {
        QVariantMap block;
        block["blockId"] = query.value(0).toString();
        block["pageId"] = query.value(1).toString();
        block["blockType"] = query.value(2).toString();
        block["content"] = query.value(3).toString();
        block["depth"] = query.value(4).toInt();
        block["checked"] = query.value(5).toBool();
        block["collapsed"] = query.value(6).toBool();
        block["language"] = query.value(7).toString();
        block["headingLevel"] = query.value(8).toInt();
        block["sortOrder"] = query.value(9).toInt();
        block["updatedAt"] = query.value(10).toString();
        blocks.append(block);
    }

    return blocks;
}

void DataStore::applyBlockUpdates(const QVariantList& blocks) {
    if (!m_ready) return;

    QSet<QString> changedPages;
    m_db.transaction();

    QSqlQuery selectQuery(m_db);
    selectQuery.prepare("SELECT updated_at FROM blocks WHERE id = ?");

    QSqlQuery upsertQuery(m_db);
    upsertQuery.prepare(R"SQL(
        INSERT INTO blocks (
            id, page_id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            page_id = excluded.page_id,
            block_type = excluded.block_type,
            content = excluded.content,
            depth = excluded.depth,
            checked = excluded.checked,
            collapsed = excluded.collapsed,
            language = excluded.language,
            heading_level = excluded.heading_level,
            sort_order = excluded.sort_order,
            updated_at = excluded.updated_at;
    )SQL");

    for (const auto& entry : blocks) {
        const auto block = entry.toMap();
        const QString blockId = block.value("blockId").toString();
        const QString pageId = block.value("pageId").toString();
        if (blockId.isEmpty() || pageId.isEmpty()) {
            continue;
        }

        const QString remoteUpdated = normalize_timestamp(block.value("updatedAt"));
        QDateTime remoteTime = parse_timestamp(remoteUpdated);

        selectQuery.bindValue(0, blockId);
        QString localUpdated;
        if (selectQuery.exec() && selectQuery.next()) {
            localUpdated = selectQuery.value(0).toString();
        }
        selectQuery.finish();

        if (!localUpdated.isEmpty()) {
            QDateTime localTime = parse_timestamp(localUpdated);
            if (localTime.isValid() && remoteTime.isValid() && localTime > remoteTime) {
                continue;
            }
        }

        upsertQuery.bindValue(0, blockId);
        upsertQuery.bindValue(1, pageId);
        upsertQuery.bindValue(2, block.value("blockType").toString());
        upsertQuery.bindValue(3, block.value("content").toString());
        upsertQuery.bindValue(4, block.value("depth").toInt());
        upsertQuery.bindValue(5, block.value("checked").toBool() ? 1 : 0);
        upsertQuery.bindValue(6, block.value("collapsed").toBool() ? 1 : 0);
        upsertQuery.bindValue(7, block.value("language").toString());
        upsertQuery.bindValue(8, block.value("headingLevel").toInt());
        upsertQuery.bindValue(9, block.value("sortOrder").toInt());
        upsertQuery.bindValue(10, remoteUpdated);

        if (upsertQuery.exec()) {
            changedPages.insert(pageId);
        } else {
            qWarning() << "DataStore: Failed to apply block update:" << upsertQuery.lastError().text();
        }
        upsertQuery.finish();
    }

    m_db.commit();
    for (const auto& pageId : changedPages) {
        emit pageContentChanged(pageId);
    }
}

QVariantList DataStore::getBlocksForPage(const QString& pageId) {
    QVariantList blocks;
    
    if (!m_ready) return blocks;
    
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at
        FROM blocks WHERE page_id = ? ORDER BY sort_order
    )");
    query.addBindValue(pageId);
    
    if (query.exec()) {
        while (query.next()) {
            QVariantMap block;
            block["blockId"] = query.value(0).toString();
            block["blockType"] = query.value(1).toString();
            block["content"] = query.value(2).toString();
            block["depth"] = query.value(3).toInt();
            block["checked"] = query.value(4).toBool();
            block["collapsed"] = query.value(5).toBool();
            block["language"] = query.value(6).toString();
            block["headingLevel"] = query.value(7).toInt();
            block["sortOrder"] = query.value(8).toInt();
            block["updatedAt"] = query.value(9).toString();
            blocks.append(block);
        }
    }
    
    return blocks;
}

void DataStore::saveBlocksForPage(const QString& pageId, const QVariantList& blocks) {
    if (!m_ready) return;
    
    m_db.transaction();
    const QString updatedAt = now_timestamp_utc();
    
    // Delete existing blocks for this page
    QSqlQuery deleteQuery(m_db);
    deleteQuery.prepare("DELETE FROM blocks WHERE page_id = ?");
    deleteQuery.addBindValue(pageId);
    deleteQuery.exec();
    
    // Insert new blocks
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO blocks (id, page_id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    )");
    
    for (int i = 0; i < blocks.size(); ++i) {
        QVariantMap block = blocks[i].toMap();
        query.addBindValue(block["blockId"].toString());
        query.addBindValue(pageId);
        query.addBindValue(block["blockType"].toString());
        query.addBindValue(block["content"].toString());
        query.addBindValue(block["depth"].toInt());
        query.addBindValue(block["checked"].toBool() ? 1 : 0);
        query.addBindValue(block["collapsed"].toBool() ? 1 : 0);
        query.addBindValue(block["language"].toString());
        query.addBindValue(block["headingLevel"].toInt());
        query.addBindValue(i);
        query.addBindValue(updatedAt);
        
        if (!query.exec()) {
            qWarning() << "DataStore: Failed to save block:" << query.lastError().text();
        }
    }
    
    m_db.commit();
    emit pageContentChanged(pageId);
}

void DataStore::deleteBlocksForPage(const QString& pageId) {
    if (!m_ready) return;
    
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM blocks WHERE page_id = ?");
    query.addBindValue(pageId);
    
    if (!query.exec()) {
        qWarning() << "DataStore: Failed to delete blocks:" << query.lastError().text();
    }
}

QVariantList DataStore::getPairedDevices() {
    QVariantList devices;
    if (!m_ready) return devices;

    QSqlQuery query(m_db);
    query.exec("SELECT device_id, device_name, workspace_id, host, port, last_seen, paired_at FROM paired_devices ORDER BY paired_at DESC");

    while (query.next()) {
        QVariantMap device;
        device["deviceId"] = query.value(0).toString();
        device["deviceName"] = query.value(1).toString();
        device["workspaceId"] = query.value(2).toString();
        device["host"] = query.value(3).toString();
        device["port"] = query.value(4).toInt();
        device["lastSeen"] = query.value(5).toString();
        device["pairedAt"] = query.value(6).toString();
        devices.append(device);
    }

    return devices;
}

void DataStore::savePairedDevice(const QString& deviceId,
                                 const QString& deviceName,
                                 const QString& workspaceId) {
    if (!m_ready) return;
    if (deviceId.isEmpty()) return;

    QSqlQuery query(m_db);
    // Remove older entries that share the same name/workspace but different IDs.
    QSqlQuery cleanup(m_db);
    cleanup.prepare("DELETE FROM paired_devices WHERE device_name = ? AND workspace_id = ? AND device_id <> ?");
    cleanup.addBindValue(deviceName);
    cleanup.addBindValue(workspaceId);
    cleanup.addBindValue(deviceId);
    cleanup.exec();

    query.prepare(R"SQL(
        INSERT INTO paired_devices (device_id, device_name, workspace_id, last_seen)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(device_id) DO UPDATE SET
            device_name = excluded.device_name,
            workspace_id = excluded.workspace_id,
            last_seen = excluded.last_seen;
    )SQL");
    query.addBindValue(deviceId);
    query.addBindValue(deviceName);
    query.addBindValue(workspaceId);

    if (!query.exec()) {
        qWarning() << "DataStore: Failed to save paired device:" << query.lastError().text();
        return;
    }

    emit pairedDevicesChanged();
}

void DataStore::updatePairedDeviceEndpoint(const QString& deviceId,
                                          const QString& host,
                                          int port) {
    if (!m_ready) return;
    if (deviceId.isEmpty()) return;

    QSqlQuery query(m_db);
    query.prepare(R"SQL(
        UPDATE paired_devices
        SET host = ?, port = ?, last_seen = CURRENT_TIMESTAMP
        WHERE device_id = ?;
    )SQL");
    query.addBindValue(host);
    query.addBindValue(port);
    query.addBindValue(deviceId);

    if (!query.exec()) {
        qWarning() << "DataStore: Failed to update paired device endpoint:" << query.lastError().text();
        return;
    }
    const auto updated = query.numRowsAffected();
    if (updated > 0) {
        emit pairedDevicesChanged();
    }
}

void DataStore::removePairedDevice(const QString& deviceId) {
    if (!m_ready) return;

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM paired_devices WHERE device_id = ?");
    query.addBindValue(deviceId);

    if (!query.exec()) {
        qWarning() << "DataStore: Failed to remove paired device:" << query.lastError().text();
        return;
    }

    emit pairedDevicesChanged();
}

void DataStore::clearPairedDevices() {
    if (!m_ready) return;

    QSqlQuery query(m_db);
    if (!query.exec("DELETE FROM paired_devices")) {
        qWarning() << "DataStore: Failed to clear paired devices:" << query.lastError().text();
        return;
    }
    emit pairedDevicesChanged();
}

bool DataStore::seedDefaultPages() {
    if (!m_ready) return false;

    struct DefaultPage {
        const char* id;
        const char* title;
        const char* parent;
        int depth;
        int sortOrder;
    };

    static constexpr DefaultPage defaults[] = {
        {"1", "Getting Started", "", 0, 0},
        {"2", "Projects", "", 0, 1},
        {"3", "Work Project", "2", 1, 2},
        {"4", "Personal", "", 0, 3},
    };

    bool insertedAny = false;
    m_db.transaction();

    QSqlQuery insert(m_db);
    insert.prepare(R"SQL(
        INSERT INTO pages (id, title, parent_id, content_markdown, depth, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, '', ?, ?, ?, ?)
        ON CONFLICT(id) DO NOTHING;
    )SQL");

    const auto seedTs = QString::fromLatin1(kDefaultPagesSeedTimestamp);
    for (const auto& page : defaults) {
        insert.bindValue(0, QString::fromLatin1(page.id));
        insert.bindValue(1, QString::fromLatin1(page.title));
        insert.bindValue(2, QString::fromLatin1(page.parent));
        insert.bindValue(3, page.depth);
        insert.bindValue(4, page.sortOrder);
        insert.bindValue(5, seedTs);
        insert.bindValue(6, seedTs);
        if (!insert.exec()) {
            qWarning() << "DataStore: seedDefaultPages failed:" << insert.lastError().text();
        } else if (insert.numRowsAffected() > 0) {
            insertedAny = true;
        }
        insert.finish();
    }

    m_db.commit();
    if (insertedAny) {
        emit pagesChanged();
    }
    return insertedAny;
}

QString DataStore::databasePath() const {
    return resolve_database_path();
}

bool DataStore::resetDatabase() {
    qDebug() << "DataStore: Resetting database...";
    
    if (m_db.isOpen()) {
        m_db.close();
    }
    
    m_ready = false;
    
    QString dbPath = databasePath();
    
    // Remove the database file
    if (QFile::exists(dbPath)) {
        if (!QFile::remove(dbPath)) {
            qWarning() << "DataStore: Failed to remove database file";
            emit error("Failed to remove database file");
            return false;
        }
        qDebug() << "DataStore: Database file removed";
    }
    
    // Also remove the journal and wal files if they exist
    QFile::remove(dbPath + "-journal");
    QFile::remove(dbPath + "-wal");
    QFile::remove(dbPath + "-shm");

    // Remove attachments stored alongside the DB (best-effort).
    QDir(resolve_attachments_dir()).removeRecursively();
    
    // Reinitialize
    if (!initialize()) {
        qWarning() << "DataStore: Failed to reinitialize database after reset";
        return false;
    }
    
    qDebug() << "DataStore: Database reset complete";
    emit pagesChanged();
    return true;
}

bool DataStore::runMigrations() {
    if (!m_ready) {
        qWarning() << "DataStore: Cannot run migrations - database not ready";
        return false;
    }
    
    QSqlQuery query(m_db);
    
    // Check current schema version
    query.exec("PRAGMA user_version");
    int currentVersion = 0;
    if (query.next()) {
        currentVersion = query.value(0).toInt();
    }
    query.finish();
    
    qDebug() << "DataStore: Current schema version:" << currentVersion;
    
    // Migration 1: Initial schema (version 0 -> 1)
    if (currentVersion < 1) {
        qDebug() << "DataStore: Running migration to version 1";
        
        m_db.transaction();
        
        // Ensure tables exist with all columns
        createTables();
        
        // Mark migration complete
        query.exec("PRAGMA user_version = 1");
        
        m_db.commit();
        currentVersion = 1;
    }
    
    // Migration 2: Paired devices table
    if (currentVersion < 2) {
        qDebug() << "DataStore: Running migration to version 2";
        m_db.transaction();
        QSqlQuery migration(m_db);
        migration.exec(R"(
            CREATE TABLE IF NOT EXISTS paired_devices (
                device_id TEXT PRIMARY KEY,
                device_name TEXT NOT NULL,
                workspace_id TEXT NOT NULL,
                host TEXT,
                port INTEGER,
                last_seen TEXT,
                paired_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        )");
        migration.exec("CREATE INDEX IF NOT EXISTS idx_paired_devices_workspace_id ON paired_devices(workspace_id)");
        migration.exec("PRAGMA user_version = 2");
        m_db.commit();
        currentVersion = 2;
    }

    // Migration 3: Endpoint fields on paired devices.
    if (currentVersion < 3) {
        qDebug() << "DataStore: Running migration to version 3";
        m_db.transaction();
        QSqlQuery migration(m_db);
        QSet<QString> columns;
        QSqlQuery info(m_db);
        if (info.exec("PRAGMA table_info(paired_devices)")) {
            while (info.next()) {
                columns.insert(info.value(1).toString());
            }
        }
        if (!columns.contains("host")) {
            migration.exec("ALTER TABLE paired_devices ADD COLUMN host TEXT");
        }
        if (!columns.contains("port")) {
            migration.exec("ALTER TABLE paired_devices ADD COLUMN port INTEGER");
        }
        if (!columns.contains("last_seen")) {
            migration.exec("ALTER TABLE paired_devices ADD COLUMN last_seen TEXT");
        }
        migration.exec("PRAGMA user_version = 3");
        m_db.commit();
        currentVersion = 3;
    }

    // Migration 4: Plume-style markdown storage per page.
    // - Add pages.content_markdown
    // - Backfill pages.content_markdown from legacy blocks table when empty
    if (currentVersion < 4) {
        qDebug() << "DataStore: Running migration to version 4";
        m_db.transaction();

        QSet<QString> pageColumns;
        QSqlQuery pageInfo(m_db);
        if (pageInfo.exec("PRAGMA table_info(pages)")) {
            while (pageInfo.next()) {
                pageColumns.insert(pageInfo.value(1).toString());
            }
        }

        QSqlQuery migration(m_db);
        if (!pageColumns.contains(QStringLiteral("content_markdown"))) {
            migration.exec("ALTER TABLE pages ADD COLUMN content_markdown TEXT NOT NULL DEFAULT ''");
        }

        QSet<QString> tables;
        QSqlQuery tableQuery(m_db);
        if (tableQuery.exec("SELECT name FROM sqlite_master WHERE type='table'")) {
            while (tableQuery.next()) {
                tables.insert(tableQuery.value(0).toString());
            }
        }

        if (tables.contains(QStringLiteral("blocks"))) {
            MarkdownBlocks codec;

            QSqlQuery pagesQuery(m_db);
            pagesQuery.exec("SELECT id FROM pages");

            QSqlQuery blocksQuery(m_db);
            blocksQuery.prepare(R"SQL(
                SELECT block_type, content, depth, checked, collapsed, language, heading_level
                FROM blocks
                WHERE page_id = ?
                ORDER BY sort_order
            )SQL");

            QSqlQuery update(m_db);
            update.prepare("UPDATE pages SET content_markdown = ? WHERE id = ? AND content_markdown = ''");

            while (pagesQuery.next()) {
                const QString pageId = pagesQuery.value(0).toString();
                if (pageId.isEmpty()) continue;

                blocksQuery.bindValue(0, pageId);
                if (!blocksQuery.exec()) {
                    blocksQuery.finish();
                    continue;
                }

                QVariantList blocks;
                while (blocksQuery.next()) {
                    QVariantMap block;
                    block["blockType"] = blocksQuery.value(0).toString();
                    block["content"] = blocksQuery.value(1).toString();
                    block["depth"] = blocksQuery.value(2).toInt();
                    block["checked"] = blocksQuery.value(3).toBool();
                    block["collapsed"] = blocksQuery.value(4).toBool();
                    block["language"] = blocksQuery.value(5).toString();
                    block["headingLevel"] = blocksQuery.value(6).toInt();
                    blocks.append(block);
                }
                blocksQuery.finish();

                if (blocks.isEmpty()) {
                    continue;
                }

                const auto markdown = codec.serializeContent(blocks);
                update.bindValue(0, markdown);
                update.bindValue(1, pageId);
                update.exec();
                update.finish();
            }
        }

        migration.exec("PRAGMA user_version = 4");
        m_db.commit();
        currentVersion = 4;
    }

    // Migration 5: Attachments table for image blobs.
    if (currentVersion < 5) {
        qDebug() << "DataStore: Running migration to version 5";
        m_db.transaction();
        QSqlQuery migration(m_db);
        migration.exec(R"(
            CREATE TABLE IF NOT EXISTS attachments (
                id TEXT PRIMARY KEY,
                mime_type TEXT NOT NULL,
                data BLOB NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        )");
        migration.exec("CREATE INDEX IF NOT EXISTS idx_attachments_updated_at ON attachments(updated_at, id)");
        migration.exec("PRAGMA user_version = 5");
        m_db.commit();
        currentVersion = 5;
    }

    // Migration 6: Move attachment blobs to disk and store only metadata in SQLite.
    if (currentVersion < 6) {
        qDebug() << "DataStore: Running migration to version 6";
        // Phase 1: copy metadata + write blobs to disk into a staging table.
        m_db.transaction();

        QSqlQuery migration(m_db);
        auto execChecked = [&](const QString& sql) -> bool {
            if (migration.exec(sql)) return true;
            qWarning() << "DataStore: Migration 6 SQL failed:" << migration.lastError().text()
                       << "sql=" << sql;
            return false;
        };

        bool ok = true;
        ok = ok && execChecked(QStringLiteral("DROP TABLE IF EXISTS attachments_v6"));
        ok = ok && execChecked(QString::fromUtf8(R"SQL(
            CREATE TABLE attachments_v6 (
                id TEXT PRIMARY KEY,
                mime_type TEXT NOT NULL,
                file_name TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        )SQL"));

        QSet<QString> columns;
        QSqlQuery info(m_db);
        if (info.exec("PRAGMA table_info(attachments)")) {
            while (info.next()) {
                columns.insert(info.value(1).toString());
            }
        }
        info.finish();

        if (!columns.isEmpty()) {
            const bool hasData = columns.contains(QStringLiteral("data"));
            const bool hasFileName = columns.contains(QStringLiteral("file_name"));
            const bool hasCreatedAt = columns.contains(QStringLiteral("created_at"));
            const bool hasUpdatedAt = columns.contains(QStringLiteral("updated_at"));

            QSqlQuery select(m_db);
            if (hasData) {
                ok = ok && select.exec("SELECT id, mime_type, data, created_at, updated_at FROM attachments");
            } else if (hasFileName && hasCreatedAt && hasUpdatedAt) {
                ok = ok && select.exec("SELECT id, mime_type, file_name, created_at, updated_at FROM attachments");
            } else if (hasFileName) {
                ok = ok && select.exec("SELECT id, mime_type, file_name FROM attachments");
            } else {
                ok = ok && select.exec("SELECT id, mime_type FROM attachments");
            }
            if (!ok) {
                qWarning() << "DataStore: Migration 6 select failed:" << select.lastError().text();
            }

            QSqlQuery insert(m_db);
            insert.prepare(R"SQL(
                INSERT INTO attachments_v6 (id, mime_type, file_name, created_at, updated_at)
                VALUES (?, ?, ?, COALESCE(NULLIF(?, ''), CURRENT_TIMESTAMP), COALESCE(NULLIF(?, ''), CURRENT_TIMESTAMP))
                ON CONFLICT(id) DO UPDATE SET
                    mime_type = excluded.mime_type,
                    file_name = excluded.file_name,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at;
            )SQL");

            while (ok && select.next()) {
                const auto id = normalize_attachment_id(select.value(0).toString());
                const auto mime = select.value(1).toString();
                if (id.isEmpty() || mime.isEmpty() || !is_safe_attachment_id(id)) {
                    continue;
                }

                QString fileName = id;
                QString createdAt;
                QString updatedAt;

                if (hasData) {
                    const auto bytes = select.value(2).toByteArray();
                    if (!bytes.isEmpty()) {
                        const auto path = attachment_file_path_for_id(id);
                        if (!QFile::exists(path)) {
                            write_bytes_atomic(path, bytes);
                        }
                    }
                    createdAt = select.value(3).toString();
                    updatedAt = select.value(4).toString();
                } else if (hasFileName && hasCreatedAt && hasUpdatedAt) {
                    fileName = select.value(2).toString().isEmpty() ? id : select.value(2).toString();
                    createdAt = select.value(3).toString();
                    updatedAt = select.value(4).toString();
                } else if (hasFileName) {
                    fileName = select.value(2).toString().isEmpty() ? id : select.value(2).toString();
                }

                insert.bindValue(0, id);
                insert.bindValue(1, mime);
                insert.bindValue(2, fileName);
                insert.bindValue(3, createdAt);
                insert.bindValue(4, updatedAt);
                if (!insert.exec()) {
                    ok = false;
                    qWarning() << "DataStore: Migration 6 insert failed:" << insert.lastError().text();
                }
                insert.finish();
            }
            select.finish();
        }

        if (!ok) {
            qWarning() << "DataStore: Migration 6 failed; rolling back";
            m_db.rollback();
            return false;
        }

        m_db.commit();

        // Phase 2: swap staging table into place.
        m_db.transaction();
        ok = ok && execChecked(QStringLiteral("DROP TABLE IF EXISTS attachments"));
        ok = ok && execChecked(QStringLiteral("ALTER TABLE attachments_v6 RENAME TO attachments"));
        ok = ok && execChecked(QStringLiteral("CREATE INDEX IF NOT EXISTS idx_attachments_updated_at ON attachments(updated_at, id)"));
        ok = ok && execChecked(QStringLiteral("PRAGMA user_version = 6"));
        if (!ok) {
            qWarning() << "DataStore: Migration 6 failed; rolling back";
            m_db.rollback();
            return false;
        }
        m_db.commit();
        currentVersion = 6;
    }
    
    qDebug() << "DataStore: Migrations complete. Schema version:" << currentVersion;
    return true;
}

int DataStore::schemaVersion() const {
    if (!m_ready) return -1;
    
    QSqlQuery query(m_db);
    query.exec("PRAGMA user_version");
    if (query.next()) {
        return query.value(0).toInt();
    }
    return -1;
}

} // namespace zinc::ui
