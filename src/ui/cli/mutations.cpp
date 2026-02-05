#include "ui/cli/mutations.hpp"

#include <QUuid>
#include <QVariantMap>

#include "ui/DataStore.hpp"

namespace zinc::ui {

namespace {

[[nodiscard]] QString trimmed(const QString& s) {
    return s.trimmed();
}

[[nodiscard]] bool exists_notebook(DataStore& store, const QString& notebookId) {
    return !store.getNotebook(notebookId).isEmpty();
}

[[nodiscard]] bool exists_page(DataStore& store, const QString& pageId) {
    return !store.getPage(pageId).isEmpty();
}

[[nodiscard]] QVariantMap make_page_row(const QString& pageId,
                                        const QString& title,
                                        const QString& parentId,
                                        int depth,
                                        const QString& contentMarkdown,
                                        const QString& notebookId,
                                        bool includeNotebookId) {
    QVariantMap page;
    page.insert(QStringLiteral("pageId"), pageId);
    page.insert(QStringLiteral("title"), title);
    page.insert(QStringLiteral("parentId"), parentId);
    page.insert(QStringLiteral("depth"), depth);
    page.insert(QStringLiteral("sortOrder"), 0);
    page.insert(QStringLiteral("contentMarkdown"), contentMarkdown);
    if (includeNotebookId) {
        page.insert(QStringLiteral("notebookId"), notebookId);
    }
    return page;
}

} // namespace

Result<QString> create_notebook(DataStore& store, const CreateNotebookOptions& options) {
    const auto name = trimmed(options.name);
    if (name.isEmpty()) {
        return Result<QString>::err(Error{"Notebook name is required"});
    }

    const auto id = store.createNotebook(name);
    if (id.isEmpty()) {
        return Result<QString>::err(Error{"Failed to create notebook"});
    }
    if (!exists_notebook(store, id)) {
        return Result<QString>::err(Error{"Notebook creation did not persist"});
    }
    return Result<QString>::ok(id);
}

Result<void> delete_notebook(DataStore& store, const DeleteNotebookOptions& options) {
    const auto id = trimmed(options.notebookId);
    if (id.isEmpty()) {
        return Result<void>::err(Error{"Notebook id is required"});
    }
    if (!exists_notebook(store, id)) {
        return Result<void>::err(Error{("Notebook not found: " + id).toStdString()});
    }

    store.deleteNotebook(id, options.deletePages);

    if (exists_notebook(store, id)) {
        return Result<void>::err(Error{"Notebook delete did not persist"});
    }
    return Result<void>::ok();
}

Result<QString> create_page(DataStore& store, const CreatePageOptions& options) {
    const auto title = trimmed(options.title);
    if (title.isEmpty()) {
        return Result<QString>::err(Error{"Page title is required"});
    }

    const auto parentId = trimmed(options.parentPageId);
    const bool hasParent = !parentId.isEmpty();
    const bool hasNotebookId = !trimmed(options.notebookId).isEmpty();
    const bool loose = options.loose;

    if (hasParent && (hasNotebookId || loose)) {
        return Result<QString>::err(Error{"Use either --parent OR (--notebook/--loose), not both"});
    }

    QString resolvedNotebookId;
    QString resolvedParentId;
    int depth = 0;
    bool includeNotebookId = false;

    if (hasParent) {
        const auto parent = store.getPage(parentId);
        if (parent.isEmpty()) {
            return Result<QString>::err(Error{("Parent page not found: " + parentId).toStdString()});
        }
        resolvedNotebookId = parent.value(QStringLiteral("notebookId")).toString();
        resolvedParentId = parent.value(QStringLiteral("pageId")).toString();
        depth = parent.value(QStringLiteral("depth")).toInt() + 1;
        includeNotebookId = true;
    } else if (loose) {
        resolvedNotebookId = QStringLiteral("");
        resolvedParentId = QStringLiteral("");
        depth = 0;
        includeNotebookId = true;
    } else if (hasNotebookId) {
        resolvedNotebookId = trimmed(options.notebookId);
        resolvedParentId = QStringLiteral("");
        depth = 0;
        includeNotebookId = true;
    } else {
        // Let DataStore default notebook assignment happen.
        resolvedParentId = QStringLiteral("");
        depth = 0;
        includeNotebookId = false;
    }

    const auto pageId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    store.savePage(make_page_row(pageId,
                                 title,
                                 resolvedParentId,
                                 depth,
                                 QStringLiteral(""),
                                 resolvedNotebookId,
                                 includeNotebookId));

    if (!exists_page(store, pageId)) {
        return Result<QString>::err(Error{"Failed to create page"});
    }
    return Result<QString>::ok(pageId);
}

Result<void> delete_page(DataStore& store, const DeletePageOptions& options) {
    const auto id = trimmed(options.pageId);
    if (id.isEmpty()) {
        return Result<void>::err(Error{"Page id is required"});
    }
    if (!exists_page(store, id)) {
        return Result<void>::err(Error{("Page not found: " + id).toStdString()});
    }

    store.deletePage(id);

    if (exists_page(store, id)) {
        return Result<void>::err(Error{"Page delete did not persist"});
    }
    return Result<void>::ok();
}

} // namespace zinc::ui
