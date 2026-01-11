#include <QCoreApplication>
#include <QGuiApplication>
#include <QStandardPaths>
#include <catch2/catch_session.hpp>

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName("zinc");
    QCoreApplication::setOrganizationDomain("zinc.app");
    QCoreApplication::setApplicationName("zinc_qml_tests");
    QStandardPaths::setTestModeEnabled(true);
    Catch::Session session;
    return session.run(argc, argv);
}
