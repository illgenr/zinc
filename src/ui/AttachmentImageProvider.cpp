#include "ui/AttachmentImageProvider.hpp"

#include <QImage>
#include <QImageReader>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QStandardPaths>
#include <QDebug>

namespace zinc::ui {

Q_LOGGING_CATEGORY(zincAttachmentsLog, "zinc.attachments")

AttachmentImageProvider::AttachmentImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image) {
}

namespace {

QString resolve_attachments_dir() {
    const auto overrideDir = qEnvironmentVariable("ZINC_ATTACHMENTS_DIR");
    if (!overrideDir.isEmpty()) {
        QDir dir(overrideDir);
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        return dir.absolutePath();
    }

    const auto overrideDb = qEnvironmentVariable("ZINC_DB_PATH");
    if (!overrideDb.isEmpty()) {
        QFileInfo info(overrideDb);
        QDir dir(info.absolutePath() + "/attachments");
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        return dir.absolutePath();
    }

    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir dir(dataPath + "/attachments");
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dir.absolutePath();
}

QString normalize_attachment_id(QString id) {
    if (id.startsWith('/')) id.remove(0, 1);
    const auto queryIndex = id.indexOf('?');
    if (queryIndex >= 0) id = id.left(queryIndex);
    return id;
}

bool is_safe_attachment_id(const QString& id) {
    if (id.isEmpty()) return false;
    if (id.contains('/') || id.contains('\\')) return false;
    return true;
}

} // namespace

QImage AttachmentImageProvider::requestImage(const QString& id,
                                             QSize* size,
                                             const QSize& requestedSize) {
    QImage out;

    if (qEnvironmentVariableIsSet("ZINC_DEBUG_ATTACHMENTS")) {
        qInfo() << "AttachmentImageProvider: requestImage id=" << id << "requestedSize=" << requestedSize;
    } else {
        qCDebug(zincAttachmentsLog) << "requestImage id=" << id << "requestedSize=" << requestedSize;
    }

    const auto normalizedId = normalize_attachment_id(id);
    if (!is_safe_attachment_id(normalizedId)) {
        qWarning() << "AttachmentImageProvider: Unsafe attachment id=" << id;
        if (size) *size = out.size();
        return out;
    }

    const auto path = resolve_attachments_dir() + "/" + normalizedId;
    QFile f(path);
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) {
        qWarning() << "AttachmentImageProvider: Missing attachment file id=" << normalizedId << "path=" << path;
        if (size) *size = out.size();
        return out;
    }

    QImageReader reader(&f);
    reader.setAutoTransform(true);

    if (qEnvironmentVariableIsSet("ZINC_DEBUG_ATTACHMENTS")) {
        qInfo() << "AttachmentImageProvider: format=" << reader.format() << "originalSize=" << reader.size();
    } else {
        qCDebug(zincAttachmentsLog) << "requestImage format=" << reader.format() << "originalSize=" << reader.size();
    }

    if (requestedSize.isValid()) {
        const auto originalSize = reader.size();
        if (originalSize.isValid() && originalSize.width() > 0 && originalSize.height() > 0) {
            auto target = originalSize;
            target.scale(requestedSize, Qt::KeepAspectRatio);
            if (target.isValid()) {
                reader.setScaledSize(target);
            }
        } else {
            reader.setScaledSize(requestedSize);
        }
    }

    out = reader.read();
    if (out.isNull()) {
        qWarning() << "AttachmentImageProvider: Failed to decode image id=" << id
                   << "error=" << reader.errorString()
                   << "path=" << path;
    } else {
        if (qEnvironmentVariableIsSet("ZINC_DEBUG_ATTACHMENTS")) {
            qInfo() << "AttachmentImageProvider: decodedSize=" << out.size() << "id=" << id;
        } else {
            qCDebug(zincAttachmentsLog) << "requestImage decodedSize=" << out.size() << "id=" << id;
        }
    }

    if (size) *size = out.size();
    return out;
}

} // namespace zinc::ui
