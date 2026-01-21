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
    
    static DataStore* create(QQmlEngine* engine, QJSEngine*) {
        static DataStore instance;
        if (engine) {
            QQmlEngine::setObjectOwnership(&instance, QQmlEngine::CppOwnership);
        }
        return &instance;
    }
    
    // Page operations
    Q_INVOKABLE QVariantList getAllPages();
    Q_INVOKABLE QVariantList getPagesForSync();
    Q_INVOKABLE QVariantList getPagesForSyncSince(const QString& updatedAtCursor,
                                                  const QString& pageIdCursor);
    // Mark pages as "synced base" (used for conflict detection).
    // Accepts either a list of pageId strings or a list of {pageId: "..."} maps.
    Q_INVOKABLE void markPagesAsSynced(const QVariantList& pagesOrIds);

    // Sync conflict handling
    Q_INVOKABLE QVariantList getPageConflicts();
    Q_INVOKABLE QVariantMap getPageConflict(const QString& pageId);
    Q_INVOKABLE bool hasPageConflict(const QString& pageId);
    // Returns { mergedMarkdown: string, clean: bool, kind: string } or empty if not found.
    Q_INVOKABLE QVariantMap previewMergeForPageConflict(const QString& pageId);
    // resolution: "local" | "remote" | "merge"
    Q_INVOKABLE void resolvePageConflict(const QString& pageId, const QString& resolution);
    Q_INVOKABLE QVariantList getDeletedPagesForSync();
    Q_INVOKABLE QVariantList getDeletedPagesForSyncSince(const QString& deletedAtCursor,
                                                         const QString& pageIdCursor);
    Q_INVOKABLE QVariantMap getPage(const QString& pageId);
    Q_INVOKABLE void savePage(const QVariantMap& page);
    Q_INVOKABLE void deletePage(const QString& pageId);
    Q_INVOKABLE void saveAllPages(const QVariantList& pages);
    Q_INVOKABLE void applyPageUpdates(const QVariantList& pages);
    Q_INVOKABLE void applyDeletedPageUpdates(const QVariantList& deletedPages);
    Q_INVOKABLE QVariantList searchPages(const QString& query, int limit = 50);

    Q_INVOKABLE int deletedPagesRetentionLimit() const;
    Q_INVOKABLE void setDeletedPagesRetentionLimit(int limit);

    // UI startup behavior:
    // - mode=0: open last viewed page (default)
    // - mode=1: always open fixed page id (if available)
    Q_INVOKABLE int startupPageMode() const;
    Q_INVOKABLE void setStartupPageMode(int mode);
    Q_INVOKABLE QString startupFixedPageId() const;
    Q_INVOKABLE void setStartupFixedPageId(const QString& pageId);
    Q_INVOKABLE QString lastViewedPageId() const;
    Q_INVOKABLE void setLastViewedPageId(const QString& pageId);
    Q_INVOKABLE QString resolveStartupPageId(const QVariantList& pages) const;
    
    // Block operations  
    Q_INVOKABLE QVariantList getBlocksForPage(const QString& pageId);
    Q_INVOKABLE QVariantList getBlocksForSync();
    Q_INVOKABLE QVariantList getBlocksForSyncSince(const QString& updatedAtCursor,
                                                   const QString& blockIdCursor);
    Q_INVOKABLE void saveBlocksForPage(const QString& pageId, const QVariantList& blocks);
    Q_INVOKABLE void deleteBlocksForPage(const QString& pageId);
    Q_INVOKABLE void applyBlockUpdates(const QVariantList& blocks);

    // Plume-style storage: one markdown document per page.
    Q_INVOKABLE QString getPageContentMarkdown(const QString& pageId);
    Q_INVOKABLE void savePageContentMarkdown(const QString& pageId, const QString& markdown);

    // Attachments (images, etc)
    // Data URL format: data:<mime>;base64,<payload>
    // Returns attachmentId (UUID) or empty on error.
    Q_INVOKABLE QString saveAttachmentFromDataUrl(const QString& dataUrl);
    Q_INVOKABLE QVariantList getAttachmentsForSync();
    Q_INVOKABLE QVariantList getAttachmentsForSyncSince(const QString& updatedAtCursor,
                                                        const QString& attachmentIdCursor);
    Q_INVOKABLE QVariantList getAttachmentsByIds(const QVariantList& attachmentIds);
    Q_INVOKABLE void applyAttachmentUpdates(const QVariantList& attachments);

    // Paired device operations
    Q_INVOKABLE QVariantList getPairedDevices();
    Q_INVOKABLE void savePairedDevice(const QString& deviceId,
                                      const QString& deviceName,
                                      const QString& workspaceId);
    Q_INVOKABLE void updatePairedDeviceEndpoint(const QString& deviceId,
                                               const QString& host,
                                               int port);
    Q_INVOKABLE void removePairedDevice(const QString& deviceId);
    Q_INVOKABLE void clearPairedDevices();

    // Seed the initial "Getting Started" style pages using a sentinel old timestamp so
    // they never win sync conflicts against real user edits from other clients.
    Q_INVOKABLE bool seedDefaultPages();
    
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
    void pageContentChanged(const QString& pageId);
    void attachmentsChanged();
    void pairedDevicesChanged();
    void pageConflictsChanged();
    void pageConflictDetected(const QVariantMap& conflict);
    void error(const QString& message);

private:
    void createTables();
    QString getDatabasePath();
    
    QSqlDatabase m_db;
    bool m_ready = false;
};

} // namespace zinc::ui
