#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

#include <QQmlEngine>

namespace zinc::ui {

class InlineRichText : public QObject {
    Q_OBJECT

public:
    explicit InlineRichText(QObject* parent = nullptr);

    static InlineRichText* create(QQmlEngine* engine, QJSEngine*) {
        static InlineRichText instance;
        if (engine) {
            QQmlEngine::setObjectOwnership(&instance, QQmlEngine::CppOwnership);
        }
        return &instance;
    }

    Q_INVOKABLE QVariantMap parse(const QString& markup) const;
    Q_INVOKABLE QString serialize(const QString& text, const QVariantList& runs) const;

    // Keeps run positions in sync with edits to plain text.
    // Expects a single contiguous edit, which matches typical TextEdit mutations.
    Q_INVOKABLE QVariantMap reconcileTextChange(const QString& beforeText,
                                                const QString& afterText,
                                                const QVariantList& runs,
                                                const QVariantMap& typingAttrs,
                                                int cursorPosition) const;

    Q_INVOKABLE QVariantMap applyFormat(const QString& text,
                                        const QVariantList& runs,
                                        int selectionStart,
                                        int selectionEnd,
                                        int cursorPosition,
                                        const QVariantMap& format,
                                        const QVariantMap& typingAttrs) const;

    Q_INVOKABLE QVariantMap attrsAt(const QVariantList& runs, int pos) const;
};

} // namespace zinc::ui
