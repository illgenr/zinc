#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>

#include <memory>

#include <QQuickTextDocument>
class QTextDocument;

namespace zinc::ui {

class InlineRichTextHighlighter : public QObject {
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument* document READ document WRITE setDocument NOTIFY documentChanged)
    Q_PROPERTY(QVariantList runs READ runs WRITE setRuns NOTIFY runsChanged)

public:
    explicit InlineRichTextHighlighter(QObject* parent = nullptr);
    ~InlineRichTextHighlighter() override;

    QQuickTextDocument* document() const;
    void setDocument(QQuickTextDocument* doc);

    QVariantList runs() const;
    void setRuns(const QVariantList& runs);

signals:
    void documentChanged();
    void runsChanged();

private:
    void rebuildHighlighter();
    void rehighlight();

    QPointer<QQuickTextDocument> m_document;
    QVariantList m_runs;

    class Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace zinc::ui
