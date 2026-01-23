#pragma once

#include <QAbstractListModel>
#include <QQmlEngine>
#include <QVariantMap>
#include <QUndoStack>
#include <vector>

namespace zinc::ui {

/**
 * BlockModel - QAbstractListModel backing the QML block editor.
 *
 * This intentionally mimics the subset of QML ListModel APIs used by
 * `qml/components/BlockEditor.qml` (get/append/insert/remove/move/setProperty/clear),
 * while also being a real Qt model suitable for ListView.
 *
 * Each row is a "block" with fields that match the MarkdownBlocks schema:
 * - blockId, blockType, content, depth, checked, collapsed, language, headingLevel
 */
class BlockModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QString pageId READ pageId WRITE setPageId NOTIFY pageIdChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY canUndoChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY canRedoChanged)
    
public:
    enum Roles {
        BlockIdRole = Qt::UserRole + 1,
        BlockTypeRole,
        ContentRole,
        DepthRole,
        CheckedRole,
        CollapsedRole,
        LanguageRole,
        HeadingLevelRole,
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
    [[nodiscard]] QString pageId() const { return page_id_; }
    void setPageId(const QString& pageId);
    [[nodiscard]] bool canUndo() const { return undo_stack_.canUndo(); }
    [[nodiscard]] bool canRedo() const { return undo_stack_.canRedo(); }

    // Undo/redo (Qt's undo framework, with merge support for typing)
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
    Q_INVOKABLE void clearUndoStack();
    Q_INVOKABLE void beginUndoMacro(const QString& text);
    Q_INVOKABLE void endUndoMacro();

    // Internal helpers for undo commands
    void setUndoSuppressed(bool suppressed) { suppress_undo_ = suppressed; }
    [[nodiscard]] bool undoSuppressed() const { return suppress_undo_; }
    [[nodiscard]] int indexForBlockId(const QString& blockId) const;
    
    // QML ListModel-like helpers used by BlockEditor.qml
    Q_INVOKABLE QVariantMap get(int index) const;
    Q_INVOKABLE void setProperty(int index, const QString& property, const QVariant& value);
    Q_INVOKABLE void insert(int index, const QVariantMap& block);
    Q_INVOKABLE void append(const QVariantMap& block);
    Q_INVOKABLE void remove(int index, int count = 1);
    Q_INVOKABLE void move(int from, int to, int count = 1);
    Q_INVOKABLE void clear();

    // Markdown (de)serialization helpers
    Q_INVOKABLE bool loadFromMarkdown(const QString& markdown);
    Q_INVOKABLE QString serializeContentToMarkdown() const;
    
    // Get block at index
    Q_INVOKABLE QString blockId(int index) const;
    Q_INVOKABLE QString blockType(int index) const;
    Q_INVOKABLE QString blockContent(int index) const;
    Q_INVOKABLE int blockDepth(int index) const;

    // Higher-level operations (EditorController-friendly)
    Q_INVOKABLE void addBlock(const QString& type, int index = -1);
    Q_INVOKABLE void removeBlock(int index);
    Q_INVOKABLE void moveBlock(int fromIndex, int toIndex);
    Q_INVOKABLE void updateContent(int index, const QString& content);
    Q_INVOKABLE void transformBlock(int index, const QString& newType);
    Q_INVOKABLE void indentBlock(int index);
    Q_INVOKABLE void outdentBlock(int index);
    Q_INVOKABLE void toggleChecked(int index);
    Q_INVOKABLE void toggleCollapsed(int index);

signals:
    void countChanged();
    void pageIdChanged();
    void canUndoChanged();
    void canRedoChanged();
    void blockChanged(int index);
    void blocksLoaded();

private:
    struct BlockRow {
        QString block_id;
        QString block_type;
        QString content;
        int depth = 0;
        bool checked = false;
        bool collapsed = false;
        QString language;
        int heading_level = 0;
    };

    QString page_id_;
    std::vector<BlockRow> blocks_;
    QUndoStack undo_stack_;
    bool suppress_undo_ = false;

    static BlockRow normalize(BlockRow row);
    static BlockRow fromVariantMap(const QVariantMap& map);
    static QVariantMap toVariantMap(const BlockRow& row);
    static int roleForPropertyName(const QString& property);
    static QString ensureId(const QString& blockId);
};

} // namespace zinc::ui
