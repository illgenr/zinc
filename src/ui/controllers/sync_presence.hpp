#pragma once

#include <QByteArray>
#include <QString>
#include <optional>

namespace zinc::ui {

struct SyncPresence {
    bool auto_sync_enabled = false;
    QString page_id;
    int block_index = -1;
    int cursor_pos = -1;
};

[[nodiscard]] std::optional<SyncPresence> parseSyncPresence(const QByteArray& payload);
[[nodiscard]] QByteArray serializeSyncPresence(const SyncPresence& presence);

} // namespace zinc::ui

