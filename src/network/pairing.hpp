#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include "crypto/keys.hpp"
#include <QObject>
#include <QString>
#include <QHostAddress>
#include <memory>

namespace zinc::network {

/**
 * PairingMethod - Supported pairing methods.
 */
enum class PairingMethod {
    QRCode,      // Scan QR code
    NumericCode, // Enter 6-digit code
    Passphrase   // Enter passphrase
};

/**
 * PairingInfo - Information exchanged during pairing.
 */
struct PairingInfo {
    Uuid device_id;
    Uuid workspace_id;
    QString device_name;
    crypto::PublicKey public_key;
    QHostAddress address;
    uint16_t port;
    QString verification_code;  // 6-digit code or passphrase
    PairingMethod method;
};

/**
 * PairingSession - Manages a device pairing session.
 * 
 * Supports three pairing methods:
 * 1. QR Code: Display/scan QR containing device info + verification code
 * 2. Numeric Code: Display 6-digit code for manual entry
 * 3. Passphrase: User enters a shared passphrase
 */
class PairingSession : public QObject {
    Q_OBJECT
    
    Q_PROPERTY(PairingState state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString verificationCode READ verificationCode NOTIFY verificationCodeChanged)
    Q_PROPERTY(QString qrCodeData READ qrCodeData NOTIFY qrCodeDataChanged)
    
public:
    enum class PairingState {
        Idle,
        WaitingForPeer,    // Displaying code, waiting for peer to connect
        Connecting,         // Connecting to peer
        Verifying,          // Verifying codes match
        Exchanging,         // Exchanging workspace keys
        Complete,
        Failed
    };
    Q_ENUM(PairingState)
    
    explicit PairingSession(QObject* parent = nullptr);
    ~PairingSession() override;
    
    /**
     * Start pairing as initiator (display code for other device to scan/enter).
     */
    Q_INVOKABLE void startAsInitiator(const crypto::KeyPair& identity,
                                      const Uuid& workspace_id,
                                      const QString& device_name,
                                      PairingMethod method);
    
    /**
     * Start pairing as responder (scan/enter code from other device).
     */
    Q_INVOKABLE void startAsResponder(const crypto::KeyPair& identity,
                                      const QString& device_name);
    
    /**
     * Submit verification code (for numeric code or passphrase methods).
     */
    Q_INVOKABLE void submitCode(const QString& code);

    /**
     * Submit QR code payload (for QR scan).
     */
    Q_INVOKABLE void submitQrCodeData(const QString& qrData);

    /**
     * Set the local listen port for QR payload generation.
     */
    void setListenPort(uint16_t port);
    
    /**
     * Cancel the pairing session.
     */
    Q_INVOKABLE void cancel();
    
    /**
     * Get the QR code data (JSON string).
     */
    [[nodiscard]] QString qrCodeData() const { return qr_code_data_; }
    
    /**
     * Get the verification code (6-digit or passphrase).
     */
    [[nodiscard]] QString verificationCode() const { return verification_code_; }
    
    /**
     * Get the current state.
     */
    [[nodiscard]] PairingState state() const { return state_; }
    
    /**
     * Get the paired device info (after successful pairing).
     */
    [[nodiscard]] const PairingInfo& pairedDevice() const { return paired_device_; }

signals:
    void stateChanged(PairingState state);
    void verificationCodeChanged();
    void qrCodeDataChanged();
    void pairingComplete(const PairingInfo& device);
    void pairingFailed(const QString& reason);

private:
    void setState(PairingState state);
    void generateVerificationCode();
    void generateQRCodeData();
    
    PairingState state_ = PairingState::Idle;
    PairingMethod method_;
    
    crypto::KeyPair identity_;
    Uuid workspace_id_;
    QString device_name_;
    
    QString verification_code_;
    QString qr_code_data_;
    
    PairingInfo paired_device_;
    uint16_t listen_port_ = 0;
    
    // Ephemeral keys for this pairing session
    crypto::KeyPair ephemeral_keys_;
};

/**
 * Generate QR code data for pairing.
 * 
 * JSON format:
 * {
 *   "v": 1,
 *   "id": "device-uuid",
 *   "name": "Device Name",
 *   "pk": "base64-public-key",
 *   "addr": "192.168.1.100",
 *   "port": 12345,
 *   "code": "123456",
 *   "ws": "workspace-uuid"
 * }
 */
QString generateQRCodeJson(const PairingInfo& info);

/**
 * Parse QR code data.
 */
Result<PairingInfo, Error> parseQRCodeJson(const QString& json);

} // namespace zinc::network

Q_DECLARE_METATYPE(zinc::network::PairingSession::PairingState)
