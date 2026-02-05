#pragma once

#include "network/sync_manager.hpp"
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <optional>

#include "ui/controllers/sync_presence.hpp"

namespace zinc::ui {

/**
 * SyncController - Controller for sync functionality.
 */
class SyncController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(bool syncing READ isSyncing NOTIFY syncingChanged)
    Q_PROPERTY(int peerCount READ peerCount NOTIFY peerCountChanged)
    Q_PROPERTY(QStringList peers READ peers NOTIFY peersChanged)
    Q_PROPERTY(bool configured READ isConfigured NOTIFY configuredChanged)
    Q_PROPERTY(QString workspaceId READ workspaceId NOTIFY configuredChanged)
    Q_PROPERTY(QVariantList discoveredPeers READ discoveredPeers NOTIFY discoveredPeersChanged)
    Q_PROPERTY(bool remoteAutoSyncEnabled READ remoteAutoSyncEnabled NOTIFY remotePresenceChanged)
    Q_PROPERTY(QString remoteCursorPageId READ remoteCursorPageId NOTIFY remotePresenceChanged)
    Q_PROPERTY(int remoteCursorBlockIndex READ remoteCursorBlockIndex NOTIFY remotePresenceChanged)
    Q_PROPERTY(int remoteCursorPos READ remoteCursorPos NOTIFY remotePresenceChanged)
    
public:
    explicit SyncController(QObject* parent = nullptr);
    
    [[nodiscard]] bool isSyncing() const;
    [[nodiscard]] int peerCount() const;
    [[nodiscard]] QStringList peers() const;
    [[nodiscard]] bool isConfigured() const;
    [[nodiscard]] QString workspaceId() const;
    [[nodiscard]] QVariantList discoveredPeers() const;
    [[nodiscard]] bool remoteAutoSyncEnabled() const;
    [[nodiscard]] QString remoteCursorPageId() const;
    [[nodiscard]] int remoteCursorBlockIndex() const;
    [[nodiscard]] int remoteCursorPos() const;
    
    Q_INVOKABLE bool configure(const QString& workspaceId, const QString& deviceName);
    Q_INVOKABLE bool tryAutoStart(const QString& defaultDeviceName);
    Q_INVOKABLE bool startSync();
    Q_INVOKABLE bool startPairingListener(const QString& defaultDeviceName);
    Q_INVOKABLE void stopSync();
    Q_INVOKABLE void connectToPeer(const QString& deviceId,
                                   const QString& host,
                                   int port);
    Q_INVOKABLE void connectToHost(const QString& host);
    Q_INVOKABLE void connectToHostWithPort(const QString& host, int port);
    Q_INVOKABLE void pairToHostWithPort(const QString& host, int port);
    Q_INVOKABLE void sendPairingResponse(const QString& deviceId,
                                         bool accepted,
                                         const QString& reason,
                                         const QString& workspaceId);
    Q_INVOKABLE void approvePeer(const QString& deviceId, bool approved);
    Q_INVOKABLE int listeningPort() const;
    Q_INVOKABLE void sendPageSnapshot(const QString& jsonPayload);
    Q_INVOKABLE void sendPresence(const QString& pageId, int blockIndex, int cursorPos, bool autoSyncEnabled);

signals:
    void syncingChanged();
    void peerCountChanged();
    void peersChanged();
    void configuredChanged();
    void discoveredPeersChanged();
    void peerDiscovered(const QString& deviceId,
                        const QString& deviceName,
                        const QString& workspaceId,
                        const QString& host,
                        int port);
    void peerConnected(const QString& deviceName);
    void peerDisconnected(const QString& deviceName);
    void peerHelloReceived(const QString& deviceId,
                           const QString& deviceName,
                           const QString& host,
                           int port);
    void pairingRequestReceived(const QString& deviceId,
                                const QString& deviceName,
                                const QString& host,
                                int port,
                                const QString& workspaceId);
    void pairingResponseReceived(const QString& deviceId,
                                 bool accepted,
                                 const QString& reason,
                                 const QString& workspaceId);
    void peerApprovalRequired(const QString& deviceId,
                              const QString& deviceName,
                              const QString& host,
                              int port);
    void pageSnapshotReceived(const QString& jsonPayload);
    void pageSnapshotReceivedPages(const QVariantList& pages);
    void blockSnapshotReceivedBlocks(const QVariantList& blocks);
    void deletedPageSnapshotReceivedPages(const QVariantList& deletedPages);
    void attachmentSnapshotReceivedAttachments(const QVariantList& attachments);
    void notebookSnapshotReceivedNotebooks(const QVariantList& notebooks);
    void deletedNotebookSnapshotReceivedNotebooks(const QVariantList& deletedNotebooks);
    void remotePresenceChanged();
    void error(const QString& message);

private:
    std::unique_ptr<network::SyncManager> sync_manager_;
    bool configured_ = false;
    QString workspace_id_;
    QVariantList discovered_peers_;
    std::optional<SyncPresence> remote_presence_;

    struct PendingPairToHost {
        QString host;
        int port = 0;
        qint64 started_ms = 0;
    };
    std::optional<PendingPairToHost> pending_pair_to_host_;
};

} // namespace zinc::ui
