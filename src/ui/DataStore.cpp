#include "ui/DataStore.hpp"
#include <QDateTime>
#include <QTimeZone>
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSet>
#include <QDebug>

namespace zinc::ui {

namespace {

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
    return QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd HH:mm:ss.zzz");
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
        m_db = QSqlDatabase::database(connectionName);
    } else {
        m_db = QSqlDatabase::addDatabase("QSQLITE", connectionName);
    }
    m_db.setDatabaseName(dbPath);
    
    if (!m_db.open()) {
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
            depth INTEGER DEFAULT 0,
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
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

    // Create index for faster lookups
    query.exec("CREATE INDEX IF NOT EXISTS idx_blocks_page_id ON blocks(page_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_pages_parent_id ON pages(parent_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_paired_devices_workspace_id ON paired_devices(workspace_id)");
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
    query.exec("SELECT id, title, parent_id, depth, sort_order, updated_at FROM pages ORDER BY sort_order, created_at");

    while (query.next()) {
        QVariantMap page;
        page["pageId"] = query.value(0).toString();
        page["title"] = query.value(1).toString();
        page["parentId"] = query.value(2).toString();
        page["depth"] = query.value(3).toInt();
        page["sortOrder"] = query.value(4).toInt();
        page["updatedAt"] = query.value(5).toString();
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
        SELECT id, title, parent_id, depth, sort_order, updated_at
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
        page["depth"] = query.value(3).toInt();
        page["sortOrder"] = query.value(4).toInt();
        page["updatedAt"] = query.value(5).toString();
        pages.append(page);
    }

    qDebug() << "DataStore: getPagesForSyncSince count=" << pages.size()
             << "cursorAt=" << updatedAtCursor << "cursorId=" << pageIdCursor;
    return pages;
}

QVariantMap DataStore::getPage(const QString& pageId) {
    QVariantMap page;
    
    if (!m_ready) return page;
    
    QSqlQuery query(m_db);
    query.prepare("SELECT id, title, parent_id, depth, sort_order FROM pages WHERE id = ?");
    query.addBindValue(pageId);
    
    if (query.exec() && query.next()) {
        page["pageId"] = query.value(0).toString();
        page["title"] = query.value(1).toString();
        page["parentId"] = query.value(2).toString();
        page["depth"] = query.value(3).toInt();
        page["sortOrder"] = query.value(4).toInt();
    }
    
    return page;
}

void DataStore::savePage(const QVariantMap& page) {
    if (!m_ready) return;
    
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT OR REPLACE INTO pages (id, title, parent_id, depth, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
    )");
    
    const QString updatedAt = QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd HH:mm:ss.zzz");
    query.addBindValue(page["pageId"].toString());
    query.addBindValue(normalize_title(page.value("title")));
    query.addBindValue(normalize_parent_id(page.value("parentId")));
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
    
    // Delete blocks for this page first
    deleteBlocksForPage(pageId);
    
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM pages WHERE id = ?");
    query.addBindValue(pageId);
    
    if (!query.exec()) {
        qWarning() << "DataStore: Failed to delete page:" << query.lastError().text();
        emit error("Failed to delete page: " + query.lastError().text());
    }
    
    emit pagesChanged();
}

void DataStore::saveAllPages(const QVariantList& pages) {
    if (!m_ready) return;
    
    m_db.transaction();
    const QString updatedAt = QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd HH:mm:ss.zzz");
    
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
    if (!ids.isEmpty()) {
        QString placeholders;
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
    }

    QSqlQuery selectQuery(m_db);
    selectQuery.prepare("SELECT title, parent_id, depth, sort_order FROM pages WHERE id = ?");

    QSqlQuery insertQuery(m_db);
    insertQuery.prepare(R"SQL(
        INSERT INTO pages (id, title, parent_id, depth, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
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
            insertQuery.bindValue(3, depth);
            insertQuery.bindValue(4, sortOrder);
            insertQuery.bindValue(5, updatedAt);
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

    QSqlQuery selectQuery(m_db);
    selectQuery.prepare("SELECT updated_at FROM pages WHERE id = ?");

    QSqlQuery upsertQuery(m_db);
    upsertQuery.prepare(R"SQL(
        INSERT INTO pages (id, title, parent_id, depth, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            parent_id = excluded.parent_id,
            depth = excluded.depth,
            sort_order = excluded.sort_order,
            updated_at = excluded.updated_at;
    )SQL");

    for (const auto& entry : pages) {
        auto page = entry.toMap();
        const QString pageId = page.value("pageId").toString();
        if (pageId.isEmpty()) {
            continue;
        }

        const QString remoteUpdated = page.value("updatedAt").toString();
        QDateTime remoteTime = parse_timestamp(remoteUpdated);

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
        upsertQuery.bindValue(3, page.value("depth").toInt());
        upsertQuery.bindValue(4, page.value("sortOrder").toInt());
        upsertQuery.bindValue(5, normalize_timestamp(page.value("updatedAt")));
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
    }
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
        emit blocksChanged(pageId);
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
    const QString updatedAt = QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd HH:mm:ss.zzz");
    
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
    emit blocksChanged(pageId);
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

    emit pairedDevicesChanged();
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
