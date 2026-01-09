#include "network/discovery.hpp"

#ifdef ZINC_HAS_AVAHI

#include <avahi-client/client.h>
#include <avahi-client/publish.h>
#include <avahi-client/lookup.h>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>
#include <avahi-common/simple-watch.h>
#include <avahi-common/thread-watch.h>

#include <thread>
#include <mutex>
#include <atomic>

namespace zinc::network {

/**
 * Avahi-based mDNS discovery backend for Linux.
 */
class AvahiDiscoveryBackend : public DiscoveryBackend {
public:
    AvahiDiscoveryBackend() = default;
    
    ~AvahiDiscoveryBackend() {
        stop_advertising();
        stop_browsing();
        
        if (client_) {
            avahi_client_free(client_);
        }
        if (threaded_poll_) {
            avahi_threaded_poll_free(threaded_poll_);
        }
    }
    
    Result<void, Error> start_advertising(const ServiceInfo& info) override {
        if (!ensure_client()) {
            return Result<void, Error>::err(Error{"Failed to create Avahi client"});
        }
        
        // Create entry group for our service
        entry_group_ = avahi_entry_group_new(client_, entry_group_callback, this);
        if (!entry_group_) {
            return Result<void, Error>::err(Error{"Failed to create entry group"});
        }
        
        // Prepare TXT records
        AvahiStringList* txt = nullptr;
        txt = avahi_string_list_add_printf(txt, "v=%d", info.protocol_version);
        txt = avahi_string_list_add_printf(txt, "id=%s", 
            info.device_id.to_string().c_str());
        txt = avahi_string_list_add_printf(txt, "ws=%s", 
            info.workspace_id.to_string().c_str());
        
        // Add service
        int ret = avahi_entry_group_add_service_strlst(
            entry_group_,
            AVAHI_IF_UNSPEC,
            AVAHI_PROTO_UNSPEC,
            static_cast<AvahiPublishFlags>(0),
            info.device_name.toUtf8().constData(),
            DiscoveryService::SERVICE_TYPE,
            nullptr,  // domain
            nullptr,  // host
            info.port,
            txt
        );
        
        avahi_string_list_free(txt);
        
        if (ret < 0) {
            return Result<void, Error>::err(Error{
                "Failed to add service: " + std::string(avahi_strerror(ret))});
        }
        
        // Commit
        ret = avahi_entry_group_commit(entry_group_);
        if (ret < 0) {
            return Result<void, Error>::err(Error{
                "Failed to commit service: " + std::string(avahi_strerror(ret))});
        }
        
        return Result<void, Error>::ok();
    }
    
    void stop_advertising() override {
        if (entry_group_) {
            avahi_entry_group_reset(entry_group_);
            avahi_entry_group_free(entry_group_);
            entry_group_ = nullptr;
        }
    }
    
    Result<void, Error> start_browsing() override {
        if (!ensure_client()) {
            return Result<void, Error>::err(Error{"Failed to create Avahi client"});
        }
        
        browser_ = avahi_service_browser_new(
            client_,
            AVAHI_IF_UNSPEC,
            AVAHI_PROTO_UNSPEC,
            DiscoveryService::SERVICE_TYPE,
            nullptr,  // domain
            static_cast<AvahiLookupFlags>(0),
            browse_callback,
            this
        );
        
        if (!browser_) {
            return Result<void, Error>::err(Error{"Failed to create service browser"});
        }
        
        return Result<void, Error>::ok();
    }
    
    void stop_browsing() override {
        if (browser_) {
            avahi_service_browser_free(browser_);
            browser_ = nullptr;
        }
    }

private:
    AvahiThreadedPoll* threaded_poll_ = nullptr;
    AvahiClient* client_ = nullptr;
    AvahiEntryGroup* entry_group_ = nullptr;
    AvahiServiceBrowser* browser_ = nullptr;
    
    bool ensure_client() {
        if (client_) return true;
        
        // Create threaded poll
        threaded_poll_ = avahi_threaded_poll_new();
        if (!threaded_poll_) return false;
        
        // Create client
        int error;
        client_ = avahi_client_new(
            avahi_threaded_poll_get(threaded_poll_),
            static_cast<AvahiClientFlags>(0),
            client_callback,
            this,
            &error
        );
        
        if (!client_) {
            avahi_threaded_poll_free(threaded_poll_);
            threaded_poll_ = nullptr;
            return false;
        }
        
        // Start the poll thread
        avahi_threaded_poll_start(threaded_poll_);
        
        return true;
    }
    
    static void client_callback(AvahiClient* client, AvahiClientState state, void* userdata) {
        auto* self = static_cast<AvahiDiscoveryBackend*>(userdata);
        
        switch (state) {
            case AVAHI_CLIENT_S_RUNNING:
                // Server is running
                break;
            case AVAHI_CLIENT_FAILURE:
                // Error
                break;
            case AVAHI_CLIENT_S_COLLISION:
            case AVAHI_CLIENT_S_REGISTERING:
                // Registering
                break;
            case AVAHI_CLIENT_CONNECTING:
                // Connecting
                break;
        }
    }
    
    static void entry_group_callback(AvahiEntryGroup* group, 
                                     AvahiEntryGroupState state, 
                                     void* userdata) {
        switch (state) {
            case AVAHI_ENTRY_GROUP_ESTABLISHED:
                // Service registered successfully
                break;
            case AVAHI_ENTRY_GROUP_COLLISION:
                // Name collision
                break;
            case AVAHI_ENTRY_GROUP_FAILURE:
                // Registration failed
                break;
            case AVAHI_ENTRY_GROUP_UNCOMMITED:
            case AVAHI_ENTRY_GROUP_REGISTERING:
                break;
        }
    }
    
    static void browse_callback(AvahiServiceBrowser* browser,
                               AvahiIfIndex interface,
                               AvahiProtocol protocol,
                               AvahiBrowserEvent event,
                               const char* name,
                               const char* type,
                               const char* domain,
                               AvahiLookupResultFlags flags,
                               void* userdata) {
        auto* self = static_cast<AvahiDiscoveryBackend*>(userdata);
        
        switch (event) {
            case AVAHI_BROWSER_NEW:
                // Resolve the service to get details
                avahi_service_resolver_new(
                    self->client_,
                    interface,
                    protocol,
                    name,
                    type,
                    domain,
                    AVAHI_PROTO_UNSPEC,
                    static_cast<AvahiLookupFlags>(0),
                    resolve_callback,
                    userdata
                );
                break;
                
            case AVAHI_BROWSER_REMOVE:
                // Service removed - need to map name to device_id
                // For now, we'd need to track this mapping
                break;
                
            case AVAHI_BROWSER_FAILURE:
            case AVAHI_BROWSER_ALL_FOR_NOW:
            case AVAHI_BROWSER_CACHE_EXHAUSTED:
                break;
        }
    }
    
    static void resolve_callback(AvahiServiceResolver* resolver,
                                AvahiIfIndex interface,
                                AvahiProtocol protocol,
                                AvahiResolverEvent event,
                                const char* name,
                                const char* type,
                                const char* domain,
                                const char* host_name,
                                const AvahiAddress* address,
                                uint16_t port,
                                AvahiStringList* txt,
                                AvahiLookupResultFlags flags,
                                void* userdata) {
        auto* self = static_cast<AvahiDiscoveryBackend*>(userdata);
        
        if (event == AVAHI_RESOLVER_FOUND) {
            // Parse TXT records
            PeerInfo info;
            info.port = port;
            info.device_name = QString::fromUtf8(name);
            info.last_seen = Timestamp::now();
            
            // Get IP address
            char addr_str[AVAHI_ADDRESS_STR_MAX];
            avahi_address_snprint(addr_str, sizeof(addr_str), address);
            info.host = QHostAddress(QString::fromUtf8(addr_str));
            
            // Parse TXT records
            for (AvahiStringList* item = txt; item; item = item->next) {
                char* key;
                char* value;
                if (avahi_string_list_get_pair(item, &key, &value, nullptr) == 0) {
                    QString k = QString::fromUtf8(key);
                    QString v = QString::fromUtf8(value);
                    
                    if (k == "id") {
                        if (auto id = Uuid::parse(v.toStdString())) {
                            info.device_id = *id;
                        }
                    } else if (k == "ws") {
                        if (auto id = Uuid::parse(v.toStdString())) {
                            info.workspace_id = *id;
                        }
                    } else if (k == "v") {
                        info.protocol_version = v.toInt();
                    }
                    
                    avahi_free(key);
                    avahi_free(value);
                }
            }
            
            // Notify
            if (self->on_peer_discovered && !info.device_id.is_nil()) {
                self->on_peer_discovered(info);
            }
        }
        
        avahi_service_resolver_free(resolver);
    }
};

std::unique_ptr<DiscoveryBackend> createAvahiBackend() {
    return std::make_unique<AvahiDiscoveryBackend>();
}

} // namespace zinc::network

#endif // ZINC_HAS_AVAHI

