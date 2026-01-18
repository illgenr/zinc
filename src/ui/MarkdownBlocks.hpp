#pragma once

#include <QObject>
#include <QJSEngine>
#include <QQmlEngine>
#include <QVariantList>

namespace zinc::ui {

class MarkdownBlocks : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit MarkdownBlocks(QObject* parent = nullptr);

    static MarkdownBlocks* create(QQmlEngine* engine, QJSEngine*) {
        static MarkdownBlocks instance;
        if (engine) {
            QQmlEngine::setObjectOwnership(&instance, QQmlEngine::CppOwnership);
        }
        return &instance;
    }

    Q_INVOKABLE QString serialize(const QVariantList& blocks) const;
    Q_INVOKABLE QString serializeContent(const QVariantList& blocks) const;
    Q_INVOKABLE QVariantList parse(const QString& markdown) const;
    Q_INVOKABLE QVariantList parseWithSpans(const QString& markdown) const;
    Q_INVOKABLE bool isZincBlocksPayload(const QString& markdown) const;

    static QString headerLine();
};

} // namespace zinc::ui
