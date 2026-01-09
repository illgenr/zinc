#include "network/pairing.hpp"
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>

namespace zinc::network {

PairingSession::PairingSession(QObject* parent)
    : QObject(parent)
{
}

PairingSession::~PairingSession() {
    cancel();
}

void PairingSession::startAsInitiator(const crypto::KeyPair& identity,
                                      const Uuid& workspace_id,
                                      const QString& device_name,
                                      PairingMethod method) {
    identity_ = identity;
    workspace_id_ = workspace_id;
    device_name_ = device_name;
    method_ = method;
    
    // Generate ephemeral keys for this session
    ephemeral_keys_ = crypto::generate_keypair();
    
    // Generate verification code
    generateVerificationCode();
    
    // Generate QR code data if applicable
    if (method == PairingMethod::QRCode) {
        generateQRCodeData();
    }
    
    setState(PairingState::WaitingForPeer);
}

void PairingSession::startAsResponder(const crypto::KeyPair& identity,
                                      const QString& device_name) {
    identity_ = identity;
    device_name_ = device_name;
    
    // Generate ephemeral keys
    ephemeral_keys_ = crypto::generate_keypair();
    
    setState(PairingState::WaitingForPeer);
}

void PairingSession::submitCode(const QString& code) {
    if (state_ != PairingState::WaitingForPeer) {
        return;
    }
    
    verification_code_ = code;
    setState(PairingState::Verifying);
    
    // In a real implementation, this would:
    // 1. Connect to the initiator using info from QR/code
    // 2. Perform Noise handshake
    // 3. Verify codes match
    // 4. Exchange workspace keys
    
    // For now, simulate success
    setState(PairingState::Complete);
    emit pairingComplete(paired_device_);
}

void PairingSession::cancel() {
    if (state_ != PairingState::Idle && state_ != PairingState::Complete) {
        setState(PairingState::Idle);
    }
}

void PairingSession::setState(PairingState state) {
    if (state_ != state) {
        state_ = state;
        emit stateChanged(state);
    }
}

void PairingSession::generateVerificationCode() {
    if (method_ == PairingMethod::NumericCode || method_ == PairingMethod::QRCode) {
        verification_code_ = QString::fromStdString(crypto::generate_pairing_code());
    }
    emit verificationCodeChanged();
}

void PairingSession::generateQRCodeData() {
    // Get local IP address
    QHostAddress local_address;
    for (const auto& address : QNetworkInterface::allAddresses()) {
        if (address.protocol() == QAbstractSocket::IPv4Protocol &&
            !address.isLoopback()) {
            local_address = address;
            break;
        }
    }
    
    PairingInfo info{
        .device_id = Uuid::generate(),  // Would use actual device ID
        .device_name = device_name_,
        .public_key = ephemeral_keys_.public_key,
        .address = local_address,
        .port = 0,  // Would use actual port
        .verification_code = verification_code_,
        .method = method_
    };
    
    qr_code_data_ = generateQRCodeJson(info);
    emit qrCodeDataChanged();
}

QString generateQRCodeJson(const PairingInfo& info) {
    QJsonObject obj;
    obj["v"] = 1;
    obj["id"] = QString::fromStdString(info.device_id.to_string());
    obj["name"] = info.device_name;
    obj["pk"] = QString::fromStdString(crypto::to_base64(
        std::vector<uint8_t>(info.public_key.begin(), info.public_key.end())));
    obj["addr"] = info.address.toString();
    obj["port"] = info.port;
    obj["code"] = info.verification_code;
    
    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

Result<PairingInfo, Error> parseQRCodeJson(const QString& json) {
    QJsonParseError error;
    auto doc = QJsonDocument::fromJson(json.toUtf8(), &error);
    
    if (error.error != QJsonParseError::NoError) {
        return Result<PairingInfo, Error>::err(
            Error{"Invalid JSON: " + error.errorString().toStdString()});
    }
    
    auto obj = doc.object();
    
    if (obj["v"].toInt() != 1) {
        return Result<PairingInfo, Error>::err(Error{"Unsupported version"});
    }
    
    PairingInfo info;
    
    auto id = Uuid::parse(obj["id"].toString().toStdString());
    if (!id) {
        return Result<PairingInfo, Error>::err(Error{"Invalid device ID"});
    }
    info.device_id = *id;
    
    info.device_name = obj["name"].toString();
    
    auto pk_result = crypto::from_base64(obj["pk"].toString().toStdString());
    if (pk_result.is_err() || pk_result.unwrap().size() != crypto::PUBLIC_KEY_SIZE) {
        return Result<PairingInfo, Error>::err(Error{"Invalid public key"});
    }
    auto pk_bytes = pk_result.unwrap();
    std::copy(pk_bytes.begin(), pk_bytes.end(), info.public_key.begin());
    
    info.address = QHostAddress(obj["addr"].toString());
    info.port = static_cast<uint16_t>(obj["port"].toInt());
    info.verification_code = obj["code"].toString();
    
    return Result<PairingInfo, Error>::ok(info);
}

} // namespace zinc::network

