#include "ui/controllers/SyncController.hpp"
#include "core/types.hpp"
#include "crypto/keys.hpp"
#include "ui/controllers/sync_presence.hpp"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QDateTime>

namespace zinc::ui {

namespace {

constexpr const char* kSettingsDeviceId = "sync/device_id";
constexpr const char* kSettingsWorkspaceId = "sync/workspace_id";
constexpr const char* kSettingsDeviceName = "sync/device_name";

Uuid get_or_create_device_id(QSettings& settings) {
    const QString device_id_key = QString::fromLatin1(kSettingsDeviceId);
    QString stored_id = settings.value(device_id_key).toString();
    if (!stored_id.isEmpty()) {
        auto parsed_id = Uuid::parse(stored_id.toStdString());
        if (parsed_id) {
            return *parsed_id;
        }
    }
    auto id = Uuid::generate();
    settings.setValue(device_id_key, QString::fromStdString(id.to_string()));
    return id;
}

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
    connect(sync_manager_.get(), &network::SyncManager::peerHelloReceived,
            this, [this](const Uuid& device_id,
                         const QString& device_name,
                         const QString& host,
                         uint16_t port) {
                // If we're in the middle of a "pair to host" attempt and the remote isn't yet in our workspace,
                // send an explicit pairing request.
                if (pending_pair_to_host_.has_value() && !workspace_id_.isEmpty()) {
                    const auto ageMs = QDateTime::currentDateTimeUtc().toMSecsSinceEpoch() - pending_pair_to_host_->started_ms;
                    if (ageMs >= 0 && ageMs < 30000) {
                        const auto wsParsed = Uuid::parse(workspace_id_.toStdString());
                        if (wsParsed) {
                            qInfo() << "SYNC: pairToHost hello received; sending PairingRequest"
                                    << "peer=" << QString::fromStdString(device_id.to_string())
                                    << "ws=" << workspace_id_;
                            sync_manager_->sendPairingRequest(device_id, *wsParsed);
                        }
                    }
                    pending_pair_to_host_.reset();
                }
                emit peerHelloReceived(
                    QString::fromStdString(device_id.to_string()),
                    device_name,
                    host,
                    static_cast<int>(port));
            });
    connect(sync_manager_.get(), &network::SyncManager::peerApprovalRequired,
            this, [this](const Uuid& device_id,
                         const QString& device_name,
                         const QString& host,
                         uint16_t port) {
                emit peerApprovalRequired(
                    QString::fromStdString(device_id.to_string()),
                    device_name,
                    host,
                    static_cast<int>(port));
            });
    connect(sync_manager_.get(), &network::SyncManager::pairingRequestReceived,
            this, [this](const Uuid& device_id,
                         const QString& device_name,
                         const QString& host,
                         uint16_t port,
                         const Uuid& workspace_id) {
                emit pairingRequestReceived(
                    QString::fromStdString(device_id.to_string()),
                    device_name,
                    host,
                    static_cast<int>(port),
                    QString::fromStdString(workspace_id.to_string()));
            });
    connect(sync_manager_.get(), &network::SyncManager::pairingResponseReceived,
            this, [this](const Uuid& device_id,
                         bool accepted,
                         const QString& reason,
                         const Uuid& workspace_id) {
                emit pairingResponseReceived(
                    QString::fromStdString(device_id.to_string()),
                    accepted,
                    reason,
                    QString::fromStdString(workspace_id.to_string()));
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
    const auto device_id = get_or_create_device_id(settings);
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

bool SyncController::startPairingListener(const QString& defaultDeviceName) {
    if (sync_manager_->isSyncing()) {
        return true;
    }
    const auto name = defaultDeviceName.isEmpty()
        ? QStringLiteral("This Device")
        : defaultDeviceName;
    auto keys = crypto::generate_keypair();
    QSettings settings;
    const auto device_id = get_or_create_device_id(settings);
    // Unconfigured listener uses nil workspace id and does not advertise/browse.
    sync_manager_->initialize(keys, Uuid{}, name, device_id);
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
    const auto trimmedHost = host.trimmed();
    if (trimmedHost.isEmpty()) {
        emit error("Invalid peer host");
        return;
    }
    qInfo() << "SYNC: connectToPeer deviceId=" << deviceId << "host=" << trimmedHost << "port=" << port;
    sync_manager_->connectToEndpoint(*parsed, trimmedHost,
                                     static_cast<uint16_t>(port));
}

void SyncController::connectToHost(const QString& host) {
    connectToHostWithPort(host, 47888);
}

void SyncController::connectToHostWithPort(const QString& host, int port) {
    if (port <= 0 || port > 65535) {
        emit error("Invalid peer port");
        return;
    }
    const auto trimmedHost = host.trimmed();
    if (trimmedHost.isEmpty()) {
        emit error("Invalid peer host");
        return;
    }
    qInfo() << "SYNC: connectToHost host=" << trimmedHost << "port=" << port;
    sync_manager_->connectToEndpoint(Uuid::generate(), trimmedHost,
                                     static_cast<uint16_t>(port));
}

void SyncController::pairToHostWithPort(const QString& host, int port) {
    if (!configured_ || workspace_id_.isEmpty()) {
        emit error("Sync not configured. Pairing requires an existing workspace.");
        return;
    }
    if (!sync_manager_->isSyncing()) {
        emit error("Sync is not running");
        return;
    }
    if (port <= 0 || port > 65535) {
        emit error("Invalid peer port");
        return;
    }
    const auto trimmedHost = host.trimmed();
    if (trimmedHost.isEmpty()) {
        emit error("Invalid peer host");
        return;
    }
    pending_pair_to_host_ = PendingPairToHost{
        .host = trimmedHost,
        .port = port,
        .started_ms = QDateTime::currentDateTimeUtc().toMSecsSinceEpoch(),
    };
    qInfo() << "SYNC: pairToHost connect host=" << trimmedHost << "port=" << port;
    sync_manager_->connectToEndpoint(Uuid::generate(), trimmedHost, static_cast<uint16_t>(port));
}

void SyncController::sendPairingResponse(const QString& deviceId,
                                        bool accepted,
                                        const QString& reason,
                                        const QString& workspaceId) {
    auto parsedPeer = Uuid::parse(deviceId.toStdString());
    auto parsedWs = Uuid::parse(workspaceId.toStdString());
    if (!parsedPeer || !parsedWs) {
        emit error("Invalid pairing response parameters");
        return;
    }
    sync_manager_->sendPairingResponse(*parsedPeer, accepted, reason, *parsedWs);
}

void SyncController::approvePeer(const QString& deviceId, bool approved) {
    auto parsed = Uuid::parse(deviceId.toStdString());
    if (!parsed) {
        emit error("Invalid peer ID");
        return;
    }
    sync_manager_->approvePeer(*parsed, approved);
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
