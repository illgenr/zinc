#include "ui/models/SearchResultModel.hpp"

namespace zinc::ui {

SearchResultModel::SearchResultModel(QObject* parent)
    : QAbstractListModel(parent)
{
}

int SearchResultModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return static_cast<int>(results_.size());
}

QVariant SearchResultModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= static_cast<int>(results_.size())) {
        return QVariant();
    }
    
    const auto& result = results_[index.row()];
    
    switch (role) {
        case BlockIdRole:
            return QString::fromStdString(result.block_id.to_string());
        case PageIdRole:
            return QString::fromStdString(result.page_id.to_string());
        case PageTitleRole:
            return QString::fromStdString(result.page_title);
        case SnippetRole:
            return QString::fromStdString(result.snippet);
        case RankRole:
            return result.rank;
        default:
            return QVariant();
    }
}

QHash<int, QByteArray> SearchResultModel::roleNames() const {
    return {
        {BlockIdRole, "blockId"},
        {PageIdRole, "pageId"},
        {PageTitleRole, "pageTitle"},
        {SnippetRole, "snippet"},
        {RankRole, "rank"}
    };
}

void SearchResultModel::setQuery(const QString& query) {
    if (query_ != query) {
        query_ = query;
        emit queryChanged();
        
        if (!query.isEmpty()) {
            search(query);
        } else {
            clear();
        }
    }
}

void SearchResultModel::search(const QString& query) {
    searching_ = true;
    emit searchingChanged();
    
    // In real implementation, this would query FTS5
    // For now, just clear and emit
    beginResetModel();
    results_.clear();
    endResetModel();
    
    searching_ = false;
    emit searchingChanged();
    emit resultCountChanged();
}

void SearchResultModel::clear() {
    beginResetModel();
    results_.clear();
    endResetModel();
    emit resultCountChanged();
}

} // namespace zinc::ui

