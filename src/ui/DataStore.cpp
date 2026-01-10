#include "ui/DataStore.hpp"
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>

namespace zinc::ui {

DataStore::DataStore(QObject* parent)
    : QObject(parent)
{
}

DataStore::~DataStore() {
    if (m_db.isOpen()) {
        m_db.close();
    }
}

QString DataStore::getDatabasePath() {
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir dir(dataPath);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dataPath + "/zinc.db";
}

bool DataStore::initialize() {
    if (m_ready) return true;
    
    QString dbPath = getDatabasePath();
    qDebug() << "DataStore: Opening database at" << dbPath;
    
    m_db = QSqlDatabase::addDatabase("QSQLITE", "zinc_datastore");
    m_db.setDatabaseName(dbPath);
    
    if (!m_db.open()) {
        qWarning() << "DataStore: Failed to open database:" << m_db.lastError().text();
        emit error("Failed to open database: " + m_db.lastError().text());
        return false;
    }
    
    createTables();
    m_ready = true;
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
    
    // Create index for faster lookups
    query.exec("CREATE INDEX IF NOT EXISTS idx_blocks_page_id ON blocks(page_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_pages_parent_id ON pages(parent_id)");
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
        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    )");
    
    query.addBindValue(page["pageId"].toString());
    query.addBindValue(page["title"].toString());
    query.addBindValue(page["parentId"].toString());
    query.addBindValue(page["depth"].toInt());
    query.addBindValue(page["sortOrder"].toInt());
    
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
    
    // Clear existing pages
    QSqlQuery deleteQuery(m_db);
    deleteQuery.exec("DELETE FROM pages");
    
    // Insert all pages
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO pages (id, title, parent_id, depth, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    )");
    
    for (int i = 0; i < pages.size(); ++i) {
        QVariantMap page = pages[i].toMap();
        query.addBindValue(page["pageId"].toString());
        query.addBindValue(page["title"].toString());
        query.addBindValue(page["parentId"].toString());
        query.addBindValue(page["depth"].toInt());
        query.addBindValue(i); // Use index as sort order
        
        if (!query.exec()) {
            qWarning() << "DataStore: Failed to save page:" << query.lastError().text();
        }
    }
    
    m_db.commit();
    emit pagesChanged();
}

QVariantList DataStore::getBlocksForPage(const QString& pageId) {
    QVariantList blocks;
    
    if (!m_ready) return blocks;
    
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order
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
            blocks.append(block);
        }
    }
    
    return blocks;
}

void DataStore::saveBlocksForPage(const QString& pageId, const QVariantList& blocks) {
    if (!m_ready) return;
    
    m_db.transaction();
    
    // Delete existing blocks for this page
    QSqlQuery deleteQuery(m_db);
    deleteQuery.prepare("DELETE FROM blocks WHERE page_id = ?");
    deleteQuery.addBindValue(pageId);
    deleteQuery.exec();
    
    // Insert new blocks
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO blocks (id, page_id, block_type, content, depth, checked, collapsed, language, heading_level, sort_order, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
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

} // namespace zinc::ui

