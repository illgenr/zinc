#include "ui/logging.hpp"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutex>
#include <QStandardPaths>
#include <QtGlobal>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace zinc::ui {
namespace {

QString compute_log_file_path() {
    const auto base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty()) {
        return QString{};
    }
    return QDir(base).filePath(QStringLiteral("logs/zinc.log"));
}

const char* level_tag(QtMsgType type) {
    switch (type) {
        case QtDebugMsg: return "D";
        case QtInfoMsg: return "I";
        case QtWarningMsg: return "W";
        case QtCriticalMsg: return "C";
        case QtFatalMsg: return "F";
    }
    return "?";
}

struct LoggerState {
    QMutex mu;
    QFile file;
    bool initialized = false;
};

LoggerState& state() {
    static LoggerState s{};
    return s;
}

void ensure_open(LoggerState& s) {
    if (s.initialized) return;
    s.initialized = true;

    const auto path = compute_log_file_path();
    if (path.isEmpty()) {
        return;
    }

    QDir dir(QFileInfo(path).absolutePath());
    dir.mkpath(QStringLiteral("."));

    s.file.setFileName(path);
    s.file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
}

void message_handler(QtMsgType type,
                     const QMessageLogContext& ctx,
                     const QString& msg) {
    auto& s = state();
    QMutexLocker lock(&s.mu);
    ensure_open(s);

    const auto ts = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    const auto cat = ctx.category ? QString::fromLatin1(ctx.category) : QStringLiteral("");

    const auto line = QStringLiteral("%1 %2 %3 %4\n")
                          .arg(ts, QString::fromLatin1(level_tag(type)), cat, msg);

    if (s.file.isOpen()) {
        s.file.write(line.toUtf8());
        s.file.flush();
    }

#ifdef Q_OS_WIN
    OutputDebugStringW(reinterpret_cast<const wchar_t*>(line.utf16()));
#endif
}

} // namespace

void install_file_logging() {
    // Keep the pattern stable; our message handler already stamps time/level/category.
    qSetMessagePattern(QStringLiteral("%{category} %{message}"));
    qInstallMessageHandler(message_handler);
}

QString default_log_file_path() {
    return compute_log_file_path();
}

} // namespace zinc::ui
