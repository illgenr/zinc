#include <catch2/catch_test_macros.hpp>

#include <QCoreApplication>
#include <QElapsedTimer>

#include <functional>

#include "core/types.hpp"
#include "crypto/keys.hpp"
#include "network/sync_manager.hpp"

namespace {

class EnvVarGuard {
public:
    explicit EnvVarGuard(const char* name)
        : name_(name)
        , old_(qgetenv(name))
        , had_(qEnvironmentVariableIsSet(name))
    {
    }

    ~EnvVarGuard() {
        if (had_) {
            qputenv(name_.constData(), old_);
        } else {
            qunsetenv(name_.constData());
        }
    }

private:
    QByteArray name_;
    QByteArray old_;
    bool had_ = false;
};

bool spinUntil(const std::function<bool()>& predicate, int timeoutMs) {
    QElapsedTimer timer;
    timer.start();
    while (!predicate()) {
        if (timer.elapsed() > timeoutMs) {
            return false;
        }
        QCoreApplication::processEvents(QEventLoop::AllEvents, 25);
    }
    return true;
}

} // namespace

TEST_CASE("SyncManager: incoming manual connection requires approval", "[qml][sync]") {
    EnvVarGuard discoveryGuard("ZINC_SYNC_DISABLE_DISCOVERY");
    qputenv("ZINC_SYNC_DISABLE_DISCOVERY", "1");

    const auto workspaceId = zinc::Uuid::generate();
    const auto deviceA = zinc::Uuid::generate();
    const auto deviceB = zinc::Uuid::generate();

    auto keysA = zinc::crypto::generate_keypair();
    auto keysB = zinc::crypto::generate_keypair();

    zinc::network::SyncManager a;
    zinc::network::SyncManager b;

    a.initialize(keysA, workspaceId, QStringLiteral("Device A"), deviceA);
    b.initialize(keysB, workspaceId, QStringLiteral("Device B"), deviceB);

    if (!a.start(0) || !b.start(0) || b.listeningPort() == 0) {
        SKIP("TCP listen/connect not permitted in this environment");
    }

    bool approvalRequested = false;
    zinc::Uuid requestedPeer{};
    QString requestedName;
    QString requestedHost;
    uint16_t requestedPort = 0;

    QObject::connect(&b, &zinc::network::SyncManager::peerApprovalRequired,
                     &b, [&](const zinc::Uuid& deviceId,
                             const QString& deviceName,
                             const QString& host,
                             uint16_t port) {
                         approvalRequested = true;
                         requestedPeer = deviceId;
                         requestedName = deviceName;
                         requestedHost = host;
                         requestedPort = port;
                     });

    bool connectedAfterApproval = false;
    QObject::connect(&b, &zinc::network::SyncManager::peerConnected,
                     &b, [&](const zinc::Uuid& deviceId) {
                         if (deviceId == requestedPeer) {
                             connectedAfterApproval = true;
                         }
                     });

    a.connectToEndpoint(deviceB, QStringLiteral("localhost"), b.listeningPort());

    REQUIRE(spinUntil([&]() { return approvalRequested; }, 5000));
    REQUIRE(!requestedPeer.is_nil());
    REQUIRE(requestedName.isEmpty() == false);
    REQUIRE(requestedHost.isEmpty() == false);
    REQUIRE(requestedPort != 0);
    REQUIRE(b.connectedPeerCount() == 0);

    b.approvePeer(requestedPeer, true);
    REQUIRE(spinUntil([&]() { return connectedAfterApproval; }, 5000));
    REQUIRE(b.connectedPeerCount() == 1);
}
