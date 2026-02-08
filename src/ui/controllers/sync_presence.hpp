#pragma once

#include <QByteArray>
#include <QString>
#include <QtGlobal>
#include <optional>

namespace zinc::ui {

struct SyncPresence {
    bool auto_sync_enabled = false;
    QString page_id;
    int block_index = -1;
    int cursor_pos = -1;
    QString title_preview;
    qint64 updated_at_ms = 0;
};

[[nodiscard]] std::optional<SyncPresence> parseSyncPresence(const QByteArray& payload);
[[nodiscard]] QByteArray serializeSyncPresence(const SyncPresence& presence);

} // namespace zinc::ui
