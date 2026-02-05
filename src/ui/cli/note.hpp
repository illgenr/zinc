#pragma once

#include <QString>

#include "core/result.hpp"

namespace zinc::ui {

class DataStore;

struct NoteOptions {
    QString pageId;
    QString name;
    bool html = false;
};

[[nodiscard]] Result<QString> render_note(DataStore& store, const NoteOptions& options);

} // namespace zinc::ui

