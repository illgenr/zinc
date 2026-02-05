#pragma once

#include <QString>
#include <QVariantList>

namespace zinc::ui {

struct ListTreeOptions {
    bool includeIds = false;
    bool includeLooseNotes = true;
};

// Pure-ish formatter: consumes notebook + page rows (as returned by DataStore) and returns a stable tree.
[[nodiscard]] QString format_notebook_page_tree(const QVariantList& notebooks,
                                                const QVariantList& pages,
                                                const ListTreeOptions& options = {});

// JSON output:
// {
//   "notebooks": [{ "notebookId"?, "name", "pages": [ ... ] }],
//   "looseNotes"?: { "pages": [ ... ] }
// }
[[nodiscard]] QString format_notebook_page_tree_json(const QVariantList& notebooks,
                                                     const QVariantList& pages,
                                                     const ListTreeOptions& options = {});

} // namespace zinc::ui
