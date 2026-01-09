#include "ui/models/PageTreeModel.hpp"

namespace zinc::ui {

PageTreeModel::PageTreeModel(QObject* parent)
    : QAbstractItemModel(parent)
{
}

QModelIndex PageTreeModel::index(int row, int column, const QModelIndex& parent) const {
    if (!hasIndex(row, column, parent)) {
        return QModelIndex();
    }
    
    // Get children of parent
    std::optional<Uuid> parent_id;
    if (parent.isValid()) {
        parent_id = Uuid::parse(
            data(parent, IdRole).toString().toStdString());
    }
    
    int count = 0;
    for (size_t i = 0; i < pages_.size(); ++i) {
        if (pages_[i].parent_page_id == parent_id && !pages_[i].is_archived) {
            if (count == row) {
                return createIndex(row, column, const_cast<Page*>(&pages_[i]));
            }
            ++count;
        }
    }
    
    return QModelIndex();
}

QModelIndex PageTreeModel::parent(const QModelIndex& child) const {
    if (!child.isValid()) {
        return QModelIndex();
    }
    
    auto* page = static_cast<Page*>(child.internalPointer());
    if (!page || !page->parent_page_id) {
        return QModelIndex();
    }
    
    // Find parent page
    for (size_t i = 0; i < pages_.size(); ++i) {
        if (pages_[i].id == *page->parent_page_id) {
            // Find row of parent among its siblings
            int row = 0;
            for (size_t j = 0; j < i; ++j) {
                if (pages_[j].parent_page_id == pages_[i].parent_page_id) {
                    ++row;
                }
            }
            return createIndex(row, 0, const_cast<Page*>(&pages_[i]));
        }
    }
    
    return QModelIndex();
}

int PageTreeModel::rowCount(const QModelIndex& parent) const {
    std::optional<Uuid> parent_id;
    if (parent.isValid()) {
        auto* page = static_cast<Page*>(parent.internalPointer());
        if (page) {
            parent_id = page->id;
        }
    }
    
    int count = 0;
    for (const auto& page : pages_) {
        if (page.parent_page_id == parent_id && !page.is_archived) {
            ++count;
        }
    }
    return count;
}

int PageTreeModel::columnCount(const QModelIndex&) const {
    return 1;
}

QVariant PageTreeModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid()) {
        return QVariant();
    }
    
    auto* page = static_cast<Page*>(index.internalPointer());
    if (!page) {
        return QVariant();
    }
    
    switch (role) {
        case IdRole:
        case Qt::DisplayRole:
            return QString::fromStdString(page->id.to_string());
        case TitleRole:
            return QString::fromStdString(page->title);
        case ParentIdRole:
            return page->parent_page_id 
                ? QString::fromStdString(page->parent_page_id->to_string())
                : QString();
        case SortOrderRole:
            return page->sort_order;
        case IsArchivedRole:
            return page->is_archived;
        default:
            return QVariant();
    }
}

QHash<int, QByteArray> PageTreeModel::roleNames() const {
    return {
        {IdRole, "pageId"},
        {TitleRole, "title"},
        {ParentIdRole, "parentId"},
        {SortOrderRole, "sortOrder"},
        {IsArchivedRole, "isArchived"}
    };
}

QString PageTreeModel::workspaceId() const {
    return QString::fromStdString(workspace_id_.to_string());
}

void PageTreeModel::setWorkspaceId(const QString& id) {
    auto parsed = Uuid::parse(id.toStdString());
    if (parsed) {
        workspace_id_ = *parsed;
        loadPages();
        emit workspaceIdChanged();
    }
}

void PageTreeModel::loadPages() {
    beginResetModel();
    pages_.clear();
    // In real implementation, load from storage
    endResetModel();
    emit pageCountChanged();
}

QString PageTreeModel::createPage(const QString& title, const QString& parentId) {
    std::optional<Uuid> parent_id;
    if (!parentId.isEmpty()) {
        parent_id = Uuid::parse(parentId.toStdString());
    }
    
    auto page = create_page(
        Uuid::generate(),
        workspace_id_,
        title.toStdString(),
        static_cast<int>(pages_.size()),
        parent_id
    );
    
    beginInsertRows(QModelIndex(), static_cast<int>(pages_.size()), 
                    static_cast<int>(pages_.size()));
    pages_.push_back(page);
    endInsertRows();
    
    emit pageCountChanged();
    return QString::fromStdString(page.id.to_string());
}

void PageTreeModel::renamePage(const QString& pageId, const QString& newTitle) {
    auto id = Uuid::parse(pageId.toStdString());
    if (!id) return;
    
    for (size_t i = 0; i < pages_.size(); ++i) {
        if (pages_[i].id == *id) {
            pages_[i] = with_title(pages_[i], newTitle.toStdString());
            auto idx = createIndex(static_cast<int>(i), 0, &pages_[i]);
            emit dataChanged(idx, idx, {TitleRole});
            break;
        }
    }
}

void PageTreeModel::movePage(const QString& pageId, const QString& newParentId) {
    auto id = Uuid::parse(pageId.toStdString());
    if (!id) return;
    
    std::optional<Uuid> new_parent;
    if (!newParentId.isEmpty()) {
        new_parent = Uuid::parse(newParentId.toStdString());
    }
    
    // This is simplified - real implementation would need proper tree restructuring
    for (auto& page : pages_) {
        if (page.id == *id) {
            page = with_parent(page, new_parent);
            break;
        }
    }
    
    // Trigger full refresh for simplicity
    beginResetModel();
    endResetModel();
}

void PageTreeModel::archivePage(const QString& pageId) {
    auto id = Uuid::parse(pageId.toStdString());
    if (!id) return;
    
    for (auto& page : pages_) {
        if (page.id == *id) {
            page = with_archived(page, true);
            break;
        }
    }
    
    beginResetModel();
    endResetModel();
    emit pageCountChanged();
}

void PageTreeModel::deletePage(const QString& pageId) {
    auto id = Uuid::parse(pageId.toStdString());
    if (!id) return;
    
    auto it = std::find_if(pages_.begin(), pages_.end(),
        [&](const Page& p) { return p.id == *id; });
    
    if (it != pages_.end()) {
        int row = static_cast<int>(std::distance(pages_.begin(), it));
        beginRemoveRows(QModelIndex(), row, row);
        pages_.erase(it);
        endRemoveRows();
        emit pageCountChanged();
    }
}

std::vector<Page*> PageTreeModel::getChildren(const std::optional<Uuid>& parentId) {
    std::vector<Page*> children;
    for (auto& page : pages_) {
        if (page.parent_page_id == parentId && !page.is_archived) {
            children.push_back(&page);
        }
    }
    std::sort(children.begin(), children.end(),
        [](Page* a, Page* b) { return a->sort_order < b->sort_order; });
    return children;
}

Page* PageTreeModel::findPage(const Uuid& id) {
    for (auto& page : pages_) {
        if (page.id == id) {
            return &page;
        }
    }
    return nullptr;
}

int PageTreeModel::getPageIndex(const Uuid& id) const {
    for (size_t i = 0; i < pages_.size(); ++i) {
        if (pages_[i].id == id) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

} // namespace zinc::ui

