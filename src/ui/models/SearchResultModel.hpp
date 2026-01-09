#pragma once

#include "core/search.hpp"
#include <QAbstractListModel>
#include <QQmlEngine>
#include <vector>

namespace zinc::ui {

/**
 * SearchResultModel - Model for full-text search results.
 */
class SearchResultModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(int resultCount READ resultCount NOTIFY resultCountChanged)
    Q_PROPERTY(bool searching READ isSearching NOTIFY searchingChanged)
    
public:
    enum Roles {
        BlockIdRole = Qt::UserRole + 1,
        PageIdRole,
        PageTitleRole,
        SnippetRole,
        RankRole
    };
    
    explicit SearchResultModel(QObject* parent = nullptr);
    
    // QAbstractListModel interface
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    
    // Properties
    [[nodiscard]] QString query() const { return query_; }
    void setQuery(const QString& query);
    [[nodiscard]] int resultCount() const { return static_cast<int>(results_.size()); }
    [[nodiscard]] bool isSearching() const { return searching_; }
    
    // Search
    Q_INVOKABLE void search(const QString& query);
    Q_INVOKABLE void clear();

signals:
    void queryChanged();
    void resultCountChanged();
    void searchingChanged();
    void resultSelected(const QString& pageId, const QString& blockId);

private:
    QString query_;
    std::vector<SearchResult> results_;
    bool searching_ = false;
};

} // namespace zinc::ui

