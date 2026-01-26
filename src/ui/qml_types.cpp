#include "ui/qml_types.hpp"
#include "ui/Clipboard.hpp"
#include "ui/DataStore.hpp"
#include "ui/FeatureFlags.hpp"
#include "ui/Cmark.hpp"
#include "ui/MarkdownBlocks.hpp"
#include "ui/InlineFormatting.hpp"
#include "ui/FontUtils.hpp"
#include "ui/models/BlockModel.hpp"
#include "ui/models/PageTreeModel.hpp"
#include "ui/models/SearchResultModel.hpp"
#include "ui/controllers/EditorController.hpp"
#include "ui/controllers/SyncController.hpp"
#include "ui/controllers/PairingController.hpp"
#if ZINC_ENABLE_QR
#include "ui/QrScanner.hpp"
#endif
#include "platform/android/android_utils.hpp"

namespace zinc::ui {

void registerQmlTypes() {
    static bool registered = false;
    if (registered) {
        return;
    }
    registered = true;

    // Data Store singleton (registered under "zinc" module to match QML imports)
    qmlRegisterSingletonType<DataStore>("zinc", 1, 0, "DataStore", DataStore::create);
    qmlRegisterSingletonType<Clipboard>("zinc", 1, 0, "Clipboard", Clipboard::create);
    qmlRegisterSingletonType<MarkdownBlocks>("zinc", 1, 0, "MarkdownBlocks", MarkdownBlocks::create);
    qmlRegisterSingletonType<Cmark>("zinc", 1, 0, "Cmark", Cmark::create);
    qmlRegisterSingletonType<InlineFormatting>("zinc", 1, 0, "InlineFormatting", InlineFormatting::create);
    qmlRegisterSingletonType<FontUtils>("zinc", 1, 0, "FontUtils", FontUtils::create);
    
    // Platform utilities
    qmlRegisterSingletonType<platform::AndroidUtils>("zinc", 1, 0, "AndroidUtils", platform::AndroidUtils::create);

    // Feature flags
    qmlRegisterSingletonType<FeatureFlags>("Zinc", 1, 0, "FeatureFlags", FeatureFlags::create);
    
    // Models
    qmlRegisterType<BlockModel>("Zinc", 1, 0, "BlockModel");
    qmlRegisterType<PageTreeModel>("Zinc", 1, 0, "PageTreeModel");
    qmlRegisterType<SearchResultModel>("Zinc", 1, 0, "SearchResultModel");
    
    // Controllers
    qmlRegisterType<EditorController>("Zinc", 1, 0, "EditorController");
    qmlRegisterType<SyncController>("Zinc", 1, 0, "SyncController");
    qmlRegisterType<PairingController>("Zinc", 1, 0, "PairingController");
#if ZINC_ENABLE_QR
    qmlRegisterType<QrScanner>("Zinc", 1, 0, "QrScanner");
#endif
}

} // namespace zinc::ui
