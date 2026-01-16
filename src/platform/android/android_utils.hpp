#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QPermission>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QJniEnvironment>
#include <QtCore/qnativeinterface.h>
#endif

namespace zinc::platform {

/**
 * AndroidUtils - Platform utilities for Android.
 * Provides access to Android-specific functionality from QML.
 */
class AndroidUtils : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit AndroidUtils(QObject* parent = nullptr);
    
    static AndroidUtils* create(QQmlEngine*, QJSEngine*) {
        static AndroidUtils instance;
        return &instance;
    }

    /**
     * Open the app's settings page in Android Settings.
     * This allows users to grant permissions manually.
     */
    Q_INVOKABLE void openAppSettings();
    
    /**
     * Check if a specific permission is granted.
     */
    Q_INVOKABLE bool hasPermission(const QPermission& permission);
    
    /**
     * Request a permission from the system.
     * Note: For Qt 6.5+, this triggers the system permission dialog.
     */
    Q_INVOKABLE void requestPermission(const QPermission& permission);

    /**
     * Camera permission helpers for QML.
     */
    Q_INVOKABLE bool hasCameraPermission();
    Q_INVOKABLE void requestCameraPermission();
    
    /**
     * Check if we're running on Android.
     */
    Q_INVOKABLE bool isAndroid() const;

signals:
    void permissionGranted(const QPermission& permission);
    void permissionDenied(const QPermission& permission);
    void cameraPermissionGranted();
    void cameraPermissionDenied();
};

} // namespace zinc::platform
