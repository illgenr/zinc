#include "ui/controllers/SyncController.hpp"
#include "core/types.hpp"
#include "crypto/keys.hpp"
#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QHostAddress>
#include <QSettings>

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
    connect(sync_manager_.get(), &network::SyncManager::peerDiscovered,
            this, [this](const network::PeerInfo& peer) {
                emit peerDiscovered(
                    QString::fromStdString(peer.device_id.to_string()),
                    peer.device_name,
                    QString::fromStdString(peer.workspace_id.to_string()),
                    peer.host.toString(),
                    static_cast<int>(peer.port));
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
                emit pageSnapshotReceivedPages(pagesValue.toArray().toVariantList());

                auto blocksValue = obj.value("blocks");
                if (blocksValue.isArray()) {
                    emit blockSnapshotReceivedBlocks(blocksValue.toArray().toVariantList());
                }
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
    emit configuredChanged();
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

} // namespace zinc::ui
