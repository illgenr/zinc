#pragma once

#include <QObject>
#include <QJSEngine>
#include <QQmlEngine>
#include <QString>
#include <QUrl>

namespace zinc::ui {

class Clipboard : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Clipboard(QObject* parent = nullptr);

    static Clipboard* create(QQmlEngine* engine, QJSEngine*) {
        static Clipboard instance;
        if (engine) {
            QQmlEngine::setObjectOwnership(&instance, QQmlEngine::CppOwnership);
        }
        return &instance;
    }

    Q_INVOKABLE QString text() const;
    Q_INVOKABLE void setText(const QString& text);

    Q_INVOKABLE bool hasImage() const;
    Q_INVOKABLE QString saveClipboardImage();
    Q_INVOKABLE QString importImageFile(const QUrl& fileUrl);
};

} // namespace zinc::ui
