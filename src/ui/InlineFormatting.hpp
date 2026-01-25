#pragma once

#include <QObject>
#include <QJSEngine>
#include <QQmlEngine>
#include <QVariantMap>

namespace zinc::ui {

class InlineFormatting : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit InlineFormatting(QObject* parent = nullptr);

    static InlineFormatting* create(QQmlEngine* engine, QJSEngine*) {
        static InlineFormatting instance;
        if (engine) {
            QQmlEngine::setObjectOwnership(&instance, QQmlEngine::CppOwnership);
        }
        return &instance;
    }

    Q_INVOKABLE QVariantMap wrapSelection(const QString& text,
                                         int selectionStart,
                                         int selectionEnd,
                                         int cursorPosition,
                                         const QString& prefix,
                                         const QString& suffix,
                                         bool toggle) const;
};

} // namespace zinc::ui

