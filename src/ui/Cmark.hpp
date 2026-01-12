#pragma once

#include <QJSEngine>
#include <QObject>
#include <QQmlEngine>
#include <QString>

namespace zinc::ui {

class Cmark : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Cmark(QObject* parent = nullptr);

    static Cmark* create(QQmlEngine*, QJSEngine*) {
        static Cmark instance;
        return &instance;
    }

    Q_INVOKABLE QString toHtml(const QString& markdown) const;
};

} // namespace zinc::ui

