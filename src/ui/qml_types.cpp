#include "ui/qml_types.hpp"
#include "ui/DataStore.hpp"
#include "ui/models/BlockModel.hpp"
#include "ui/models/PageTreeModel.hpp"
#include "ui/models/SearchResultModel.hpp"
#include "ui/controllers/EditorController.hpp"
#include "ui/controllers/SyncController.hpp"
#include "ui/controllers/PairingController.hpp"
#include "platform/android/android_utils.hpp"

namespace zinc::ui {

void registerQmlTypes() {
    // Data Store singleton (registered under "zinc" module to match QML imports)
    qmlRegisterSingletonType<DataStore>("zinc", 1, 0, "DataStore", DataStore::create);
    
    // Platform utilities
    qmlRegisterSingletonType<platform::AndroidUtils>("zinc", 1, 0, "AndroidUtils", platform::AndroidUtils::create);
    
    // Models
    qmlRegisterType<BlockModel>("Zinc", 1, 0, "BlockModel");
    qmlRegisterType<PageTreeModel>("Zinc", 1, 0, "PageTreeModel");
    qmlRegisterType<SearchResultModel>("Zinc", 1, 0, "SearchResultModel");
    
    // Controllers
    qmlRegisterType<EditorController>("Zinc", 1, 0, "EditorController");
    qmlRegisterType<SyncController>("Zinc", 1, 0, "SyncController");
    qmlRegisterType<PairingController>("Zinc", 1, 0, "PairingController");
}

} // namespace zinc::ui

