#include "ui/controllers/PairingController.hpp"
#include <algorithm>

namespace zinc::ui {

PairingController::PairingController(QObject* parent)
    : QObject(parent)
    , session_(std::make_unique<network::PairingSession>(this))
{
    connect(session_.get(), &network::PairingSession::stateChanged,
            this, [this]() {
                emit pairingChanged();
                emit statusChanged();
            });
    connect(session_.get(), &network::PairingSession::verificationCodeChanged,
            this, &PairingController::verificationCodeChanged);
    connect(session_.get(), &network::PairingSession::qrCodeDataChanged,
            this, &PairingController::qrCodeDataChanged);
    connect(session_.get(), &network::PairingSession::pairingComplete,
            this, [this](const network::PairingInfo& info) {
                updatePeerInfo(info);
                emit pairingComplete(info.device_name);
            });
    connect(session_.get(), &network::PairingSession::pairingFailed,
            this, &PairingController::pairingFailed);
}

bool PairingController::isPairing() const {
    auto state = session_->state();
    return state != network::PairingSession::PairingState::Idle &&
           state != network::PairingSession::PairingState::Complete &&
           state != network::PairingSession::PairingState::Failed;
}

QString PairingController::verificationCode() const {
    return session_->verificationCode();
}

QString PairingController::qrCodeData() const {
    return session_->qrCodeData();
}

QString PairingController::status() const {
    switch (session_->state()) {
        case network::PairingSession::PairingState::Idle:
            return "Ready";
        case network::PairingSession::PairingState::WaitingForPeer:
            return "Waiting for peer...";
        case network::PairingSession::PairingState::Connecting:
            return "Connecting...";
        case network::PairingSession::PairingState::Verifying:
            return "Verifying...";
        case network::PairingSession::PairingState::Exchanging:
            return "Exchanging keys...";
        case network::PairingSession::PairingState::Complete:
            return "Pairing complete!";
        case network::PairingSession::PairingState::Failed:
            return "Pairing failed";
    }
    return "";
}

QString PairingController::workspaceId() const {
    return workspace_id_;
}

QString PairingController::peerDeviceId() const {
    return QString::fromStdString(peer_info_.device_id.to_string());
}

QString PairingController::peerName() const {
    return peer_info_.device_name;
}

QString PairingController::peerHost() const {
    return peer_info_.address.toString();
}

int PairingController::peerPort() const {
    return static_cast<int>(peer_info_.port);
}

void PairingController::configureLocalDevice(const QString& deviceName,
                                             const QString& workspaceId,
                                             int listenPort) {
    device_name_ = deviceName.isEmpty() ? QStringLiteral("This Device") : deviceName;
    workspace_id_ = workspaceId;
    listen_port_ = listenPort;
    peer_info_ = {};
    emit peerInfoChanged();
    emit workspaceIdChanged();
}

void PairingController::startPairingAsInitiator(const QString& method) {
    network::PairingMethod pm = network::PairingMethod::QRCode;
    if (method == "numeric") {
        pm = network::PairingMethod::NumericCode;
    } else if (method == "passphrase") {
        pm = network::PairingMethod::Passphrase;
    }
#if !ZINC_ENABLE_QR
    if (pm == network::PairingMethod::QRCode) {
        emit pairingFailed("QR pairing disabled in this build");
        return;
    }
#endif
    
    auto keys = crypto::generate_keypair();
    Uuid workspace_id{};
    if (!workspace_id_.isEmpty()) {
        auto parsed = Uuid::parse(workspace_id_.toStdString());
        if (parsed) {
            workspace_id = *parsed;
        }
    }
    session_->setListenPort(static_cast<uint16_t>(std::max(0, listen_port_)));
    session_->startAsInitiator(keys, workspace_id, device_name_, pm);
    workspace_id_ = QString::fromStdString(session_->workspaceId().to_string());
    emit workspaceIdChanged();
}

void PairingController::startPairingAsResponder() {
    auto keys = crypto::generate_keypair();
    session_->startAsResponder(keys, device_name_);
}

void PairingController::submitCode(const QString& code) {
    session_->submitCode(code);
    workspace_id_ = QString::fromStdString(session_->workspaceId().to_string());
    emit workspaceIdChanged();
}

void PairingController::submitQrCodeData(const QString& qrData) {
#if !ZINC_ENABLE_QR
    Q_UNUSED(qrData)
    emit pairingFailed("QR pairing disabled in this build");
    return;
#endif
    session_->submitQrCodeData(qrData);
    if (session_->state() == network::PairingSession::PairingState::Failed) {
        return;
    }
    updatePeerInfo(session_->pairedDevice());
    workspace_id_ = QString::fromStdString(
        session_->pairedDevice().workspace_id.to_string());
    emit workspaceIdChanged();
}

void PairingController::cancel() {
    session_->cancel();
}

void PairingController::updatePeerInfo(const network::PairingInfo& info) {
    peer_info_ = info;
    emit peerInfoChanged();
}

} // namespace zinc::ui
