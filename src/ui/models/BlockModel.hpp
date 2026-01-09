#pragma once

#include "core/block_types.hpp"
#include <QAbstractListModel>
#include <QQmlEngine>
#include <vector>

namespace zinc::ui {

/**
 * BlockModel - Qt model for blocks in a page.
 * 
 * Provides block data to QML views with roles for:
 * - id, pageId, parentId
 * - type, content, properties
 * - sortOrder, depth
 */
class BlockModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString pageId READ pageId WRITE setPageId NOTIFY pageIdChanged)
    
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        PageIdRole,
        ParentIdRole,
        TypeRole,
        ContentRole,
        PropertiesRole,
        SortOrderRole,
        DepthRole,
        CheckedRole,      // For todo blocks
        LanguageRole,     // For code blocks
        CollapsedRole,    // For toggle blocks
        HeadingLevelRole  // For heading blocks
    };
    
    explicit BlockModel(QObject* parent = nullptr);
    
    // QAbstractListModel interface
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    bool setData(const QModelIndex& index, const QVariant& value, int role) override;
    QHash<int, QByteArray> roleNames() const override;
    Qt::ItemFlags flags(const QModelIndex& index) const override;
    
    // Properties
    [[nodiscard]] int count() const { return static_cast<int>(blocks_.size()); }
    [[nodiscard]] QString pageId() const;
    void setPageId(const QString& pageId);
    
    // Block operations
    Q_INVOKABLE void loadBlocks(const QString& pageId);
    Q_INVOKABLE void addBlock(const QString& type, int index = -1);
    Q_INVOKABLE void removeBlock(int index);
    Q_INVOKABLE void moveBlock(int fromIndex, int toIndex);
    Q_INVOKABLE void updateContent(int index, const QString& content);
    Q_INVOKABLE void transformBlock(int index, const QString& newType);
    Q_INVOKABLE void indentBlock(int index);
    Q_INVOKABLE void outdentBlock(int index);
    Q_INVOKABLE void toggleChecked(int index);
    Q_INVOKABLE void toggleCollapsed(int index);
    
    // Get block at index
    Q_INVOKABLE QString blockId(int index) const;
    Q_INVOKABLE QString blockType(int index) const;
    Q_INVOKABLE QString blockContent(int index) const;
    Q_INVOKABLE int blockDepth(int index) const;

signals:
    void countChanged();
    void pageIdChanged();
    void blockChanged(int index);
    void blocksLoaded();

private:
    std::vector<blocks::Block> blocks_;
    Uuid page_id_;
    
    void recalculateDepths();
    int calculateDepth(const blocks::Block& block) const;
};

} // namespace zinc::ui

