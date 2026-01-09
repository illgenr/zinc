#include "ui/qml_types.hpp"
#include "ui/models/BlockModel.hpp"
#include "ui/models/PageTreeModel.hpp"
#include "ui/models/SearchResultModel.hpp"
#include "ui/controllers/EditorController.hpp"
#include "ui/controllers/SyncController.hpp"
#include "ui/controllers/PairingController.hpp"

namespace zinc::ui {

void registerQmlTypes() {
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

