#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>

namespace zinc::ui {

/**
 * DataStore - SQLite-backed storage for pages and blocks.
 * Exposed to QML as a singleton.
 */
class DataStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    
public:
    explicit DataStore(QObject* parent = nullptr);
    ~DataStore() override;
    
    static DataStore* create(QQmlEngine*, QJSEngine*) {
        static DataStore instance;
        return &instance;
    }
    
    // Page operations
    Q_INVOKABLE QVariantList getAllPages();
    Q_INVOKABLE QVariantMap getPage(const QString& pageId);
    Q_INVOKABLE void savePage(const QVariantMap& page);
    Q_INVOKABLE void deletePage(const QString& pageId);
    Q_INVOKABLE void saveAllPages(const QVariantList& pages);
    
    // Block operations  
    Q_INVOKABLE QVariantList getBlocksForPage(const QString& pageId);
    Q_INVOKABLE void saveBlocksForPage(const QString& pageId, const QVariantList& blocks);
    Q_INVOKABLE void deleteBlocksForPage(const QString& pageId);
    
    // Initialize database
    Q_INVOKABLE bool initialize();
    Q_INVOKABLE bool isReady() const { return m_ready; }
    
    // Database management
    Q_INVOKABLE QString databasePath() const;
    Q_INVOKABLE bool resetDatabase();
    Q_INVOKABLE bool runMigrations();
    Q_INVOKABLE int schemaVersion() const;
    
signals:
    void pagesChanged();
    void blocksChanged(const QString& pageId);
    void error(const QString& message);

private:
    void createTables();
    QString getDatabasePath();
    
    QSqlDatabase m_db;
    bool m_ready = false;
};

} // namespace zinc::ui

