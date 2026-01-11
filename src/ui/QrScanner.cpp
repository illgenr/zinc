#include "ui/QrScanner.hpp"
#include <QImage>

#ifdef ZINC_HAS_ZXING
#include <ZXing/BarcodeFormat.h>
#include <ZXing/DecodeHints.h>
#include <ZXing/ReadBarcode.h>
#endif

namespace zinc::ui {

QrScanner::QrScanner(QObject* parent)
    : QObject(parent) {
    last_scan_.invalidate();
}

void QrScanner::setVideoSink(QVideoSink* sink) {
    if (video_sink_ == sink) {
        return;
    }
    if (video_sink_) {
        disconnect(video_sink_, nullptr, this, nullptr);
    }
    video_sink_ = sink;
    if (video_sink_) {
        connect(video_sink_, &QVideoSink::videoFrameChanged,
                this, &QrScanner::onVideoFrameChanged);
    }
    emit videoSinkChanged();
}

void QrScanner::setActive(bool active) {
    if (active_ == active) {
        return;
    }
    active_ = active;
    if (!active_) {
        last_payload_.clear();
    }
    emit activeChanged();
}

void QrScanner::setScanIntervalMs(int interval_ms) {
    if (scan_interval_ms_ == interval_ms) {
        return;
    }
    scan_interval_ms_ = interval_ms;
    emit scanIntervalMsChanged();
}

void QrScanner::onVideoFrameChanged(const QVideoFrame& frame) {
    if (!active_ || decoding_) {
        return;
    }
    if (last_scan_.isValid() && last_scan_.elapsed() < scan_interval_ms_) {
        return;
    }

    if (!frame.isValid()) {
        return;
    }

    decoding_ = true;
    last_scan_.restart();

#ifdef ZINC_HAS_ZXING
    QImage image = frame.toImage();
    if (!image.isNull()) {
        QImage grayscale = image.convertToFormat(QImage::Format_Grayscale8);
        ZXing::ImageView view(
            grayscale.constBits(),
            grayscale.width(),
            grayscale.height(),
            ZXing::ImageFormat::Lum);

        auto hints = ZXing::DecodeHints()
            .setFormats(ZXing::BarcodeFormat::QR_CODE)
            .setTryRotate(true);

        auto result = ZXing::ReadBarcode(view, hints);
        if (result.isValid()) {
            QString payload = QString::fromStdString(result.text());
            if (!payload.isEmpty() && payload != last_payload_) {
                last_payload_ = payload;
                emit qrCodeDetected(payload);
            }
        }
    }
#else
    Q_UNUSED(frame)
    if (!warned_missing_backend_) {
        warned_missing_backend_ = true;
        emit error("QR scanning backend not available");
    }
#endif

    decoding_ = false;
}

} // namespace zinc::ui
