#include <QCoreApplication>
#include <QEventLoop>
#include <QHostAddress>
#include <QTimer>

#include "crypto/keys.hpp"
#include "network/sync_manager.hpp"

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);

    qputenv("ZINC_DEBUG_SYNC", "1");
    qputenv("ZINC_SYNC_DISABLE_DISCOVERY", "1");

    const auto workspaceId = zinc::Uuid::generate();
    const auto deviceA = zinc::Uuid::generate();
    const auto deviceB = zinc::Uuid::generate();

    zinc::network::SyncManager a;
    zinc::network::SyncManager b;

    a.initialize(zinc::crypto::generate_keypair(), workspaceId, QStringLiteral("A"), deviceA);
    b.initialize(zinc::crypto::generate_keypair(), workspaceId, QStringLiteral("B"), deviceB);

    QObject::connect(&a, &zinc::network::SyncManager::error, &app, [&](const QString &msg) {
        qCritical().noquote() << "A error:" << msg;
    });
    QObject::connect(&b, &zinc::network::SyncManager::error, &app, [&](const QString &msg) {
        qCritical().noquote() << "B error:" << msg;
    });

    if (!a.start(0)) {
        return 1;
    }
    if (!b.start(0)) {
        return 1;
    }

    bool aSawB = false;
    bool bSawA = false;

    QObject::connect(&a, &zinc::network::SyncManager::peerConnected, &app, [&](const zinc::Uuid &id) {
        aSawB = aSawB || (id == deviceB);
    });
    QObject::connect(&b, &zinc::network::SyncManager::peerConnected, &app, [&](const zinc::Uuid &id) {
        bSawA = bSawA || (id == deviceA);
    });

    // Initiate a direct connection A -> B; B should rekey its incoming peer entry via Hello.
    a.connectToEndpoint(deviceB, QHostAddress::LocalHost, b.listeningPort());

    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    timeout.setInterval(3000);
    QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);

    QTimer poll;
    poll.setInterval(20);
    QObject::connect(&poll, &QTimer::timeout, &loop, [&]() {
        if (aSawB && bSawA) {
            loop.quit();
        }
    });

    timeout.start();
    poll.start();
    loop.exec();

    if (!aSawB || !bSawA) {
        return 2;
    }
    return 0;
}
