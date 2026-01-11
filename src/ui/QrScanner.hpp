#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVideoSink>
#include <QVideoFrame>
#include <QElapsedTimer>

namespace zinc::ui {

/**
 * QrScanner - QML helper to decode QR codes from a VideoSink stream.
 */
class QrScanner : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
    Q_PROPERTY(bool active READ isActive WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(int scanIntervalMs READ scanIntervalMs WRITE setScanIntervalMs NOTIFY scanIntervalMsChanged)

public:
    explicit QrScanner(QObject* parent = nullptr);

    [[nodiscard]] QVideoSink* videoSink() const { return video_sink_; }
    void setVideoSink(QVideoSink* sink);

    [[nodiscard]] bool isActive() const { return active_; }
    void setActive(bool active);

    [[nodiscard]] int scanIntervalMs() const { return scan_interval_ms_; }
    void setScanIntervalMs(int interval_ms);

signals:
    void videoSinkChanged();
    void activeChanged();
    void scanIntervalMsChanged();
    void qrCodeDetected(const QString& payload);
    void error(const QString& message);

private slots:
    void onVideoFrameChanged(const QVideoFrame& frame);

private:
    QVideoSink* video_sink_ = nullptr;
    bool active_ = false;
    int scan_interval_ms_ = 250;
    bool decoding_ = false;
    bool warned_missing_backend_ = false;
    QElapsedTimer last_scan_;
    QString last_payload_;
};

} // namespace zinc::ui
