#include <QCoreApplication>
#include <QDebug>
#include <QStringList>

#include "crypto/keys.hpp"
#include "network/sync_manager.hpp"

namespace {

struct CapturedLog {
    QtMsgType type;
    QString message;
};

QVector<CapturedLog> &capturedLogs() {
    static QVector<CapturedLog> logs;
    return logs;
}

void messageHandler(QtMsgType type, const QMessageLogContext &, const QString &message) {
    capturedLogs().push_back(CapturedLog{type, message});
}

bool containsDisconnectWhileConnecting(const QVector<CapturedLog> &logs) {
    const auto needlePrefix = QStringLiteral("SYNC: socket disconnect state=");
    const auto needleState = QStringLiteral("Connecting");
    return std::any_of(logs.begin(), logs.end(), [&](const CapturedLog &entry) {
        return entry.message.contains(needlePrefix) && entry.message.contains(needleState);
    });
}

} // namespace

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);

    qputenv("ZINC_DEBUG_SYNC", "1");
    qInstallMessageHandler(messageHandler);

    auto identity = zinc::crypto::generate_keypair();
    const auto workspaceId = zinc::Uuid::generate();
    const auto localDeviceId = zinc::Uuid::generate();
    const auto remoteDeviceId = zinc::Uuid::generate();

    zinc::network::SyncManager manager;
    manager.initialize(identity, workspaceId, QStringLiteral("test-device"), localDeviceId);

    const auto host = QHostAddress::LocalHost;
    constexpr uint16_t port = 9; // Discard port; not expected to accept connections.

    manager.connectToEndpoint(remoteDeviceId, host, port);

    capturedLogs().clear();
    manager.connectToEndpoint(remoteDeviceId, host, port);

    QCoreApplication::processEvents();

    if (containsDisconnectWhileConnecting(capturedLogs())) {
        qCritical().noquote() << "Second connectToEndpoint canceled an in-progress connection";
        return 1;
    }

    return 0;
}
