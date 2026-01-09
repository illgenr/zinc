#include "ui/controllers/SyncController.hpp"

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

bool SyncController::startSync() {
    return sync_manager_->start();
}

void SyncController::stopSync() {
    sync_manager_->stop();
}

} // namespace zinc::ui

