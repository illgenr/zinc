#pragma once

#include <QObject>
#include <QPointer>
#include <QVariantList>

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
    void scheduleApply();
    void applyNow();

    QPointer<QQuickTextDocument> m_document;
    QVariantList m_runs;
    bool m_apply_scheduled = false;

    class Impl;
    QPointer<Impl> m_impl;
};

} // namespace zinc::ui
