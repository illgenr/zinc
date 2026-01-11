#include "ui/controllers/SyncController.hpp"
#include "core/types.hpp"
#include "crypto/keys.hpp"
#include <QHostAddress>

namespace zinc::ui {

SyncController::SyncController(QObject* parent)
    : QObject(parent)
    , sync_manager_(std::make_unique<network::SyncManager>(this))
{
    connect(sync_manager_.get(), &network::SyncManager::syncingChanged,
            this, &SyncController::syncingChanged);
    connect(sync_manager_.get(), &network::SyncManager::peersChanged,
            this, [this]() {
                emit peerCountChanged();
                emit peersChanged();
            });
    connect(sync_manager_.get(), &network::SyncManager::error,
            this, &SyncController::error);
}

bool SyncController::isSyncing() const {
    return sync_manager_->isSyncing();
}

int SyncController::peerCount() const {
    return sync_manager_->connectedPeerCount();
}

QStringList SyncController::peers() const {
    QStringList result;
    // Would enumerate connected peers
    return result;
}

bool SyncController::isConfigured() const {
    return configured_;
}

QString SyncController::workspaceId() const {
    return workspace_id_;
}

bool SyncController::configure(const QString& workspaceId, const QString& deviceName) {
    auto parsed = Uuid::parse(workspaceId.toStdString());
    if (!parsed) {
        emit error("Invalid workspace ID");
        return false;
    }
    
    QString resolved_name = deviceName.isEmpty()
        ? QStringLiteral("This Device")
        : deviceName;
    auto keys = crypto::generate_keypair();
    sync_manager_->initialize(keys, *parsed, resolved_name);
    configured_ = true;
    workspace_id_ = workspaceId;
    emit configuredChanged();
    return true;
}

bool SyncController::startSync() {
    if (!configured_) {
        emit error("Sync not configured");
        return false;
    }
    return sync_manager_->start();
}

void SyncController::stopSync() {
    sync_manager_->stop();
}

void SyncController::connectToPeer(const QString& deviceId,
                                   const QString& host,
                                   int port) {
    auto parsed = Uuid::parse(deviceId.toStdString());
    if (!parsed) {
        emit error("Invalid peer ID");
        return;
    }
    if (port <= 0 || port > 65535) {
        emit error("Invalid peer port");
        return;
    }
    QHostAddress address(host);
    if (address.isNull()) {
        emit error("Invalid peer address");
        return;
    }
    sync_manager_->connectToEndpoint(*parsed, address,
                                     static_cast<uint16_t>(port));
}

int SyncController::listeningPort() const {
    return static_cast<int>(sync_manager_->listeningPort());
}

} // namespace zinc::ui
