#include "network/pairing.hpp"
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInterface>

namespace zinc::network {
namespace {

Uuid deriveWorkspaceIdFromSecret(const QString& secret) {
    const auto bytes = secret.toUtf8();
    const auto hashed = crypto::hash(
        std::vector<uint8_t>(bytes.begin(), bytes.end()),
        static_cast<size_t>(Uuid::BYTE_SIZE));

    Uuid::Bytes uuid_bytes{};
    for (size_t i = 0; i < uuid_bytes.size() && i < hashed.size(); ++i) {
        uuid_bytes[i] = hashed[i];
    }

    // Mark as RFC 4122 variant and "v5-like" version.
    uuid_bytes[6] = (uuid_bytes[6] & 0x0F) | 0x50;
    uuid_bytes[8] = (uuid_bytes[8] & 0x3F) | 0x80;

    return Uuid(uuid_bytes);
}

} // namespace

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
#if !ZINC_ENABLE_QR
    if (method == PairingMethod::QRCode) {
        setState(PairingState::Failed);
        emit pairingFailed("QR pairing disabled in this build");
        return;
    }
#endif
    identity_ = identity;
    workspace_id_ = workspace_id;
    device_name_ = device_name;
    method_ = method;
    
    // Generate ephemeral keys for this session
    ephemeral_keys_ = crypto::generate_keypair();
    
    // Generate verification code
    generateVerificationCode();

    // For code/passphrase pairing, derive a deterministic workspace id from the secret.
    // This lets mobile/desktop clients join the same workspace without needing a
    // separate pairing transport.
    if (method_ == PairingMethod::NumericCode) {
        workspace_id_ = deriveWorkspaceIdFromSecret(QStringLiteral("code:") + verification_code_);
    } else {
        workspace_id_ = workspace_id;
    }
    
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
    method_ = PairingMethod::NumericCode;
    
    // Generate ephemeral keys
    ephemeral_keys_ = crypto::generate_keypair();
    
    setState(PairingState::WaitingForPeer);
}

void PairingSession::setListenPort(uint16_t port) {
    listen_port_ = port;
}

void PairingSession::submitCode(const QString& code) {
    if (state_ != PairingState::WaitingForPeer) {
        return;
    }

    verification_code_ = code;
    emit verificationCodeChanged();

    if (method_ == PairingMethod::NumericCode) {
        workspace_id_ = deriveWorkspaceIdFromSecret(QStringLiteral("code:") + verification_code_);
    } else if (method_ == PairingMethod::Passphrase) {
        workspace_id_ = deriveWorkspaceIdFromSecret(QStringLiteral("pass:") + verification_code_);
    }

    // Numeric/passphrase pairing is "workspace join" only; the actual peer device
    // is discovered/connected via the sync layer afterwards.
    setState(PairingState::WaitingForPeer);
}

void PairingSession::submitQrCodeData(const QString& qrData) {
#if !ZINC_ENABLE_QR
    Q_UNUSED(qrData)
    setState(PairingState::Failed);
    emit pairingFailed("QR pairing disabled in this build");
    return;
#endif
    if (state_ != PairingState::WaitingForPeer) {
        return;
    }
    
    auto parsed = parseQRCodeJson(qrData);
    if (parsed.is_err()) {
        setState(PairingState::Failed);
        emit pairingFailed(QString::fromStdString(parsed.unwrap_err().message));
        return;
    }
    
    paired_device_ = parsed.unwrap();
    verification_code_ = paired_device_.verification_code;
    workspace_id_ = paired_device_.workspace_id;
    method_ = PairingMethod::QRCode;
    emit verificationCodeChanged();
    
    setState(PairingState::Verifying);
    
    // Simulate success for now.
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
#if !ZINC_ENABLE_QR
    qr_code_data_.clear();
    emit qrCodeDataChanged();
    return;
#endif
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
        .workspace_id = workspace_id_,
        .device_name = device_name_,
        .public_key = ephemeral_keys_.public_key,
        .address = local_address,
        .port = listen_port_,
        .verification_code = verification_code_,
        .method = method_
    };
    
    qr_code_data_ = generateQRCodeJson(info);
    emit qrCodeDataChanged();
}

QString generateQRCodeJson(const PairingInfo& info) {
#if !ZINC_ENABLE_QR
    Q_UNUSED(info)
    return {};
#endif
    QJsonObject obj;
    obj["v"] = 1;
    obj["id"] = QString::fromStdString(info.device_id.to_string());
    obj["ws"] = QString::fromStdString(info.workspace_id.to_string());
    obj["name"] = info.device_name;
    obj["pk"] = QString::fromStdString(crypto::to_base64(
        std::vector<uint8_t>(info.public_key.begin(), info.public_key.end())));
    obj["addr"] = info.address.toString();
    obj["port"] = info.port;
    obj["code"] = info.verification_code;
    
    return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

Result<PairingInfo, Error> parseQRCodeJson(const QString& json) {
#if !ZINC_ENABLE_QR
    Q_UNUSED(json)
    return Result<PairingInfo, Error>::err(Error{"QR pairing disabled in this build"});
#endif
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
    
    auto ws = obj["ws"].toString();
    if (!ws.isEmpty()) {
        auto ws_id = Uuid::parse(ws.toStdString());
        if (!ws_id) {
            return Result<PairingInfo, Error>::err(Error{"Invalid workspace ID"});
        }
        info.workspace_id = *ws_id;
    }
    
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
    info.method = PairingMethod::QRCode;
    
    return Result<PairingInfo, Error>::ok(info);
}

} // namespace zinc::network
