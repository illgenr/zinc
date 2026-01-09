#include "ui/controllers/EditorController.hpp"

namespace zinc::ui {

EditorController::EditorController(QObject* parent)
    : QObject(parent)
{
    // Initialize slash menu items
    updateSlashMenuItems();
}

void EditorController::setSelectedIndex(int index) {
    if (selected_index_ != index) {
        selected_index_ = index;
        emit selectedIndexChanged();
    }
}

QString EditorController::currentPageId() const {
    return block_model_.pageId();
}

void EditorController::setCurrentPageId(const QString& pageId) {
    block_model_.setPageId(pageId);
    selected_index_ = -1;
    emit currentPageIdChanged();
    emit selectedIndexChanged();
}

void EditorController::insertBlock(const QString& type, int index) {
    if (index < 0) {
        index = selected_index_ + 1;
    }
    
    block_model_.addBlock(type, index);
    setSelectedIndex(index);
    emit blockFocusRequested(index);
}

void EditorController::deleteBlock(int index) {
    if (index < 0) index = selected_index_;
    if (index < 0 || index >= block_model_.count()) return;
    
    block_model_.removeBlock(index);
    
    // Adjust selection
    if (selected_index_ >= block_model_.count()) {
        setSelectedIndex(block_model_.count() - 1);
    }
}

void EditorController::moveBlockUp(int index) {
    if (index < 0) index = selected_index_;
    if (index <= 0) return;
    
    block_model_.moveBlock(index, index - 1);
    setSelectedIndex(index - 1);
}

void EditorController::moveBlockDown(int index) {
    if (index < 0) index = selected_index_;
    if (index < 0 || index >= block_model_.count() - 1) return;
    
    block_model_.moveBlock(index, index + 2);
    setSelectedIndex(index + 1);
}

void EditorController::indentBlock(int index) {
    if (index < 0) index = selected_index_;
    block_model_.indentBlock(index);
}

void EditorController::outdentBlock(int index) {
    if (index < 0) index = selected_index_;
    block_model_.outdentBlock(index);
}

void EditorController::showSlashMenu(const QString& filter) {
    slash_filter_ = filter;
    updateSlashMenuItems();
    slash_menu_visible_ = true;
    emit slashMenuVisibleChanged();
}

void EditorController::hideSlashMenu() {
    if (slash_menu_visible_) {
        slash_menu_visible_ = false;
        emit slashMenuVisibleChanged();
    }
}

void EditorController::executeSlashCommand(int menuIndex) {
    if (menuIndex < 0 || menuIndex >= static_cast<int>(filtered_commands_.size())) {
        return;
    }
    
    const auto& cmd = filtered_commands_[menuIndex];
    auto content = cmd.create_content();
    
    // Transform current block or insert new one
    QString type = QString::fromStdString(std::string(
        blocks::type_name(blocks::get_type(content))));
    
    if (selected_index_ >= 0 && block_model_.blockContent(selected_index_).isEmpty()) {
        // Transform empty block
        block_model_.transformBlock(selected_index_, type);
    } else {
        // Insert new block
        insertBlock(type);
    }
    
    hideSlashMenu();
}

void EditorController::filterSlashMenu(const QString& filter) {
    slash_filter_ = filter;
    updateSlashMenuItems();
    emit slashMenuItemsChanged();
}

void EditorController::updateBlockContent(int index, const QString& content) {
    block_model_.updateContent(index, content);
    
    // Check for slash command
    if (content.startsWith('/') && !content.contains(' ')) {
        showSlashMenu(content);
    } else {
        hideSlashMenu();
    }
}

void EditorController::toggleTodo(int index) {
    if (index < 0) index = selected_index_;
    block_model_.toggleChecked(index);
}

void EditorController::toggleCollapse(int index) {
    if (index < 0) index = selected_index_;
    block_model_.toggleCollapsed(index);
}

void EditorController::selectNext() {
    if (selected_index_ < block_model_.count() - 1) {
        setSelectedIndex(selected_index_ + 1);
        emit blockFocusRequested(selected_index_);
    }
}

void EditorController::selectPrevious() {
    if (selected_index_ > 0) {
        setSelectedIndex(selected_index_ - 1);
        emit blockFocusRequested(selected_index_);
    }
}

void EditorController::focusBlock(int index) {
    if (index >= 0 && index < block_model_.count()) {
        setSelectedIndex(index);
        emit blockFocusRequested(index);
    }
}

void EditorController::updateSlashMenuItems() {
    filtered_commands_ = commands::CommandRegistry::filter(slash_filter_.toStdString());
    
    slash_menu_items_.clear();
    for (const auto& cmd : filtered_commands_) {
        slash_menu_items_.append(QString::fromStdString(cmd.label));
    }
    
    emit slashMenuItemsChanged();
}

} // namespace zinc::ui

