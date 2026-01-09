#include "network/discovery.hpp"

#ifdef Q_OS_ANDROID

#include <QJniObject>
#include <QJniEnvironment>
#include <QtCore/private/qandroidextras_p.h>

namespace zinc::network {

/**
 * Android NsdManager-based discovery backend.
 * 
 * Uses JNI to interact with Android's Network Service Discovery API.
 */
class NsdDiscoveryBackend : public DiscoveryBackend {
public:
    NsdDiscoveryBackend() {
        // Get NsdManager from Android context
        QJniObject context = QNativeInterface::QAndroidApplication::context();
        nsd_manager_ = context.callObjectMethod(
            "getSystemService",
            "(Ljava/lang/String;)Ljava/lang/Object;",
            QJniObject::fromString("servicediscovery").object()
        );
    }
    
    ~NsdDiscoveryBackend() {
        stop_advertising();
        stop_browsing();
    }
    
    Result<void, Error> start_advertising(const ServiceInfo& info) override {
        // Create NsdServiceInfo
        QJniObject service_info("android/net/nsd/NsdServiceInfo");
        
        service_info.callMethod<void>(
            "setServiceName",
            "(Ljava/lang/String;)V",
            QJniObject::fromString(info.device_name).object()
        );
        
        service_info.callMethod<void>(
            "setServiceType",
            "(Ljava/lang/String;)V",
            QJniObject::fromString(DiscoveryService::SERVICE_TYPE).object()
        );
        
        service_info.callMethod<void>(
            "setPort",
            "(I)V",
            static_cast<jint>(info.port)
        );
        
        // Set TXT records
        service_info.callMethod<void>(
            "setAttribute",
            "(Ljava/lang/String;Ljava/lang/String;)V",
            QJniObject::fromString("id").object(),
            QJniObject::fromString(QString::fromStdString(
                info.device_id.to_string())).object()
        );
        
        service_info.callMethod<void>(
            "setAttribute",
            "(Ljava/lang/String;Ljava/lang/String;)V",
            QJniObject::fromString("ws").object(),
            QJniObject::fromString(QString::fromStdString(
                info.workspace_id.to_string())).object()
        );
        
        service_info.callMethod<void>(
            "setAttribute",
            "(Ljava/lang/String;Ljava/lang/String;)V",
            QJniObject::fromString("v").object(),
            QJniObject::fromString(QString::number(info.protocol_version)).object()
        );
        
        // Register service
        // Note: This would need a proper RegistrationListener implementation
        // which requires more JNI code to handle callbacks
        
        return Result<void, Error>::ok();
    }
    
    void stop_advertising() override {
        if (nsd_manager_.isValid() && registration_listener_.isValid()) {
            nsd_manager_.callMethod<void>(
                "unregisterService",
                "(Landroid/net/nsd/NsdManager$RegistrationListener;)V",
                registration_listener_.object()
            );
        }
    }
    
    Result<void, Error> start_browsing() override {
        // Note: This would need a proper DiscoveryListener implementation
        return Result<void, Error>::ok();
    }
    
    void stop_browsing() override {
        if (nsd_manager_.isValid() && discovery_listener_.isValid()) {
            nsd_manager_.callMethod<void>(
                "stopServiceDiscovery",
                "(Landroid/net/nsd/NsdManager$DiscoveryListener;)V",
                discovery_listener_.object()
            );
        }
    }

private:
    QJniObject nsd_manager_;
    QJniObject registration_listener_;
    QJniObject discovery_listener_;
};

std::unique_ptr<DiscoveryBackend> createNsdBackend() {
    return std::make_unique<NsdDiscoveryBackend>();
}

} // namespace zinc::network

#endif // Q_OS_ANDROID

