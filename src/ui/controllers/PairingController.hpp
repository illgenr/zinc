#pragma once

#include "network/pairing.hpp"
#include <QObject>
#include <QQmlEngine>

namespace zinc::ui {

/**
 * PairingController - Controller for device pairing UI.
 */
class PairingController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(bool pairing READ isPairing NOTIFY pairingChanged)
    Q_PROPERTY(QString verificationCode READ verificationCode NOTIFY verificationCodeChanged)
    Q_PROPERTY(QString qrCodeData READ qrCodeData NOTIFY qrCodeDataChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString workspaceId READ workspaceId NOTIFY workspaceIdChanged)
    Q_PROPERTY(QString peerDeviceId READ peerDeviceId NOTIFY peerInfoChanged)
    Q_PROPERTY(QString peerName READ peerName NOTIFY peerInfoChanged)
    Q_PROPERTY(QString peerHost READ peerHost NOTIFY peerInfoChanged)
    Q_PROPERTY(int peerPort READ peerPort NOTIFY peerInfoChanged)
    
public:
    explicit PairingController(QObject* parent = nullptr);
    
    [[nodiscard]] bool isPairing() const;
    [[nodiscard]] QString verificationCode() const;
    [[nodiscard]] QString qrCodeData() const;
    [[nodiscard]] QString status() const;
    [[nodiscard]] QString workspaceId() const;
    [[nodiscard]] QString peerDeviceId() const;
    [[nodiscard]] QString peerName() const;
    [[nodiscard]] QString peerHost() const;
    [[nodiscard]] int peerPort() const;
    
    Q_INVOKABLE void configureLocalDevice(const QString& deviceName,
                                          const QString& workspaceId,
                                          int listenPort);
    Q_INVOKABLE void startPairingAsInitiator(const QString& method);
    Q_INVOKABLE void startPairingAsResponder();
    Q_INVOKABLE void submitCode(const QString& code);
    Q_INVOKABLE void submitQrCodeData(const QString& qrData);
    Q_INVOKABLE void cancel();

signals:
    void pairingChanged();
    void verificationCodeChanged();
    void qrCodeDataChanged();
    void statusChanged();
    void workspaceIdChanged();
    void peerInfoChanged();
    void pairingComplete(const QString& deviceName);
    void pairingFailed(const QString& reason);

private:
    void updatePeerInfo(const network::PairingInfo& info);

    std::unique_ptr<network::PairingSession> session_;
    QString status_;
    QString workspace_id_;
    QString device_name_ = "This Device";
    int listen_port_ = 0;
    network::PairingInfo peer_info_{};
};

} // namespace zinc::ui
