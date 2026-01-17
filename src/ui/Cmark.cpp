#include "ui/Cmark.hpp"

#include <cmark.h>
#include <QRegularExpression>
#include <QStringBuilder>

namespace zinc::ui {

Cmark::Cmark(QObject* parent)
    : QObject(parent) {
}

QString Cmark::toHtml(const QString& markdown) const {
    if (markdown.isEmpty()) {
        return QString();
    }

    const auto utf8 = markdown.toUtf8();
    char* html = cmark_markdown_to_html(utf8.constData(),
                                        static_cast<size_t>(utf8.size()),
                                        CMARK_OPT_DEFAULT | CMARK_OPT_HARDBREAKS);
    if (!html) {
        return QString();
    }

    QString out = QString::fromUtf8(html);
    free(html);

    static const QRegularExpression isoDateOrDateTime(
        QStringLiteral(R"(\b(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2}(?::\d{2})?))?\b)"));

    const auto transformText = [](const QString& text) -> QString {
        QString outText;
        outText.reserve(text.size());
        int last = 0;

        auto it = isoDateOrDateTime.globalMatch(text);
        while (it.hasNext()) {
            const auto m = it.next();
            outText += text.mid(last, m.capturedStart(0) - last);
            const auto date = m.captured(1);
            const auto time = m.captured(2);
            const auto value = time.isEmpty() ? date : (date % QLatin1Char('T') % time);
            const auto label = time.isEmpty() ? date : (date % QLatin1Char(' ') % time);
            outText += QStringLiteral("<a href=\"zinc://date/%1\" style=\"color:#888888; text-decoration:none;\">%2</a>")
                           .arg(value.toHtmlEscaped(), label.toHtmlEscaped());
            last = m.capturedEnd(0);
        }
        outText += text.mid(last);
        return outText;
    };

    QString rebuilt;
    rebuilt.reserve(out.size());
    int i = 0;
    while (i < out.size()) {
        const int tagStart = out.indexOf(QLatin1Char('<'), i);
        if (tagStart < 0) {
            rebuilt += transformText(out.mid(i));
            break;
        }
        rebuilt += transformText(out.mid(i, tagStart - i));
        const int tagEnd = out.indexOf(QLatin1Char('>'), tagStart);
        if (tagEnd < 0) {
            rebuilt += out.mid(tagStart);
            break;
        }
        rebuilt += out.mid(tagStart, tagEnd - tagStart + 1);
        i = tagEnd + 1;
    }
    out = std::move(rebuilt);

    return out;
}

} // namespace zinc::ui
