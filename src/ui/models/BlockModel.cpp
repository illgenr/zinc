#include "ui/models/BlockModel.hpp"

#include "ui/MarkdownBlocks.hpp"

#include <QUndoCommand>
#include <QVariantList>
#include <QUuid>
#include <algorithm>

namespace zinc::ui {

namespace {

struct ScopedUndoSuppression {
    BlockModel& model;
    explicit ScopedUndoSuppression(BlockModel& m) : model(m) { model.setUndoSuppressed(true); }
    ~ScopedUndoSuppression() { model.setUndoSuppressed(false); }
};

QString ensure_id(const QString& existing) {
    const auto trimmed = existing.trimmed();
    if (!trimmed.isEmpty()) return trimmed;
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

QString property_name_for_role(int role) {
    switch (role) {
        case BlockModel::BlockIdRole:
            return QStringLiteral("blockId");
        case BlockModel::BlockTypeRole:
            return QStringLiteral("blockType");
        case BlockModel::ContentRole:
            return QStringLiteral("content");
        case BlockModel::DepthRole:
            return QStringLiteral("depth");
        case BlockModel::CheckedRole:
            return QStringLiteral("checked");
        case BlockModel::CollapsedRole:
            return QStringLiteral("collapsed");
        case BlockModel::LanguageRole:
            return QStringLiteral("language");
        case BlockModel::HeadingLevelRole:
            return QStringLiteral("headingLevel");
        default:
            return {};
    }
}

QString predecessor_id_after_list_move(const std::vector<QString>& ids_in, int from, int to) {
    if (ids_in.empty()) return {};
    if (from < 0 || from >= static_cast<int>(ids_in.size())) return {};
    if (to < 0 || to >= static_cast<int>(ids_in.size())) return {};

    auto ids = ids_in;
    const auto moved = ids[static_cast<size_t>(from)];
    ids.erase(ids.begin() + from);
    ids.insert(ids.begin() + to, moved);

    const auto it = std::find(ids.begin(), ids.end(), moved);
    if (it == ids.end()) return {};
    const auto idx = static_cast<int>(std::distance(ids.begin(), it));
    if (idx <= 0) return {};
    return ids[static_cast<size_t>(idx - 1)];
}

class SetPropertyCommand final : public QUndoCommand {
public:
    SetPropertyCommand(BlockModel& model,
                       QString blockId,
                       QString property,
                       QVariant oldValue,
                       QVariant newValue)
        : model_(model),
          block_id_(std::move(blockId)),
          property_(std::move(property)),
          old_value_(std::move(oldValue)),
          new_value_(std::move(newValue))
    {
    }

    int id() const override { return 1; }

    bool mergeWith(const QUndoCommand* other) override {
        const auto* o = dynamic_cast<const SetPropertyCommand*>(other);
        if (!o) return false;
        if (o->block_id_ != block_id_) return false;
        if (o->property_ != property_) return false;
        if (property_ != QStringLiteral("content")) return false;
        new_value_ = o->new_value_;
        return true;
    }

    void undo() override { apply(old_value_); }
    void redo() override { apply(new_value_); }

private:
    BlockModel& model_;
    QString block_id_;
    QString property_;
    QVariant old_value_;
    QVariant new_value_;

    void apply(const QVariant& v) {
        const int idx = model_.indexForBlockId(block_id_);
        if (idx < 0) return;
        ScopedUndoSuppression guard(model_);
        model_.setProperty(idx, property_, v);
    }
};

class InsertBlockCommand final : public QUndoCommand {
public:
    InsertBlockCommand(BlockModel& model, int index, QVariantMap block)
        : model_(model),
          index_(index),
          block_(std::move(block))
    {
        block_id_ = block_.value(QStringLiteral("blockId")).toString();
    }

    void undo() override {
        const int idx = model_.indexForBlockId(block_id_);
        if (idx < 0) return;
        ScopedUndoSuppression guard(model_);
        model_.remove(idx, 1);
    }

    void redo() override {
        ScopedUndoSuppression guard(model_);
        model_.insert(index_, block_);
    }

private:
    BlockModel& model_;
    int index_;
    QVariantMap block_;
    QString block_id_;
};

class RemoveBlocksCommand final : public QUndoCommand {
public:
    RemoveBlocksCommand(BlockModel& model, int index, QList<QVariantMap> removed)
        : model_(model),
          index_(index),
          removed_(std::move(removed))
    {
    }

    void undo() override {
        ScopedUndoSuppression guard(model_);
        int at = std::max(0, std::min(index_, model_.count()));
        for (const auto& row : removed_) {
            model_.insert(at, row);
            ++at;
        }
    }

    void redo() override {
        ScopedUndoSuppression guard(model_);
        model_.remove(index_, removed_.size());
    }

private:
    BlockModel& model_;
    int index_;
    QList<QVariantMap> removed_;
};

class MoveBlockCommand final : public QUndoCommand {
public:
    MoveBlockCommand(BlockModel& model, QString blockId, QString redoPredecessor, QString undoPredecessor)
        : model_(model),
          block_id_(std::move(blockId)),
          redo_predecessor_(std::move(redoPredecessor)),
          undo_predecessor_(std::move(undoPredecessor))
    {
    }

    void undo() override { apply_after(undo_predecessor_); }
    void redo() override { apply_after(redo_predecessor_); }

private:
    BlockModel& model_;
    QString block_id_;
    QString redo_predecessor_;
    QString undo_predecessor_;

    void apply_after(const QString& predecessorId) {
        const int from = model_.indexForBlockId(block_id_);
        if (from < 0) return;

        int to = 0;
        if (!predecessorId.isEmpty()) {
            const int pred = model_.indexForBlockId(predecessorId);
            if (pred < 0) return;
            to = pred + 1;
            if (from < pred) {
                to = pred;
            }
            to = std::min(to, model_.count() - 1);
        }

        if (from == to) return;
        ScopedUndoSuppression guard(model_);
        model_.move(from, to, 1);
    }
};

} // namespace

BlockModel::BlockModel(QObject* parent)
    : QAbstractListModel(parent)
{
    connect(&undo_stack_, &QUndoStack::canUndoChanged, this, [this](bool) { emit canUndoChanged(); });
    connect(&undo_stack_, &QUndoStack::canRedoChanged, this, [this](bool) { emit canRedoChanged(); });
}

int BlockModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return static_cast<int>(blocks_.size());
}

QVariant BlockModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(blocks_.size())) {
        return {};
    }

    const auto& row = blocks_[static_cast<size_t>(index.row())];
    switch (role) {
        case BlockIdRole:
            return row.block_id;
        case BlockTypeRole:
            return row.block_type;
        case ContentRole:
            return row.content;
        case DepthRole:
            return row.depth;
        case CheckedRole:
            return row.checked;
        case CollapsedRole:
            return row.collapsed;
        case LanguageRole:
            return row.language;
        case HeadingLevelRole:
            return row.heading_level;
        default:
            return {};
    }
}

bool BlockModel::setData(const QModelIndex& index, const QVariant& value, int role) {
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(blocks_.size())) {
        return false;
    }

    if (!suppress_undo_) {
        const auto property = property_name_for_role(role);
        if (!property.isEmpty()) {
            const auto old_value = data(index, role);
            if (old_value == value) {
                return true;
            }
            const auto block_id = blocks_[static_cast<size_t>(index.row())].block_id;
            undo_stack_.push(new SetPropertyCommand(*this, block_id, property, old_value, value));
            return true;
        }
    }

    auto& row = blocks_[static_cast<size_t>(index.row())];
    switch (role) {
        case BlockIdRole:
            row.block_id = value.toString();
            break;
        case BlockTypeRole:
            row.block_type = value.toString();
            break;
        case ContentRole:
            row.content = value.toString();
            break;
        case DepthRole:
            row.depth = std::max(0, value.toInt());
            break;
        case CheckedRole:
            row.checked = value.toBool();
            break;
        case CollapsedRole:
            row.collapsed = value.toBool();
            break;
        case LanguageRole:
            row.language = value.toString();
            break;
        case HeadingLevelRole:
            row.heading_level = value.toInt();
            break;
        default:
            return false;
    }

    row = normalize(row);
    emit dataChanged(index, index, {role});
    emit blockChanged(index.row());
    return true;
}

QHash<int, QByteArray> BlockModel::roleNames() const {
    return {
        {BlockIdRole, "blockId"},
        {BlockTypeRole, "blockType"},
        {ContentRole, "content"},
        {DepthRole, "depth"},
        {CheckedRole, "checked"},
        {CollapsedRole, "collapsed"},
        {LanguageRole, "language"},
        {HeadingLevelRole, "headingLevel"},
    };
}

Qt::ItemFlags BlockModel::flags(const QModelIndex& index) const {
    if (!index.isValid()) return Qt::NoItemFlags;
    return Qt::ItemIsEnabled | Qt::ItemIsSelectable | Qt::ItemIsEditable;
}

void BlockModel::setPageId(const QString& pageId) {
    if (page_id_ == pageId) return;
    page_id_ = pageId;
    emit pageIdChanged();
}

void BlockModel::undo() {
    undo_stack_.undo();
}

void BlockModel::redo() {
    undo_stack_.redo();
}

void BlockModel::clearUndoStack() {
    undo_stack_.clear();
}

void BlockModel::beginUndoMacro(const QString& text) {
    undo_stack_.beginMacro(text);
}

void BlockModel::endUndoMacro() {
    undo_stack_.endMacro();
}

QVariantMap BlockModel::get(int index) const {
    if (index < 0 || index >= count()) return {};
    return toVariantMap(blocks_[static_cast<size_t>(index)]);
}

void BlockModel::setProperty(int index, const QString& property, const QVariant& value) {
    if (index < 0 || index >= count()) return;
    const int role = roleForPropertyName(property);
    if (role < 0) return;
    if (!suppress_undo_) {
        const auto old_value = data(createIndex(index, 0), role);
        if (old_value == value) return;
        const auto block_id = blocks_[static_cast<size_t>(index)].block_id;
        undo_stack_.push(new SetPropertyCommand(*this, block_id, property, old_value, value));
        return;
    }
    setData(createIndex(index, 0), value, role);
}

void BlockModel::insert(int index, const QVariantMap& block) {
    if (index < 0) index = 0;
    if (index > count()) index = count();

    auto row = normalize(fromVariantMap(block));
    row.block_id = ensure_id(row.block_id);

    if (!suppress_undo_) {
        auto map = toVariantMap(row);
        undo_stack_.push(new InsertBlockCommand(*this, index, map));
        return;
    }

    beginInsertRows(QModelIndex(), index, index);
    blocks_.insert(blocks_.begin() + index, std::move(row));
    endInsertRows();
    emit countChanged();
}

void BlockModel::append(const QVariantMap& block) {
    insert(count(), block);
}

void BlockModel::remove(int index, int countToRemove) {
    if (countToRemove <= 0) return;
    if (index < 0 || index >= count()) return;
    const int last = std::min(count() - 1, index + countToRemove - 1);

    if (!suppress_undo_) {
        QList<QVariantMap> removed;
        removed.reserve(last - index + 1);
        for (int i = index; i <= last; ++i) {
            removed.push_back(get(i));
        }
        undo_stack_.push(new RemoveBlocksCommand(*this, index, removed));
        return;
    }

    beginRemoveRows(QModelIndex(), index, last);
    blocks_.erase(blocks_.begin() + index, blocks_.begin() + last + 1);
    endRemoveRows();
    emit countChanged();
}

void BlockModel::move(int from, int to, int countToMove) {
    if (countToMove != 1) return;
    if (from < 0 || from >= count()) return;
    if (to < 0 || to >= count()) return;
    if (from == to) return;

    if (!suppress_undo_) {
        const auto& moved = blocks_[static_cast<size_t>(from)];
        std::vector<QString> ids;
        ids.reserve(blocks_.size());
        for (const auto& r : blocks_) ids.push_back(r.block_id);
        const auto undo_pred = (from > 0) ? blocks_[static_cast<size_t>(from - 1)].block_id : QString();
        const auto redo_pred = predecessor_id_after_list_move(ids, from, to);
        undo_stack_.push(new MoveBlockCommand(*this, moved.block_id, redo_pred, undo_pred));
        return;
    }

    const int destination = (to > from) ? (to + 1) : to;
    if (!beginMoveRows(QModelIndex(), from, from, QModelIndex(), destination)) {
        return;
    }
    auto row = std::move(blocks_[static_cast<size_t>(from)]);
    blocks_.erase(blocks_.begin() + from);
    const int insertAt = to;
    blocks_.insert(blocks_.begin() + insertAt, std::move(row));
    endMoveRows();
}

void BlockModel::clear() {
    undo_stack_.clear();
    if (blocks_.empty()) return;
    beginResetModel();
    blocks_.clear();
    endResetModel();
    emit countChanged();
}

bool BlockModel::loadFromMarkdown(const QString& markdown) {
    MarkdownBlocks codec;
    const auto parsed = codec.parse(markdown);
    if (parsed.isEmpty()) return false;

    undo_stack_.clear();
    std::vector<BlockRow> rows;
    rows.reserve(static_cast<size_t>(parsed.size()));
    for (const auto& entry : parsed) {
        auto row = normalize(fromVariantMap(entry.toMap()));
        row.block_id = ensure_id(row.block_id);
        rows.push_back(std::move(row));
    }

    beginResetModel();
    blocks_ = std::move(rows);
    endResetModel();
    emit countChanged();
    emit blocksLoaded();
    return true;
}

QString BlockModel::serializeContentToMarkdown() const {
    MarkdownBlocks codec;
    QVariantList list;
    list.reserve(count());
    for (const auto& row : blocks_) {
        list.append(toVariantMap(row));
    }
    return codec.serializeContent(list);
}

QString BlockModel::blockId(int index) const {
    if (index < 0 || index >= count()) return {};
    return blocks_[static_cast<size_t>(index)].block_id;
}

QString BlockModel::blockType(int index) const {
    if (index < 0 || index >= count()) return {};
    return blocks_[static_cast<size_t>(index)].block_type;
}

QString BlockModel::blockContent(int index) const {
    if (index < 0 || index >= count()) return {};
    return blocks_[static_cast<size_t>(index)].content;
}

int BlockModel::blockDepth(int index) const {
    if (index < 0 || index >= count()) return 0;
    return blocks_[static_cast<size_t>(index)].depth;
}

void BlockModel::addBlock(const QString& type, int index) {
    if (index < 0 || index > count()) {
        index = count();
    }
    insert(index, QVariantMap{
                      {QStringLiteral("blockId"), ensure_id(QString())},
                      {QStringLiteral("blockType"), type},
                      {QStringLiteral("content"), QString()},
                      {QStringLiteral("depth"), 0},
                      {QStringLiteral("checked"), false},
                      {QStringLiteral("collapsed"), false},
                      {QStringLiteral("language"), QString()},
                      {QStringLiteral("headingLevel"), 0},
                  });
}

void BlockModel::removeBlock(int index) {
    remove(index, 1);
}

void BlockModel::moveBlock(int fromIndex, int toIndex) {
    move(fromIndex, toIndex, 1);
}

void BlockModel::updateContent(int index, const QString& content) {
    setProperty(index, QStringLiteral("content"), content);
}

void BlockModel::transformBlock(int index, const QString& newType) {
    setProperty(index, QStringLiteral("blockType"), newType);
}

void BlockModel::indentBlock(int index) {
    if (index < 0 || index >= count()) return;
    const auto current = data(createIndex(index, 0), DepthRole).toInt();
    setData(createIndex(index, 0), current + 1, DepthRole);
}

void BlockModel::outdentBlock(int index) {
    if (index < 0 || index >= count()) return;
    const auto current = data(createIndex(index, 0), DepthRole).toInt();
    setData(createIndex(index, 0), std::max(0, current - 1), DepthRole);
}

void BlockModel::toggleChecked(int index) {
    if (index < 0 || index >= count()) return;
    const auto current = data(createIndex(index, 0), CheckedRole).toBool();
    setData(createIndex(index, 0), !current, CheckedRole);
}

void BlockModel::toggleCollapsed(int index) {
    if (index < 0 || index >= count()) return;
    const auto current = data(createIndex(index, 0), CollapsedRole).toBool();
    setData(createIndex(index, 0), !current, CollapsedRole);
}

BlockModel::BlockRow BlockModel::normalize(BlockRow row) {
    row.block_type = row.block_type.trimmed();
    if (row.block_type.isEmpty()) {
        row.block_type = QStringLiteral("paragraph");
    }
    row.block_id = ensure_id(row.block_id);
    row.depth = std::clamp(row.depth, 0, 64);
    row.heading_level = std::clamp(row.heading_level, 0, 6);

    if (row.block_type != QStringLiteral("todo")) row.checked = false;
    if (row.block_type != QStringLiteral("toggle")) row.collapsed = false;
    if (row.block_type != QStringLiteral("code")) row.language = QString();
    if (row.block_type != QStringLiteral("heading")) row.heading_level = 0;

    return row;
}

BlockModel::BlockRow BlockModel::fromVariantMap(const QVariantMap& map) {
    BlockRow row;
    row.block_id = map.value(QStringLiteral("blockId")).toString();
    row.block_type = map.value(QStringLiteral("blockType")).toString();
    row.content = map.value(QStringLiteral("content")).toString();
    row.depth = map.value(QStringLiteral("depth")).toInt();
    row.checked = map.value(QStringLiteral("checked")).toBool();
    row.collapsed = map.value(QStringLiteral("collapsed")).toBool();
    row.language = map.value(QStringLiteral("language")).toString();
    row.heading_level = map.value(QStringLiteral("headingLevel")).toInt();
    return row;
}

QVariantMap BlockModel::toVariantMap(const BlockRow& row) {
    return QVariantMap{
        {QStringLiteral("blockId"), row.block_id},
        {QStringLiteral("blockType"), row.block_type},
        {QStringLiteral("content"), row.content},
        {QStringLiteral("depth"), row.depth},
        {QStringLiteral("checked"), row.checked},
        {QStringLiteral("collapsed"), row.collapsed},
        {QStringLiteral("language"), row.language},
        {QStringLiteral("headingLevel"), row.heading_level},
    };
}

int BlockModel::roleForPropertyName(const QString& property) {
    if (property == QStringLiteral("blockId")) return BlockIdRole;
    if (property == QStringLiteral("blockType")) return BlockTypeRole;
    if (property == QStringLiteral("content")) return ContentRole;
    if (property == QStringLiteral("depth")) return DepthRole;
    if (property == QStringLiteral("checked")) return CheckedRole;
    if (property == QStringLiteral("collapsed")) return CollapsedRole;
    if (property == QStringLiteral("language")) return LanguageRole;
    if (property == QStringLiteral("headingLevel")) return HeadingLevelRole;
    return -1;
}

QString BlockModel::ensureId(const QString& blockId) {
    return ensure_id(blockId);
}

int BlockModel::indexForBlockId(const QString& blockId) const {
    if (blockId.isEmpty()) return -1;
    for (int i = 0; i < count(); ++i) {
        if (blocks_[static_cast<size_t>(i)].block_id == blockId) return i;
    }
    return -1;
}

} // namespace zinc::ui
