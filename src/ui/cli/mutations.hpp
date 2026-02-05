#pragma once

#include <QString>

#include "core/result.hpp"

namespace zinc::ui {

class DataStore;

struct CreateNotebookOptions {
    QString name;
};

struct DeleteNotebookOptions {
    QString notebookId;
    bool deletePages = false;
};

struct CreatePageOptions {
    QString title;
    QString notebookId;   // optional; ignored when parentPageId provided
    bool loose = false;   // forces notebookId=""
    QString parentPageId; // optional
};

struct DeletePageOptions {
    QString pageId;
};

[[nodiscard]] Result<QString> create_notebook(DataStore& store, const CreateNotebookOptions& options);
[[nodiscard]] Result<void> delete_notebook(DataStore& store, const DeleteNotebookOptions& options);
[[nodiscard]] Result<QString> create_page(DataStore& store, const CreatePageOptions& options);
[[nodiscard]] Result<void> delete_page(DataStore& store, const DeletePageOptions& options);

} // namespace zinc::ui

