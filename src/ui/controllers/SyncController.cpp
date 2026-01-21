#include "ui/controllers/SyncController.hpp"
#include "core/types.hpp"
#include "crypto/keys.hpp"
#include "ui/controllers/sync_presence.hpp"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QHostAddress>
#include <QSettings>
#include <QDateTime>

namespace zinc::ui {

namespace {

constexpr const char* kSettingsDeviceId = "sync/device_id";
constexpr const char* kSettingsWorkspaceId = "sync/workspace_id";
constexpr const char* kSettingsDeviceName = "sync/device_name";

} // namespace

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
    connect(sync_manager_.get(), &network::SyncManager::peerConnected,
            this, [this](const Uuid& device_id) {
                emit peerConnected(QString::fromStdString(device_id.to_string()));
                emit peerCountChanged();
                emit peersChanged();
            });
    connect(sync_manager_.get(), &network::SyncManager::peerDisconnected,
            this, [this](const Uuid& device_id) {
                emit peerDisconnected(QString::fromStdString(device_id.to_string()));
                emit peerCountChanged();
                emit peersChanged();
                if (remote_presence_.has_value()) {
                    remote_presence_.reset();
                    emit remotePresenceChanged();
                }
            });
    connect(sync_manager_.get(), &network::SyncManager::peerDiscovered,
            this, [this](const network::PeerInfo& peer) {
                emit peerDiscovered(
                    QString::fromStdString(peer.device_id.to_string()),
                    peer.device_name,
                    QString::fromStdString(peer.workspace_id.to_string()),
                    peer.host.toString(),
                    static_cast<int>(peer.port));

                QVariantMap device;
                device["deviceId"] = QString::fromStdString(peer.device_id.to_string());
                device["deviceName"] = peer.device_name;
                device["workspaceId"] = QString::fromStdString(peer.workspace_id.to_string());
                device["host"] = peer.host.toString();
                device["port"] = static_cast<int>(peer.port);
                device["lastSeen"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

                const auto deviceId = device.value("deviceId").toString();
                bool updated = false;
                for (auto i = 0; i < discovered_peers_.size(); ++i) {
                    const auto existing = discovered_peers_[i].toMap();
                    if (existing.value("deviceId").toString() == deviceId) {
                        discovered_peers_[i] = device;
                        updated = true;
                        break;
                    }
                }
                if (!updated) {
                    discovered_peers_.append(device);
                }
                emit discoveredPeersChanged();
            });
    connect(sync_manager_.get(), &network::SyncManager::pageSnapshotReceived,
            this, [this](const QByteArray& payload) {
                auto hash = QCryptographicHash::hash(payload, QCryptographicHash::Sha256).toHex();
                qInfo() << "SYNC: received PagesSnapshot bytes=" << payload.size()
                         << "hash=" << hash;
                auto doc = QJsonDocument::fromJson(payload);
                if (doc.isNull() || !doc.isObject()) {
                    qWarning() << "SYNC: invalid PagesSnapshot JSON";
                    emit pageSnapshotReceived(QString::fromUtf8(payload));
                    return;
                }
                auto obj = doc.object();
                auto pagesValue = obj.value("pages");
                if (!pagesValue.isArray()) {
                    qWarning() << "SYNC: PagesSnapshot missing pages array";
                    return;
                }
                auto attachmentsValue = obj.value("attachments");
                if (attachmentsValue.isArray()) {
                    emit attachmentSnapshotReceivedAttachments(attachmentsValue.toArray().toVariantList());
                }

                emit pageSnapshotReceivedPages(pagesValue.toArray().toVariantList());

                auto blocksValue = obj.value("blocks");
                if (blocksValue.isArray()) {
                    emit blockSnapshotReceivedBlocks(blocksValue.toArray().toVariantList());
                }

                auto deletedPagesValue = obj.value("deletedPages");
                if (deletedPagesValue.isArray()) {
                    emit deletedPageSnapshotReceivedPages(deletedPagesValue.toArray().toVariantList());
                }

                auto notebooksValue = obj.value("notebooks");
                if (notebooksValue.isArray()) {
                    emit notebookSnapshotReceivedNotebooks(notebooksValue.toArray().toVariantList());
                }

                auto deletedNotebooksValue = obj.value("deletedNotebooks");
                if (deletedNotebooksValue.isArray()) {
                    emit deletedNotebookSnapshotReceivedNotebooks(deletedNotebooksValue.toArray().toVariantList());
                }
            });
    connect(sync_manager_.get(), &network::SyncManager::presenceReceived,
            this, [this](const Uuid& peer_id, const QByteArray& payload) {
                Q_UNUSED(peer_id);
                const auto parsed = parseSyncPresence(payload);
                if (!parsed) {
                    return;
                }
                if (qEnvironmentVariableIsSet("ZINC_DEBUG_SYNC")) {
                    qInfo() << "SYNC: presenceReceived autoSyncEnabled=" << parsed->auto_sync_enabled
                            << "pageId=" << parsed->page_id
                            << "blockIndex=" << parsed->block_index
                            << "cursorPos=" << parsed->cursor_pos;
                }
                const auto changed =
                    (!remote_presence_.has_value()) ||
                    (remote_presence_->auto_sync_enabled != parsed->auto_sync_enabled) ||
                    (remote_presence_->page_id != parsed->page_id) ||
                    (remote_presence_->block_index != parsed->block_index) ||
                    (remote_presence_->cursor_pos != parsed->cursor_pos);
                if (!changed) {
                    return;
                }
                remote_presence_ = *parsed;
                emit remotePresenceChanged();
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

QVariantList SyncController::discoveredPeers() const {
    return discovered_peers_;
}

bool SyncController::remoteAutoSyncEnabled() const {
    return remote_presence_.has_value() ? remote_presence_->auto_sync_enabled : false;
}

QString SyncController::remoteCursorPageId() const {
    return remote_presence_.has_value() ? remote_presence_->page_id : QString{};
}

int SyncController::remoteCursorBlockIndex() const {
    return remote_presence_.has_value() ? remote_presence_->block_index : -1;
}

int SyncController::remoteCursorPos() const {
    return remote_presence_.has_value() ? remote_presence_->cursor_pos : -1;
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
    QSettings settings;
    const QString device_id_key = QString::fromLatin1(kSettingsDeviceId);
    QString stored_id = settings.value(device_id_key).toString();
    Uuid device_id{};
    if (!stored_id.isEmpty()) {
        auto parsed_id = Uuid::parse(stored_id.toStdString());
        if (parsed_id) {
            device_id = *parsed_id;
        }
    }
    if (device_id.is_nil()) {
        device_id = Uuid::generate();
        settings.setValue(device_id_key, QString::fromStdString(device_id.to_string()));
    }
    settings.setValue(QString::fromLatin1(kSettingsWorkspaceId), workspaceId);
    settings.setValue(QString::fromLatin1(kSettingsDeviceName), resolved_name);
    sync_manager_->initialize(keys, *parsed, resolved_name, device_id);
    configured_ = true;
    workspace_id_ = workspaceId;
    discovered_peers_.clear();
    emit discoveredPeersChanged();
    emit configuredChanged();
    remote_presence_.reset();
    emit remotePresenceChanged();
    return true;
}

bool SyncController::tryAutoStart(const QString& defaultDeviceName) {
    QSettings settings;
    const auto workspaceId = settings.value(QString::fromLatin1(kSettingsWorkspaceId)).toString();
    if (workspaceId.isEmpty()) {
        return false;
    }
    const auto deviceName = settings.value(QString::fromLatin1(kSettingsDeviceName), defaultDeviceName).toString();
    if (!configure(workspaceId, deviceName)) {
        return false;
    }
    return startSync();
}

bool SyncController::startSync() {
    if (!configured_) {
        emit error("Sync not configured");
        return false;
    }
    static constexpr uint16_t preferred_port = 47888;
    return sync_manager_->start(preferred_port);
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

    QSettings settings;
    const auto stored = settings.value(QString::fromLatin1(kSettingsDeviceId)).toString();
    if (!stored.isEmpty()) {
        auto parsedLocal = Uuid::parse(stored.toStdString());
        if (parsedLocal && *parsedLocal == *parsed) {
            return;
        }
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

void SyncController::sendPageSnapshot(const QString& jsonPayload) {
    if (jsonPayload.isEmpty()) {
        return;
    }
    auto bytes = jsonPayload.toUtf8();
    auto hash = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex();
    qInfo() << "SYNC: sendPageSnapshot bytes=" << bytes.size()
             << "hash=" << hash;
    std::vector<uint8_t> payload(bytes.begin(), bytes.end());
    sync_manager_->sendPageSnapshot(payload);
}

void SyncController::sendPresence(const QString& pageId, int blockIndex, int cursorPos, bool autoSyncEnabled) {
    SyncPresence presence;
    presence.auto_sync_enabled = autoSyncEnabled;
    presence.page_id = pageId;
    presence.block_index = blockIndex;
    presence.cursor_pos = cursorPos;
    const auto bytes = serializeSyncPresence(presence);
    if (qEnvironmentVariableIsSet("ZINC_DEBUG_SYNC")) {
        qInfo() << "SYNC: sendPresence pageId=" << pageId
                << "blockIndex=" << blockIndex
                << "cursorPos=" << cursorPos
                << "autoSyncEnabled=" << autoSyncEnabled;
    }
    const std::vector<uint8_t> payload(bytes.begin(), bytes.end());
    sync_manager_->sendPresenceUpdate(payload);
}

} // namespace zinc::ui
