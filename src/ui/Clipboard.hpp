#pragma once

#include <QObject>
#include <QJSEngine>
#include <QQmlEngine>
#include <QString>

namespace zinc::ui {

class Clipboard : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Clipboard(QObject* parent = nullptr);

    static Clipboard* create(QQmlEngine*, QJSEngine*) {
        static Clipboard instance;
        return &instance;
    }

    Q_INVOKABLE QString text() const;
    Q_INVOKABLE void setText(const QString& text);
};

} // namespace zinc::ui
