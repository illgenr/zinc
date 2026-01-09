#include "ui/models/BlockModel.hpp"

namespace zinc::ui {

BlockModel::BlockModel(QObject* parent)
    : QAbstractListModel(parent)
{
}

int BlockModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return static_cast<int>(blocks_.size());
}

QVariant BlockModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= static_cast<int>(blocks_.size())) {
        return QVariant();
    }
    
    const auto& block = blocks_[index.row()];
    
    switch (role) {
        case IdRole:
            return QString::fromStdString(block.id.to_string());
        case PageIdRole:
            return QString::fromStdString(block.page_id.to_string());
        case ParentIdRole:
            return block.parent_id 
                ? QString::fromStdString(block.parent_id->to_string())
                : QString();
        case TypeRole:
            return QString::fromStdString(std::string(
                blocks::type_name(blocks::get_type(block.content))));
        case ContentRole:
            return QString::fromStdString(blocks::get_text(block.content));
        case SortOrderRole:
            return QString::fromStdString(block.sort_order.value());
        case DepthRole:
            return calculateDepth(block);
        case CheckedRole:
            if (auto* todo = std::get_if<blocks::Todo>(&block.content)) {
                return todo->checked;
            }
            return false;
        case LanguageRole:
            if (auto* code = std::get_if<blocks::Code>(&block.content)) {
                return QString::fromStdString(code->language);
            }
            return QString();
        case CollapsedRole:
            if (auto* toggle = std::get_if<blocks::Toggle>(&block.content)) {
                return toggle->collapsed;
            }
            return false;
        case HeadingLevelRole:
            if (auto* heading = std::get_if<blocks::Heading>(&block.content)) {
                return heading->level;
            }
            return 0;
        default:
            return QVariant();
    }
}

bool BlockModel::setData(const QModelIndex& index, const QVariant& value, int role) {
    if (!index.isValid() || index.row() >= static_cast<int>(blocks_.size())) {
        return false;
    }
    
    auto& block = blocks_[index.row()];
    
    switch (role) {
        case ContentRole: {
            auto new_content = blocks::with_text(block.content, 
                value.toString().toStdString());
            block = blocks::with_content(block, new_content);
            emit dataChanged(index, index, {role});
            return true;
        }
        case CheckedRole: {
            if (auto* todo = std::get_if<blocks::Todo>(&block.content)) {
                block = blocks::with_content(block, 
                    blocks::Todo{value.toBool(), todo->markdown});
                emit dataChanged(index, index, {role});
                return true;
            }
            return false;
        }
        case CollapsedRole: {
            if (auto* toggle = std::get_if<blocks::Toggle>(&block.content)) {
                block = blocks::with_content(block,
                    blocks::Toggle{value.toBool(), toggle->summary});
                emit dataChanged(index, index, {role});
                return true;
            }
            return false;
        }
        default:
            return false;
    }
}

QHash<int, QByteArray> BlockModel::roleNames() const {
    return {
        {IdRole, "blockId"},
        {PageIdRole, "pageId"},
        {ParentIdRole, "parentId"},
        {TypeRole, "blockType"},
        {ContentRole, "content"},
        {SortOrderRole, "sortOrder"},
        {DepthRole, "depth"},
        {CheckedRole, "checked"},
        {LanguageRole, "language"},
        {CollapsedRole, "collapsed"},
        {HeadingLevelRole, "headingLevel"}
    };
}

Qt::ItemFlags BlockModel::flags(const QModelIndex& index) const {
    if (!index.isValid()) return Qt::NoItemFlags;
    return Qt::ItemIsEnabled | Qt::ItemIsSelectable | Qt::ItemIsEditable;
}

QString BlockModel::pageId() const {
    return QString::fromStdString(page_id_.to_string());
}

void BlockModel::setPageId(const QString& pageId) {
    auto parsed = Uuid::parse(pageId.toStdString());
    if (parsed) {
        page_id_ = *parsed;
        loadBlocks(pageId);
        emit pageIdChanged();
    }
}

void BlockModel::loadBlocks(const QString& pageId) {
    // In real implementation, this would load from storage
    // For now, just emit loaded signal
    beginResetModel();
    blocks_.clear();
    
    auto parsed = Uuid::parse(pageId.toStdString());
    if (parsed) {
        page_id_ = *parsed;
    }
    
    endResetModel();
    emit countChanged();
    emit blocksLoaded();
}

void BlockModel::addBlock(const QString& type, int index) {
    auto block_type = blocks::parse_type(type.toStdString());
    if (!block_type) return;
    
    blocks::BlockContent content;
    switch (*block_type) {
        case blocks::BlockType::Paragraph:
            content = blocks::Paragraph{""};
            break;
        case blocks::BlockType::Heading:
            content = blocks::Heading{1, ""};
            break;
        case blocks::BlockType::Todo:
            content = blocks::Todo{false, ""};
            break;
        case blocks::BlockType::Code:
            content = blocks::Code{"", ""};
            break;
        case blocks::BlockType::Quote:
            content = blocks::Quote{""};
            break;
        case blocks::BlockType::Divider:
            content = blocks::Divider{};
            break;
        case blocks::BlockType::Toggle:
            content = blocks::Toggle{true, ""};
            break;
    }
    
    // Calculate sort order
    FractionalIndex sort_order;
    if (index < 0 || index >= static_cast<int>(blocks_.size())) {
        // Add at end
        index = static_cast<int>(blocks_.size());
        if (blocks_.empty()) {
            sort_order = FractionalIndex::first();
        } else {
            sort_order = blocks_.back().sort_order.after();
        }
    } else {
        // Insert at index
        FractionalIndex before = (index > 0) ? blocks_[index - 1].sort_order : FractionalIndex{};
        FractionalIndex after = blocks_[index].sort_order;
        sort_order = FractionalIndex::between(before, after);
    }
    
    auto block = blocks::create(
        Uuid::generate(),
        page_id_,
        content,
        sort_order
    );
    
    beginInsertRows(QModelIndex(), index, index);
    blocks_.insert(blocks_.begin() + index, block);
    endInsertRows();
    
    emit countChanged();
}

void BlockModel::removeBlock(int index) {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return;
    
    beginRemoveRows(QModelIndex(), index, index);
    blocks_.erase(blocks_.begin() + index);
    endRemoveRows();
    
    emit countChanged();
}

void BlockModel::moveBlock(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= static_cast<int>(blocks_.size())) return;
    if (toIndex < 0 || toIndex > static_cast<int>(blocks_.size())) return;
    if (fromIndex == toIndex) return;
    
    // Calculate new sort order
    FractionalIndex before = (toIndex > 0) ? blocks_[toIndex - 1].sort_order : FractionalIndex{};
    FractionalIndex after = (toIndex < static_cast<int>(blocks_.size())) 
        ? blocks_[toIndex].sort_order : FractionalIndex{};
    
    auto new_order = FractionalIndex::between(before, after);
    
    if (!beginMoveRows(QModelIndex(), fromIndex, fromIndex, QModelIndex(), 
                       toIndex > fromIndex ? toIndex + 1 : toIndex)) {
        return;
    }
    
    auto block = blocks_[fromIndex];
    blocks_.erase(blocks_.begin() + fromIndex);
    
    if (toIndex > fromIndex) --toIndex;
    
    block = blocks::with_sort_order(block, new_order);
    blocks_.insert(blocks_.begin() + toIndex, block);
    
    endMoveRows();
}

void BlockModel::updateContent(int index, const QString& content) {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return;
    
    setData(createIndex(index, 0), content, ContentRole);
}

void BlockModel::transformBlock(int index, const QString& newType) {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return;
    
    auto block_type = blocks::parse_type(newType.toStdString());
    if (!block_type) return;
    
    auto result = blocks::transform_to(blocks_[index], *block_type);
    if (result) {
        blocks_[index] = *result;
        emit dataChanged(createIndex(index, 0), createIndex(index, 0));
    }
}

void BlockModel::indentBlock(int index) {
    if (index <= 0 || index >= static_cast<int>(blocks_.size())) return;
    
    // Find previous sibling to become parent
    const auto& prev = blocks_[index - 1];
    blocks_[index] = blocks::with_parent(blocks_[index], prev.id);
    
    emit dataChanged(createIndex(index, 0), createIndex(index, 0), {DepthRole, ParentIdRole});
}

void BlockModel::outdentBlock(int index) {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return;
    
    auto& block = blocks_[index];
    if (!block.parent_id) return;
    
    // Find parent's parent
    std::optional<Uuid> grandparent;
    for (const auto& b : blocks_) {
        if (b.id == *block.parent_id) {
            grandparent = b.parent_id;
            break;
        }
    }
    
    blocks_[index] = blocks::with_parent(block, grandparent);
    emit dataChanged(createIndex(index, 0), createIndex(index, 0), {DepthRole, ParentIdRole});
}

void BlockModel::toggleChecked(int index) {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return;
    
    auto& block = blocks_[index];
    if (auto* todo = std::get_if<blocks::Todo>(&block.content)) {
        setData(createIndex(index, 0), !todo->checked, CheckedRole);
    }
}

void BlockModel::toggleCollapsed(int index) {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return;
    
    auto& block = blocks_[index];
    if (auto* toggle = std::get_if<blocks::Toggle>(&block.content)) {
        setData(createIndex(index, 0), !toggle->collapsed, CollapsedRole);
    }
}

QString BlockModel::blockId(int index) const {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return QString();
    return QString::fromStdString(blocks_[index].id.to_string());
}

QString BlockModel::blockType(int index) const {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return QString();
    return QString::fromStdString(std::string(
        blocks::type_name(blocks::get_type(blocks_[index].content))));
}

QString BlockModel::blockContent(int index) const {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return QString();
    return QString::fromStdString(blocks::get_text(blocks_[index].content));
}

int BlockModel::blockDepth(int index) const {
    if (index < 0 || index >= static_cast<int>(blocks_.size())) return 0;
    return calculateDepth(blocks_[index]);
}

int BlockModel::calculateDepth(const blocks::Block& block) const {
    int depth = 0;
    auto current_parent = block.parent_id;
    
    while (current_parent) {
        ++depth;
        auto it = std::find_if(blocks_.begin(), blocks_.end(),
            [&](const blocks::Block& b) { return b.id == *current_parent; });
        
        if (it == blocks_.end()) break;
        current_parent = it->parent_id;
    }
    
    return depth;
}

} // namespace zinc::ui

