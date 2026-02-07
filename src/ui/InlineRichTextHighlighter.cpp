#include "ui/InlineRichTextHighlighter.hpp"

#include <QColor>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>
#include <QTextBlock>
#include <QTextCharFormat>
#include <QTextDocument>
#include <QMetaObject>

#include <algorithm>
#include <vector>

namespace zinc::ui {
namespace {

struct InlineAttrs {
    QString fontFamily;
    int fontPointSize = 0;
    QColor color;
    bool hasColor = false;
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strike = false;

    bool operator==(const InlineAttrs& o) const {
        return fontFamily == o.fontFamily && fontPointSize == o.fontPointSize && hasColor == o.hasColor &&
               (!hasColor || color == o.color) && bold == o.bold && italic == o.italic && underline == o.underline &&
               strike == o.strike;
    }
};

struct Run {
    int start = 0;
    int end = 0;
    InlineAttrs attrs;
};

InlineAttrs attrsFromVariantMap(const QVariantMap& m) {
    InlineAttrs a;
    a.fontFamily = m.value(QStringLiteral("fontFamily")).toString();
    a.fontPointSize = m.value(QStringLiteral("fontPointSize")).toInt();
    const auto colorStr = m.value(QStringLiteral("color")).toString();
    if (!colorStr.isEmpty()) {
        const QColor c(colorStr);
        if (c.isValid()) {
            a.color = c;
            a.hasColor = true;
        }
    }
    a.bold = m.value(QStringLiteral("bold")).toBool();
    a.italic = m.value(QStringLiteral("italic")).toBool();
    a.underline = m.value(QStringLiteral("underline")).toBool();
    a.strike = m.value(QStringLiteral("strike")).toBool();
    return a;
}

std::vector<Run> runsFromVariantList(const QVariantList& list) {
    std::vector<Run> out;
    out.reserve(static_cast<size_t>(list.size()));
    for (const auto& v : list) {
        const auto m = v.toMap();
        Run r;
        r.start = m.value(QStringLiteral("start")).toInt();
        r.end = m.value(QStringLiteral("end")).toInt();
        r.attrs = attrsFromVariantMap(m.value(QStringLiteral("attrs")).toMap());
        if (r.end > r.start) {
            out.push_back(std::move(r));
        }
    }
    std::sort(out.begin(), out.end(), [](const Run& a, const Run& b) { return a.start < b.start; });
    return out;
}

QTextCharFormat toFormat(const InlineAttrs& a) {
    QTextCharFormat f;
    if (!a.fontFamily.isEmpty()) f.setFontFamilies({a.fontFamily});
    if (a.fontPointSize > 0) f.setFontPointSize(a.fontPointSize);
    if (a.hasColor) f.setForeground(a.color);
    if (a.bold) f.setFontWeight(QFont::Bold);
    if (a.italic) f.setFontItalic(true);
    if (a.underline) f.setFontUnderline(true);
    if (a.strike) f.setFontStrikeOut(true);
    return f;
}

} // namespace

class InlineRichTextHighlighter::Impl final : public QSyntaxHighlighter {
public:
    explicit Impl(QTextDocument* doc)
        : QSyntaxHighlighter(doc) {}

    void setRuns(const QVariantList& runs) {
        m_runs = runsFromVariantList(runs);
        rehighlight();
    }

protected:
    void highlightBlock(const QString& text) override {
        if (m_runs.empty()) return;
        const int blockPos = currentBlock().position();
        const int blockEnd = blockPos + text.size();

        for (const auto& r : m_runs) {
            if (r.end <= blockPos) continue;
            if (r.start >= blockEnd) break;
            const int a = std::max(r.start, blockPos);
            const int b = std::min(r.end, blockEnd);
            if (b <= a) continue;
            setFormat(a - blockPos, b - a, toFormat(r.attrs));
        }
    }

private:
    std::vector<Run> m_runs;
};

InlineRichTextHighlighter::InlineRichTextHighlighter(QObject* parent)
    : QObject(parent) {}

InlineRichTextHighlighter::~InlineRichTextHighlighter() = default;

QQuickTextDocument* InlineRichTextHighlighter::document() const {
    return m_document;
}

void InlineRichTextHighlighter::setDocument(QQuickTextDocument* doc) {
    if (m_document == doc) return;
    m_document = doc;
    emit documentChanged();
    scheduleApply();
}

QVariantList InlineRichTextHighlighter::runs() const {
    return m_runs;
}

void InlineRichTextHighlighter::setRuns(const QVariantList& runs) {
    if (m_runs == runs) return;
    m_runs = runs;
    emit runsChanged();
    scheduleApply();
}

void InlineRichTextHighlighter::rebuildHighlighter() {
    if (m_impl) {
        m_impl->deleteLater();
        m_impl = nullptr;
    }
    if (!m_document) return;
    auto* doc = m_document->textDocument();
    if (!doc) return;
    m_impl = new Impl(doc);
    m_impl->setRuns(m_runs);
}

void InlineRichTextHighlighter::scheduleApply() {
    if (m_apply_scheduled) return;
    m_apply_scheduled = true;
    QMetaObject::invokeMethod(this, [this]() { applyNow(); }, Qt::QueuedConnection);
}

void InlineRichTextHighlighter::applyNow() {
    m_apply_scheduled = false;

    if (!m_document) {
        if (m_impl) {
            m_impl->deleteLater();
            m_impl = nullptr;
        }
        return;
    }

    auto* doc = m_document->textDocument();
    if (!doc) {
        if (m_impl) {
            m_impl->deleteLater();
            m_impl = nullptr;
        }
        return;
    }

    if (!m_impl || m_impl->document() != doc) {
        rebuildHighlighter();
        return;
    }

    m_impl->setRuns(m_runs);
}

} // namespace zinc::ui
