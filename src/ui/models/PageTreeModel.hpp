#pragma once

#include "core/page.hpp"
#include <QAbstractItemModel>
#include <QQmlEngine>
#include <vector>

namespace zinc::ui {

/**
 * PageTreeModel - Qt tree model for page hierarchy.
 */
class PageTreeModel : public QAbstractItemModel {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(QString workspaceId READ workspaceId WRITE setWorkspaceId NOTIFY workspaceIdChanged)
    Q_PROPERTY(int pageCount READ pageCount NOTIFY pageCountChanged)
    
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        ParentIdRole,
        SortOrderRole,
        IsArchivedRole,
        DepthRole
    };
    
    explicit PageTreeModel(QObject* parent = nullptr);
    
    // QAbstractItemModel interface
    QModelIndex index(int row, int column, const QModelIndex& parent = QModelIndex()) const override;
    QModelIndex parent(const QModelIndex& child) const override;
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    int columnCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    
    // Properties
    [[nodiscard]] QString workspaceId() const;
    void setWorkspaceId(const QString& id);
    [[nodiscard]] int pageCount() const { return static_cast<int>(pages_.size()); }
    
    // Page operations
    Q_INVOKABLE void loadPages();
    Q_INVOKABLE QString createPage(const QString& title, const QString& parentId = QString());
    Q_INVOKABLE void renamePage(const QString& pageId, const QString& newTitle);
    Q_INVOKABLE void movePage(const QString& pageId, const QString& newParentId);
    Q_INVOKABLE void archivePage(const QString& pageId);
    Q_INVOKABLE void deletePage(const QString& pageId);
    
signals:
    void workspaceIdChanged();
    void pageCountChanged();
    void pageSelected(const QString& pageId);

private:
    std::vector<Page> pages_;
    Uuid workspace_id_;
    
    [[nodiscard]] std::vector<Page*> getChildren(const std::optional<Uuid>& parentId);
    [[nodiscard]] Page* findPage(const Uuid& id);
    [[nodiscard]] int getPageIndex(const Uuid& id) const;
};

} // namespace zinc::ui

