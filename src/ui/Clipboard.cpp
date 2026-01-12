#include "ui/Clipboard.hpp"

#include <QClipboard>
#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QStandardPaths>
#include <QUuid>

namespace zinc::ui {

Clipboard::Clipboard(QObject* parent)
    : QObject(parent) {
}

QString Clipboard::text() const {
    if (auto* clipboard = QGuiApplication::clipboard()) {
        return clipboard->text();
    }
    return {};
}

void Clipboard::setText(const QString& text) {
    if (auto* clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(text);
    }
}

bool Clipboard::hasImage() const {
    auto* clipboard = QGuiApplication::clipboard();
    if (!clipboard) return false;
    const auto* mime = clipboard->mimeData();
    if (!mime) return false;
    return mime->hasImage();
}

namespace {

QString ensure_attachments_dir() {
    const QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir dir(dataPath);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    const QString attachments = dir.filePath(QStringLiteral("attachments"));
    QDir attachmentsDir(attachments);
    if (!attachmentsDir.exists()) {
        attachmentsDir.mkpath(".");
    }
    return attachments;
}

QString save_image_to_attachments(const QImage& image, const QString& preferredExt) {
    if (image.isNull()) return {};

    const auto dir = ensure_attachments_dir();
    const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const auto ext = preferredExt.isEmpty() ? QStringLiteral("png") : preferredExt;
    const auto filename = QStringLiteral("%1.%2").arg(id, ext);
    const auto path = QDir(dir).filePath(filename);

    QByteArray format = ext.toUtf8();
    if (!image.save(path, format.constData())) {
        // Fallback to png.
        const auto pngPath = QDir(dir).filePath(QStringLiteral("%1.png").arg(id));
        if (!image.save(pngPath, "PNG")) {
            return {};
        }
        return QUrl::fromLocalFile(pngPath).toString();
    }
    return QUrl::fromLocalFile(path).toString();
}

} // namespace

QString Clipboard::saveClipboardImage() {
    auto* clipboard = QGuiApplication::clipboard();
    if (!clipboard) return {};
    const auto* mime = clipboard->mimeData();
    if (!mime || !mime->hasImage()) return {};

    const QImage image = clipboard->image();
    return save_image_to_attachments(image, QStringLiteral("png"));
}

QString Clipboard::importImageFile(const QUrl& fileUrl) {
    if (!fileUrl.isValid() || !fileUrl.isLocalFile()) return {};

    const QString srcPath = fileUrl.toLocalFile();
    if (srcPath.isEmpty()) return {};

    QImage image(srcPath);
    if (image.isNull()) return {};

    QFileInfo info(srcPath);
    const auto ext = info.suffix().toLower();
    return save_image_to_attachments(image, ext.isEmpty() ? QStringLiteral("png") : ext);
}

} // namespace zinc::ui
