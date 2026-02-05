#include "ui/cli/list_tree.hpp"

#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStringList>
#include <QVariantMap>

namespace zinc::ui {

namespace {

struct PageRow {
    QString pageId;
    QString notebookId;
    QString title;
    QString parentId;
};

[[nodiscard]] QString render_id_suffix(const QString& id, bool includeIds) {
    return includeIds ? (QStringLiteral(" (") + id + QStringLiteral(")")) : QString{};
}

[[nodiscard]] QString render_page_line(const PageRow& page, int depth, bool includeIds) {
    const auto indent = QString(depth * 2, QLatin1Char(' '));
    return indent + QStringLiteral("- ") + page.title + render_id_suffix(page.pageId, includeIds);
}

void render_subtree(QStringList& out,
                    const QHash<QString, QList<PageRow>>& childrenByParentId,
                    const QString& parentId,
                    int depth,
                    bool includeIds,
                    QSet<QString>& path) {
    const auto children = childrenByParentId.value(parentId);
    for (const auto& child : children) {
        out.append(render_page_line(child, depth, includeIds));
        if (path.contains(child.pageId)) {
            continue;
        }
        path.insert(child.pageId);
        render_subtree(out, childrenByParentId, child.pageId, depth + 1, includeIds, path);
        path.remove(child.pageId);
    }
}

[[nodiscard]] QList<PageRow> to_page_rows(const QVariantList& pages) {
    QList<PageRow> out;
    out.reserve(pages.size());
    for (const auto& entry : pages) {
        const auto m = entry.toMap();
        PageRow row;
        row.pageId = m.value(QStringLiteral("pageId")).toString();
        row.notebookId = m.value(QStringLiteral("notebookId")).toString();
        row.title = m.value(QStringLiteral("title")).toString();
        row.parentId = m.value(QStringLiteral("parentId")).toString();
        out.append(std::move(row));
    }
    return out;
}

[[nodiscard]] QHash<QString, QList<PageRow>> group_children_by_parent(const QList<PageRow>& pages) {
    QHash<QString, QList<PageRow>> childrenByParentId;
    for (const auto& page : pages) {
        childrenByParentId[page.parentId].append(page);
    }
    return childrenByParentId;
}

[[nodiscard]] QSet<QString> page_ids(const QList<PageRow>& pages) {
    QSet<QString> ids;
    ids.reserve(pages.size());
    for (const auto& p : pages) {
        ids.insert(p.pageId);
    }
    return ids;
}

[[nodiscard]] QList<PageRow> root_pages(const QList<PageRow>& pages) {
    const auto ids = page_ids(pages);
    QList<PageRow> roots;
    roots.reserve(pages.size());
    for (const auto& page : pages) {
        if (page.parentId.isEmpty() || !ids.contains(page.parentId)) {
            roots.append(page);
        }
    }
    return roots;
}

[[nodiscard]] QJsonObject page_to_json(const PageRow& page, bool includeIds) {
    QJsonObject obj;
    if (includeIds) {
        obj.insert(QStringLiteral("pageId"), page.pageId);
    }
    obj.insert(QStringLiteral("title"), page.title);
    obj.insert(QStringLiteral("children"), QJsonArray{});
    return obj;
}

[[nodiscard]] QJsonArray render_subtree_json(const QHash<QString, QList<PageRow>>& childrenByParentId,
                                             const QString& parentId,
                                             bool includeIds,
                                             QSet<QString>& path) {
    QJsonArray out;
    const auto children = childrenByParentId.value(parentId);

    for (const auto& child : children) {
        auto obj = page_to_json(child, includeIds);

        if (!path.contains(child.pageId)) {
            path.insert(child.pageId);
            obj.insert(QStringLiteral("children"),
                       render_subtree_json(childrenByParentId, child.pageId, includeIds, path));
            path.remove(child.pageId);
        }

        out.append(obj);
    }
    return out;
}

[[nodiscard]] QJsonArray pages_to_json_tree(const QList<PageRow>& pagesInNotebook, bool includeIds) {
    const auto childrenByParentId = group_children_by_parent(pagesInNotebook);
    const auto roots = root_pages(pagesInNotebook);

    QJsonArray rootsJson;

    QSet<QString> path;
    for (const auto& root : roots) {
        auto obj = page_to_json(root, includeIds);
        path.insert(root.pageId);
        obj.insert(QStringLiteral("children"),
                   render_subtree_json(childrenByParentId, root.pageId, includeIds, path));
        path.remove(root.pageId);
        rootsJson.append(obj);
    }

    return rootsJson;
}

void render_notebook(QStringList& out,
                     const QString& notebookTitle,
                     const QList<PageRow>& pagesInNotebook,
                     bool includeIds,
                     bool includeNotebookIds,
                     const QString& notebookId = {}) {
    out.append(notebookTitle + render_id_suffix(notebookId, includeNotebookIds));

    const auto childrenByParentId = group_children_by_parent(pagesInNotebook);
    const auto roots = root_pages(pagesInNotebook);

    QSet<QString> path;
    for (const auto& root : roots) {
        out.append(render_page_line(root, 1, includeIds));
        path.insert(root.pageId);
        render_subtree(out, childrenByParentId, root.pageId, 2, includeIds, path);
        path.remove(root.pageId);
    }
}

} // namespace

QString format_notebook_page_tree(const QVariantList& notebooks,
                                 const QVariantList& pages,
                                 const ListTreeOptions& options) {
    const auto allPages = to_page_rows(pages);

    QStringList out;

    // Keep input ordering stable: DataStore already orders by sort_order, created_at.
    for (const auto& entry : notebooks) {
        const auto nb = entry.toMap();
        const auto notebookId = nb.value(QStringLiteral("notebookId")).toString();
        const auto name = nb.value(QStringLiteral("name")).toString();

        QList<PageRow> pagesInNotebook;
        pagesInNotebook.reserve(allPages.size());
        for (const auto& page : allPages) {
            if (page.notebookId == notebookId) {
                pagesInNotebook.append(page);
            }
        }

        render_notebook(out, name, pagesInNotebook, options.includeIds, options.includeIds, notebookId);
    }

    if (options.includeLooseNotes) {
        QList<PageRow> loose;
        loose.reserve(allPages.size());
        for (const auto& page : allPages) {
            if (page.notebookId.isEmpty()) {
                loose.append(page);
            }
        }
        if (!loose.isEmpty()) {
            render_notebook(out, QStringLiteral("Loose Notes"), loose, options.includeIds, false);
        }
    }

    if (out.isEmpty()) {
        return {};
    }
    return out.join(QLatin1Char('\n')) + QLatin1Char('\n');
}

QString format_notebook_page_tree_json(const QVariantList& notebooks,
                                      const QVariantList& pages,
                                      const ListTreeOptions& options) {
    const auto allPages = to_page_rows(pages);

    QJsonArray notebooksJson;

    for (const auto& entry : notebooks) {
        const auto nb = entry.toMap();
        const auto notebookId = nb.value(QStringLiteral("notebookId")).toString();
        const auto name = nb.value(QStringLiteral("name")).toString();

        QList<PageRow> pagesInNotebook;
        pagesInNotebook.reserve(allPages.size());
        for (const auto& page : allPages) {
            if (page.notebookId == notebookId) {
                pagesInNotebook.append(page);
            }
        }

        QJsonObject notebookObj;
        if (options.includeIds) {
            notebookObj.insert(QStringLiteral("notebookId"), notebookId);
        }
        notebookObj.insert(QStringLiteral("name"), name);
        notebookObj.insert(QStringLiteral("pages"), pages_to_json_tree(pagesInNotebook, options.includeIds));
        notebooksJson.append(notebookObj);
    }

    QJsonObject root;
    root.insert(QStringLiteral("notebooks"), notebooksJson);

    if (options.includeLooseNotes) {
        QList<PageRow> loose;
        loose.reserve(allPages.size());
        for (const auto& page : allPages) {
            if (page.notebookId.isEmpty()) {
                loose.append(page);
            }
        }
        if (!loose.isEmpty()) {
            QJsonObject looseObj;
            looseObj.insert(QStringLiteral("pages"), pages_to_json_tree(loose, options.includeIds));
            root.insert(QStringLiteral("looseNotes"), looseObj);
        }
    }

    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact)) + QLatin1Char('\n');
}

} // namespace zinc::ui
