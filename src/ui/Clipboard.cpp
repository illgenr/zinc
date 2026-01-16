#include "ui/Clipboard.hpp"

#include <QClipboard>
#include <QGuiApplication>
#include <QFile>
#include <QImage>
#include <QImageReader>
#include <QMimeData>
#include <QBuffer>
#include <QDebug>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <QtCore/qnativeinterface.h>
#endif

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

QImage downscale_image(QImage image, int maxDim) {
    if (image.isNull()) return image;
    if (maxDim <= 0) return image;
    const int w = image.width();
    const int h = image.height();
    if (w <= maxDim && h <= maxDim) return image;
    return image.scaled(maxDim, maxDim, Qt::KeepAspectRatio, Qt::SmoothTransformation);
}

QString image_to_data_url(const QImage& image) {
    if (image.isNull()) return {};

    const auto scaled = downscale_image(image, 1600);

    const bool alpha = scaled.hasAlphaChannel();
    const char* format = alpha ? "PNG" : "JPG";
    const QString mime = alpha ? QStringLiteral("image/png") : QStringLiteral("image/jpeg");

    QByteArray bytes;
    QBuffer buffer(&bytes);
    if (!buffer.open(QIODevice::WriteOnly)) return {};

    if (alpha) {
        if (!scaled.save(&buffer, format)) return {};
    } else {
        if (!scaled.save(&buffer, format, 85)) return {};
    }

    return QStringLiteral("data:%1;base64,%2")
        .arg(mime, QString::fromLatin1(bytes.toBase64()));
}

} // namespace

QString Clipboard::saveClipboardImage() {
    auto* clipboard = QGuiApplication::clipboard();
    if (!clipboard) return {};
    const auto* mime = clipboard->mimeData();
    if (!mime || !mime->hasImage()) return {};

    const QImage image = clipboard->image();
    return image_to_data_url(image);
}

namespace {

std::optional<QImage> read_image_from_device(QIODevice& device) {
    QImageReader reader(&device);
    reader.setAutoTransform(true);
    const auto image = reader.read();
    if (image.isNull()) {
        if (!reader.errorString().isEmpty()) {
            qWarning() << "Clipboard: failed to decode image:" << reader.errorString();
        }
        return std::nullopt;
    }
    return image;
}

#ifdef Q_OS_ANDROID
std::optional<QByteArray> read_content_uri_bytes_android(const QString& uriString) {
    QJniObject context(QNativeInterface::QAndroidApplication::context());
    if (!context.isValid()) return std::nullopt;

    auto uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri",
        "parse",
        "(Ljava/lang/String;)Landroid/net/Uri;",
        QJniObject::fromString(uriString).object<jstring>());
    if (!uri.isValid()) return std::nullopt;

    auto resolver = context.callObjectMethod(
        "getContentResolver",
        "()Landroid/content/ContentResolver;");
    if (!resolver.isValid()) return std::nullopt;

    auto inputStream = resolver.callObjectMethod(
        "openInputStream",
        "(Landroid/net/Uri;)Ljava/io/InputStream;",
        uri.object<jobject>());
    if (!inputStream.isValid()) return std::nullopt;

    QJniEnvironment env;
    constexpr int kChunkSize = 8192;
    auto buffer = env->NewByteArray(kChunkSize);
    if (!buffer) return std::nullopt;

    QByteArray out;
    for (;;) {
        const jint readCount = inputStream.callMethod<jint>("read", "([B)I", buffer);
        if (readCount <= 0) break;
        QByteArray chunk;
        chunk.resize(readCount);
        env->GetByteArrayRegion(buffer, 0, readCount, reinterpret_cast<jbyte*>(chunk.data()));
        out.append(chunk);
    }

    inputStream.callMethod<void>("close");
    env->DeleteLocalRef(buffer);

    if (out.isEmpty()) return std::nullopt;
    return out;
}
#endif

std::optional<QImage> read_image_from_url(const QUrl& url) {
    if (!url.isValid()) return std::nullopt;

    if (url.isLocalFile()) {
        QImageReader reader(url.toLocalFile());
        reader.setAutoTransform(true);
        const auto image = reader.read();
        if (image.isNull()) {
            if (!reader.errorString().isEmpty()) {
                qWarning() << "Clipboard: failed to decode local image:" << reader.errorString();
            }
            return std::nullopt;
        }
        return image;
    }

    const auto asString = url.toString();
    QFile f(asString);
    if (f.open(QIODevice::ReadOnly)) {
        return read_image_from_device(f);
    }

#ifdef Q_OS_ANDROID
    if (url.scheme() == QStringLiteral("content")) {
        const auto bytes = read_content_uri_bytes_android(asString);
        if (!bytes) return std::nullopt;
        QBuffer buffer;
        buffer.setData(*bytes);
        if (!buffer.open(QIODevice::ReadOnly)) return std::nullopt;
        return read_image_from_device(buffer);
    }
#endif

    return std::nullopt;
}

} // namespace

QString Clipboard::importImageFile(const QUrl& fileUrl) {
    const auto image = read_image_from_url(fileUrl);
    if (!image) {
        qWarning() << "Clipboard: Failed to import image url=" << fileUrl;
        return {};
    }
    return image_to_data_url(*image);
}

} // namespace zinc::ui
