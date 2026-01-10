#include "platform/android/android_utils.hpp"
#include <QDebug>
#include <QDesktopServices>
#include <QUrl>
#include <QGuiApplication>

namespace zinc::platform {

AndroidUtils::AndroidUtils(QObject* parent)
    : QObject(parent)
{
}

bool AndroidUtils::isAndroid() const {
#ifdef Q_OS_ANDROID
    return true;
#else
    return false;
#endif
}

void AndroidUtils::openAppSettings() {
#ifdef Q_OS_ANDROID
    // Use Qt's JNI helpers to open app settings
    // This approach doesn't require Qt CorePrivate
    
    auto activity = QJniObject(QNativeInterface::QAndroidApplication::context());
    if (!activity.isValid()) {
        qWarning() << "AndroidUtils: No valid context";
        return;
    }
    
    // Get package name
    auto packageName = activity.callObjectMethod<jstring>("getPackageName");
    QString pkgStr = packageName.toString();
    
    // Build the settings URI
    QString uriStr = "package:" + pkgStr;
    auto uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri",
        "parse",
        "(Ljava/lang/String;)Landroid/net/Uri;",
        QJniObject::fromString(uriStr).object<jstring>()
    );
    
    // Create the intent
    auto intent = QJniObject("android/content/Intent",
        "(Ljava/lang/String;)V",
        QJniObject::fromString("android.settings.APPLICATION_DETAILS_SETTINGS").object<jstring>()
    );
    
    intent.callObjectMethod(
        "setData",
        "(Landroid/net/Uri;)Landroid/content/Intent;",
        uri.object()
    );
    
    intent.callObjectMethod(
        "addFlags",
        "(I)Landroid/content/Intent;",
        0x10000000  // FLAG_ACTIVITY_NEW_TASK
    );
    
    activity.callMethod<void>(
        "startActivity",
        "(Landroid/content/Intent;)V",
        intent.object()
    );
    
    qDebug() << "AndroidUtils: Opened settings for" << pkgStr;
#else
    qDebug() << "AndroidUtils: openAppSettings() not available on this platform";
#endif
}

bool AndroidUtils::hasPermission(const QPermission& permission) {
#ifdef Q_OS_ANDROID
    auto* app = qApp;
    if (!app) {
        return false;
    }
    auto result = app->checkPermission(permission);
    return result == Qt::PermissionStatus::Granted;
#else
    Q_UNUSED(permission)
    return true;
#endif
}

void AndroidUtils::requestPermission(const QPermission& permission) {
#ifdef Q_OS_ANDROID
    auto* app = qApp;
    if (!app) {
        qWarning() << "AndroidUtils: No application instance available";
        emit permissionDenied(permission);
        return;
    }
    app->requestPermission(permission, [this, permission](const QPermission& p) {
        if (p.status() == Qt::PermissionStatus::Granted) {
            qDebug() << "Permission granted:" << permission;
            emit permissionGranted(permission);
        } else {
            qDebug() << "Permission denied:" << permission;
            emit permissionDenied(permission);
        }
    });
#else
    Q_UNUSED(permission)
    emit permissionGranted(permission);
#endif
}

} // namespace zinc::platform
