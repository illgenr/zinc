#pragma once

#include "network/sync_manager.hpp"
#include <QObject>
#include <QQmlEngine>

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
    
public:
    explicit SyncController(QObject* parent = nullptr);
    
    [[nodiscard]] bool isSyncing() const;
    [[nodiscard]] int peerCount() const;
    [[nodiscard]] QStringList peers() const;
    
    Q_INVOKABLE bool startSync();
    Q_INVOKABLE void stopSync();

signals:
    void syncingChanged();
    void peerCountChanged();
    void peersChanged();
    void peerConnected(const QString& deviceName);
    void peerDisconnected(const QString& deviceName);
    void error(const QString& message);

private:
    std::unique_ptr<network::SyncManager> sync_manager_;
};

} // namespace zinc::ui

