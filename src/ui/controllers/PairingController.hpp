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
    
public:
    explicit PairingController(QObject* parent = nullptr);
    
    [[nodiscard]] bool isPairing() const;
    [[nodiscard]] QString verificationCode() const;
    [[nodiscard]] QString qrCodeData() const;
    [[nodiscard]] QString status() const;
    
    Q_INVOKABLE void startPairingAsInitiator(const QString& method);
    Q_INVOKABLE void startPairingAsResponder();
    Q_INVOKABLE void submitCode(const QString& code);
    Q_INVOKABLE void cancel();

signals:
    void pairingChanged();
    void verificationCodeChanged();
    void qrCodeDataChanged();
    void statusChanged();
    void pairingComplete(const QString& deviceName);
    void pairingFailed(const QString& reason);

private:
    std::unique_ptr<network::PairingSession> session_;
    QString status_;
};

} // namespace zinc::ui

