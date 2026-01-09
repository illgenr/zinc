#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "ui/qml_types.hpp"
#include "crypto/keys.hpp"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    
    // Set application metadata
    app.setApplicationName("Zinc");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("Zinc");
    app.setOrganizationDomain("zinc.local");
    
    // Initialize crypto
    auto crypto_result = zinc::crypto::init();
    if (crypto_result.is_err()) {
        qCritical() << "Failed to initialize crypto:" 
                    << crypto_result.unwrap_err().message.c_str();
        return 1;
    }
    
    // Register QML types
    zinc::ui::registerQmlTypes();
    
    // Set up QML engine
    QQmlApplicationEngine engine;
    
    // Handle creation failures
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    
    // Load main QML
    engine.loadFromModule("zinc", "Main");

    return app.exec();
}

