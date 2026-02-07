#include <QGuiApplication>
#include <QCommandLineParser>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStyleHints>
#include <QQuickStyle>
#include <QTextStream>

#include "ui/logging.hpp"
#include "ui/qml_types.hpp"
#include "ui/AttachmentImageProvider.hpp"
#include "ui/DataStore.hpp"
#include "ui/cli/list_tree.hpp"
#include "ui/cli/note.hpp"
#include "ui/cli/mutations.hpp"
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

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Zinc Notes"));
    parser.addHelpOption();
    parser.addVersionOption();

    const QCommandLineOption dbPathOption(
        QStringList{QStringLiteral("db")},
        QStringLiteral("Override database path (sets ZINC_DB_PATH for this run)."),
        QStringLiteral("path"));
    parser.addOption(dbPathOption);

    const QCommandLineOption includeIdsOption(
        QStringList{QStringLiteral("ids")},
        QStringLiteral("Include IDs in CLI output."));
    parser.addOption(includeIdsOption);

    const QCommandLineOption jsonOption(
        QStringList{QStringLiteral("json")},
        QStringLiteral("Output JSON (for commands that support it)."));
    parser.addOption(jsonOption);

    const QCommandLineOption noteIdOption(
        QStringList{QStringLiteral("id")},
        QStringLiteral("Page ID for 'note' command."),
        QStringLiteral("pageId"));
    parser.addOption(noteIdOption);

    const QCommandLineOption noteNameOption(
        QStringList{QStringLiteral("name")},
        QStringLiteral("Page title for 'note' command (exact match)."),
        QStringLiteral("title"));
    parser.addOption(noteNameOption);

    const QCommandLineOption noteHtmlOption(
        QStringList{QStringLiteral("html")},
        QStringLiteral("Render note output as HTML (default is markdown)."));
    parser.addOption(noteHtmlOption);

    const QCommandLineOption pageTitleOption(
        QStringList{QStringLiteral("title")},
        QStringLiteral("Page title for 'page-create' command."),
        QStringLiteral("title"));
    parser.addOption(pageTitleOption);

    const QCommandLineOption pageNotebookOption(
        QStringList{QStringLiteral("notebook")},
        QStringLiteral("Notebook id for 'page-create' command."),
        QStringLiteral("notebookId"));
    parser.addOption(pageNotebookOption);

    const QCommandLineOption pageParentOption(
        QStringList{QStringLiteral("parent")},
        QStringLiteral("Parent page id for 'page-create' command."),
        QStringLiteral("pageId"));
    parser.addOption(pageParentOption);

    const QCommandLineOption pageLooseOption(
        QStringList{QStringLiteral("loose")},
        QStringLiteral("Create page as a loose note (not in a notebook)."));
    parser.addOption(pageLooseOption);

    const QCommandLineOption deletePagesOption(
        QStringList{QStringLiteral("delete-pages")},
        QStringLiteral("For notebook deletion: also delete pages and tombstone them."));
    parser.addOption(deletePagesOption);

    const QCommandLineOption debugAttachmentsOption(
        QStringList{QStringLiteral("debug-attachments")},
        QStringLiteral("Enable attachment debug logging (also sets ZINC_DEBUG_ATTACHMENTS=1)."));
    parser.addOption(debugAttachmentsOption);

    const QCommandLineOption debugSyncOption(
        QStringList{QStringLiteral("debug-sync")},
        QStringLiteral("Enable sync debug logging (also sets ZINC_DEBUG_SYNC=1)."));
    parser.addOption(debugSyncOption);

    const QCommandLineOption debugSearchUiOption(
        QStringList{QStringLiteral("debug-search-ui")},
        QStringLiteral("Enable search UI debug logging (also sets ZINC_DEBUG_SEARCH_UI=1)."));
    parser.addOption(debugSearchUiOption);

    parser.addPositionalArgument(QStringLiteral("command"),
                                 QStringLiteral("Command to run (e.g. 'list')."));
    parser.process(app);

    if (parser.isSet(dbPathOption)) {
        qputenv("ZINC_DB_PATH", parser.value(dbPathOption).toUtf8());
    }

    const bool debugAttachments = parser.isSet(debugAttachmentsOption);
    const bool debugSync = parser.isSet(debugSyncOption);
    const bool debugSearchUi = parser.isSet(debugSearchUiOption);

    if (debugAttachments) {
        qputenv("ZINC_DEBUG_ATTACHMENTS", "1");
        QLoggingCategory::setFilterRules(QStringLiteral("zinc.attachments.debug=true\n"));
    }
    if (debugSync) {
        qputenv("ZINC_DEBUG_SYNC", "1");
    }
    if (debugSearchUi) {
        qputenv("ZINC_DEBUG_SEARCH_UI", "1");
    }

    const auto positional = parser.positionalArguments();
    const auto emit_json = [&](const QJsonObject& obj) {
        QTextStream(stdout) << QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact)) << QLatin1Char('\n');
    };

    if (!positional.isEmpty() && positional.first() == QStringLiteral("list")) {
        zinc::ui::DataStore store;
        if (!store.initialize()) {
            return 1;
        }

        const auto opts = zinc::ui::ListTreeOptions{.includeIds = parser.isSet(includeIdsOption)};
        const auto output = parser.isSet(jsonOption)
            ? zinc::ui::format_notebook_page_tree_json(store.getAllNotebooks(), store.getAllPages(), opts)
            : zinc::ui::format_notebook_page_tree(store.getAllNotebooks(), store.getAllPages(), opts);
        QTextStream(stdout) << output;
        return 0;
    }

    if (!positional.isEmpty() && positional.first() == QStringLiteral("note")) {
        zinc::ui::DataStore store;
        if (!store.initialize()) {
            return 1;
        }

        zinc::ui::NoteOptions options;
        options.pageId = parser.value(noteIdOption);
        options.name = parser.value(noteNameOption);
        options.html = parser.isSet(noteHtmlOption);

        const auto result = zinc::ui::render_note(store, options);
        if (result.is_err()) {
            QTextStream(stderr) << QString::fromStdString(result.unwrap_err().message) << QLatin1Char('\n');
            return 1;
        }

        QTextStream(stdout) << result.unwrap();
        return 0;
    }

    if (!positional.isEmpty() && positional.first() == QStringLiteral("notebook-create")) {
        zinc::ui::DataStore store;
        if (!store.initialize()) {
            return 1;
        }

        const auto created = zinc::ui::create_notebook(
            store, zinc::ui::CreateNotebookOptions{.name = parser.value(noteNameOption)});
        if (created.is_err()) {
            QTextStream(stderr) << QString::fromStdString(created.unwrap_err().message) << QLatin1Char('\n');
            return 1;
        }

        const auto notebookId = created.unwrap();
        if (parser.isSet(jsonOption)) {
            emit_json(QJsonObject{{QStringLiteral("notebookId"), notebookId}});
        } else {
            QTextStream(stdout) << notebookId << QLatin1Char('\n');
        }
        return 0;
    }

    if (!positional.isEmpty() && positional.first() == QStringLiteral("notebook-delete")) {
        zinc::ui::DataStore store;
        if (!store.initialize()) {
            return 1;
        }

        const auto deleted = zinc::ui::delete_notebook(
            store,
            zinc::ui::DeleteNotebookOptions{.notebookId = parser.value(noteIdOption),
                                           .deletePages = parser.isSet(deletePagesOption)});
        if (deleted.is_err()) {
            QTextStream(stderr) << QString::fromStdString(deleted.unwrap_err().message) << QLatin1Char('\n');
            return 1;
        }

        const auto id = parser.value(noteIdOption).trimmed();
        if (parser.isSet(jsonOption)) {
            emit_json(QJsonObject{{QStringLiteral("notebookId"), id}, {QStringLiteral("deleted"), true}});
        } else if (!id.isEmpty()) {
            QTextStream(stdout) << id << QLatin1Char('\n');
        }
        return 0;
    }

    if (!positional.isEmpty() && positional.first() == QStringLiteral("page-create")) {
        zinc::ui::DataStore store;
        if (!store.initialize()) {
            return 1;
        }

        const auto created = zinc::ui::create_page(
            store,
            zinc::ui::CreatePageOptions{
                .title = parser.value(pageTitleOption),
                .notebookId = parser.value(pageNotebookOption),
                .loose = parser.isSet(pageLooseOption),
                .parentPageId = parser.value(pageParentOption),
            });
        if (created.is_err()) {
            QTextStream(stderr) << QString::fromStdString(created.unwrap_err().message) << QLatin1Char('\n');
            return 1;
        }

        const auto pageId = created.unwrap();
        if (parser.isSet(jsonOption)) {
            emit_json(QJsonObject{{QStringLiteral("pageId"), pageId}});
        } else {
            QTextStream(stdout) << pageId << QLatin1Char('\n');
        }
        return 0;
    }

    if (!positional.isEmpty() && positional.first() == QStringLiteral("page-delete")) {
        zinc::ui::DataStore store;
        if (!store.initialize()) {
            return 1;
        }

        const auto deleted = zinc::ui::delete_page(store, zinc::ui::DeletePageOptions{.pageId = parser.value(noteIdOption)});
        if (deleted.is_err()) {
            QTextStream(stderr) << QString::fromStdString(deleted.unwrap_err().message) << QLatin1Char('\n');
            return 1;
        }

        const auto id = parser.value(noteIdOption).trimmed();
        if (parser.isSet(jsonOption)) {
            emit_json(QJsonObject{{QStringLiteral("pageId"), id}, {QStringLiteral("deleted"), true}});
        } else if (!id.isEmpty()) {
            QTextStream(stdout) << id << QLatin1Char('\n');
        }
        return 0;
    }

    // Install file logging early so crashes (especially on Windows GUI builds) are actionable.
    zinc::ui::install_file_logging();
    qInfo() << "Zinc: logging to" << zinc::ui::default_log_file_path();
    if (debugAttachments) {
        qInfo() << "Zinc: attachment debug enabled";
    }
    if (debugSync) {
        qInfo() << "Zinc: sync debug enabled";
    }
    if (debugSearchUi) {
        qInfo() << "Zinc: search UI debug enabled";
    }

#ifdef Q_OS_WIN
    // Qt Quick Controls' native styles can reject customization of certain controls (background/contentItem).
    // Prefer a non-native style by default on Windows, while allowing explicit overrides via env var.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("Fusion"));
    }
#endif
    
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
