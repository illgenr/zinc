#pragma once

#include "ui/models/BlockModel.hpp"
#include "core/commands.hpp"
#include <QObject>
#include <QQmlEngine>
#include <QStringList>

namespace zinc::ui {

/**
 * EditorController - Controller for the block editor.
 * 
 * Manages:
 * - Block model
 * - Slash command handling
 * - Selection state
 * - Undo/redo (future)
 */
class EditorController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(BlockModel* blockModel READ blockModel CONSTANT)
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)
    Q_PROPERTY(bool slashMenuVisible READ slashMenuVisible NOTIFY slashMenuVisibleChanged)
    Q_PROPERTY(QStringList slashMenuItems READ slashMenuItems NOTIFY slashMenuItemsChanged)
    Q_PROPERTY(QString currentPageId READ currentPageId WRITE setCurrentPageId NOTIFY currentPageIdChanged)
    
public:
    explicit EditorController(QObject* parent = nullptr);
    
    [[nodiscard]] BlockModel* blockModel() { return &block_model_; }
    [[nodiscard]] int selectedIndex() const { return selected_index_; }
    void setSelectedIndex(int index);
    [[nodiscard]] bool slashMenuVisible() const { return slash_menu_visible_; }
    [[nodiscard]] QStringList slashMenuItems() const { return slash_menu_items_; }
    [[nodiscard]] QString currentPageId() const;
    void setCurrentPageId(const QString& pageId);
    
    // Editor actions
    Q_INVOKABLE void insertBlock(const QString& type, int index = -1);
    Q_INVOKABLE void deleteBlock(int index);
    Q_INVOKABLE void moveBlockUp(int index);
    Q_INVOKABLE void moveBlockDown(int index);
    Q_INVOKABLE void indentBlock(int index);
    Q_INVOKABLE void outdentBlock(int index);
    
    // Slash commands
    Q_INVOKABLE void showSlashMenu(const QString& filter = QString());
    Q_INVOKABLE void hideSlashMenu();
    Q_INVOKABLE void executeSlashCommand(int menuIndex);
    Q_INVOKABLE void filterSlashMenu(const QString& filter);
    
    // Content editing
    Q_INVOKABLE void updateBlockContent(int index, const QString& content);
    Q_INVOKABLE void toggleTodo(int index);
    Q_INVOKABLE void toggleCollapse(int index);
    
    // Navigation
    Q_INVOKABLE void selectNext();
    Q_INVOKABLE void selectPrevious();
    Q_INVOKABLE void focusBlock(int index);

signals:
    void selectedIndexChanged();
    void slashMenuVisibleChanged();
    void slashMenuItemsChanged();
    void currentPageIdChanged();
    void blockFocusRequested(int index);

private:
    BlockModel block_model_;
    int selected_index_ = -1;
    bool slash_menu_visible_ = false;
    QStringList slash_menu_items_;
    QString slash_filter_;
    std::vector<commands::SlashCommand> filtered_commands_;
    
    void updateSlashMenuItems();
};

} // namespace zinc::ui

