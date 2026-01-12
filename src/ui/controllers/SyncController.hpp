#pragma once

#include "network/sync_manager.hpp"
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

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
    
public:
    explicit SyncController(QObject* parent = nullptr);
    
    [[nodiscard]] bool isSyncing() const;
    [[nodiscard]] int peerCount() const;
    [[nodiscard]] QStringList peers() const;
    [[nodiscard]] bool isConfigured() const;
    [[nodiscard]] QString workspaceId() const;
    
    Q_INVOKABLE bool configure(const QString& workspaceId, const QString& deviceName);
    Q_INVOKABLE bool tryAutoStart(const QString& defaultDeviceName);
    Q_INVOKABLE bool startSync();
    Q_INVOKABLE void stopSync();
    Q_INVOKABLE void connectToPeer(const QString& deviceId,
                                   const QString& host,
                                   int port);
    Q_INVOKABLE int listeningPort() const;
    Q_INVOKABLE void sendPageSnapshot(const QString& jsonPayload);

signals:
    void syncingChanged();
    void peerCountChanged();
    void peersChanged();
    void configuredChanged();
    void peerDiscovered(const QString& deviceId,
                        const QString& deviceName,
                        const QString& workspaceId,
                        const QString& host,
                        int port);
    void peerConnected(const QString& deviceName);
    void peerDisconnected(const QString& deviceName);
    void pageSnapshotReceived(const QString& jsonPayload);
    void pageSnapshotReceivedPages(const QVariantList& pages);
    void blockSnapshotReceivedBlocks(const QVariantList& blocks);
    void error(const QString& message);

private:
    std::unique_ptr<network::SyncManager> sync_manager_;
    bool configured_ = false;
    QString workspace_id_;
};

} // namespace zinc::ui
