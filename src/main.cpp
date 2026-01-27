#include <QGuiApplication>
#include <QIcon>
#include <QLoggingCategory>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStyleHints>

#include "ui/logging.hpp"
#include "ui/qml_types.hpp"
#include "ui/AttachmentImageProvider.hpp"
#include "crypto/keys.hpp"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.styleHints()->setCursorFlashTime(500);

    // Set application metadata
    app.setApplicationName("Zinc");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("Zinc");
    app.setOrganizationDomain("zinc.local");
    app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/zinc/src/assets/icon.png")));

    // Install file logging early so crashes (especially on Windows GUI builds) are actionable.
    zinc::ui::install_file_logging();
    qInfo() << "Zinc: logging to" << zinc::ui::default_log_file_path();

    const auto args = QCoreApplication::arguments();
    if (args.contains(QStringLiteral("--debug-attachments"))) {
        qputenv("ZINC_DEBUG_ATTACHMENTS", "1");
        QLoggingCategory::setFilterRules(QStringLiteral("zinc.attachments.debug=true\n"));
        qInfo() << "Zinc: attachment debug enabled";
    }
    if (args.contains(QStringLiteral("--debug-sync"))) {
        qputenv("ZINC_DEBUG_SYNC", "1");
        qInfo() << "Zinc: sync debug enabled";
    }
    
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
    engine.addImageProvider(QStringLiteral("attachments"), new zinc::ui::AttachmentImageProvider());
    
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
