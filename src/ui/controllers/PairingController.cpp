#include "ui/controllers/PairingController.hpp"

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

void PairingController::startPairingAsInitiator(const QString& method) {
    network::PairingMethod pm = network::PairingMethod::QRCode;
    if (method == "numeric") {
        pm = network::PairingMethod::NumericCode;
    } else if (method == "passphrase") {
        pm = network::PairingMethod::Passphrase;
    }
    
    auto keys = crypto::generate_keypair();
    session_->startAsInitiator(keys, Uuid::generate(), "This Device", pm);
}

void PairingController::startPairingAsResponder() {
    auto keys = crypto::generate_keypair();
    session_->startAsResponder(keys, "This Device");
}

void PairingController::submitCode(const QString& code) {
    session_->submitCode(code);
}

void PairingController::cancel() {
    session_->cancel();
}

} // namespace zinc::ui

