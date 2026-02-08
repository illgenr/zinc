#include "ui/controllers/sync_presence.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>

namespace zinc::ui {

std::optional<SyncPresence> parseSyncPresence(const QByteArray& payload) {
    if (payload.isEmpty()) {
        return std::nullopt;
    }

    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(payload, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        return std::nullopt;
    }

    const auto obj = doc.object();
    SyncPresence out;
    out.auto_sync_enabled = obj.value(QStringLiteral("autoSyncEnabled")).toBool(false);
    out.page_id = obj.value(QStringLiteral("pageId")).toString();
    out.block_index = obj.value(QStringLiteral("blockIndex")).toInt(-1);
    out.cursor_pos = obj.value(QStringLiteral("cursorPos")).toInt(-1);
    out.title_preview = obj.value(QStringLiteral("titlePreview")).toString();
    return out;
}

QByteArray serializeSyncPresence(const SyncPresence& presence) {
    QJsonObject obj;
    obj.insert(QStringLiteral("autoSyncEnabled"), presence.auto_sync_enabled);
    obj.insert(QStringLiteral("pageId"), presence.page_id);
    obj.insert(QStringLiteral("blockIndex"), presence.block_index);
    obj.insert(QStringLiteral("cursorPos"), presence.cursor_pos);
    obj.insert(QStringLiteral("titlePreview"), presence.title_preview);
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

} // namespace zinc::ui
