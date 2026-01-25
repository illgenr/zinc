#include "ui/Cmark.hpp"

#include <cmark.h>
#include <QRegularExpression>
#include <QStringBuilder>
#include <QHash>

namespace zinc::ui {

namespace {

bool startsWithInsensitive(const QStringView s, const QStringView prefix) {
    if (s.size() < prefix.size()) return false;
    return QStringView(s.data(), prefix.size()).compare(prefix, Qt::CaseInsensitive) == 0;
}

QString lower(const QStringView s) {
    QString out;
    out.reserve(s.size());
    for (const auto ch : s) {
        out.append(ch.toLower());
    }
    return out;
}

bool isAllowedTagName(const QStringView name) {
    const auto n = lower(name);
    static const QSet<QString> allowed = {
        QStringLiteral("p"),  QStringLiteral("br"),   QStringLiteral("em"),  QStringLiteral("strong"),
        QStringLiteral("code"), QStringLiteral("pre"), QStringLiteral("blockquote"),
        QStringLiteral("ul"), QStringLiteral("ol"),   QStringLiteral("li"),
        QStringLiteral("h1"), QStringLiteral("h2"),   QStringLiteral("h3"),
        QStringLiteral("hr"),
        QStringLiteral("a"),  QStringLiteral("img"),
        QStringLiteral("span"), QStringLiteral("u"), QStringLiteral("s"), QStringLiteral("del"),
    };
    return allowed.contains(n);
}

bool isStripElement(const QStringView name) {
    const auto n = lower(name);
    return n == QStringLiteral("script") || n == QStringLiteral("style");
}

bool isSafeHref(const QStringView href) {
    const auto h = href.trimmed();
    if (startsWithInsensitive(h, QStringView(u"javascript:"))) return false;
    if (startsWithInsensitive(h, QStringView(u"vbscript:"))) return false;
    if (startsWithInsensitive(h, QStringView(u"data:"))) return false;
    return startsWithInsensitive(h, QStringView(u"zinc://")) ||
           startsWithInsensitive(h, QStringView(u"http://")) ||
           startsWithInsensitive(h, QStringView(u"https://")) ||
           startsWithInsensitive(h, QStringView(u"mailto:")) ||
           startsWithInsensitive(h, QStringView(u"file://"));
}

bool isSafeImgSrc(const QStringView src) {
    const auto s = src.trimmed();
    return startsWithInsensitive(s, QStringView(u"image://attachments/")) ||
           startsWithInsensitive(s, QStringView(u"file://")) ||
           startsWithInsensitive(s, QStringView(u"qrc:/")) ||
           startsWithInsensitive(s, QStringView(u"data:image/"));
}

QString sanitizeStyleValue(const QStringView value) {
    // Drop anything that could reference external resources.
    if (value.contains(QStringLiteral("url("), Qt::CaseInsensitive)) return QString();
    return value.toString().trimmed();
}

QString sanitizeStyle(const QStringView styleText) {
    // Whitelist a small CSS subset used by our inline formatting features.
    static const QSet<QString> allowedProps = {
        QStringLiteral("color"),
        QStringLiteral("background-color"),
        QStringLiteral("font-family"),
        QStringLiteral("font-size"),
        QStringLiteral("font-style"),
        QStringLiteral("font-weight"),
        QStringLiteral("text-decoration"),
    };

    const auto raw = styleText.toString();
    const auto decls = raw.split(QLatin1Char(';'), Qt::SkipEmptyParts);
    QStringList kept;
    kept.reserve(decls.size());

    for (const auto& decl : decls) {
        const int colon = decl.indexOf(QLatin1Char(':'));
        if (colon <= 0) continue;
        const auto prop = decl.left(colon).trimmed().toLower();
        if (!allowedProps.contains(prop)) continue;
        const auto val = sanitizeStyleValue(QStringView(decl).mid(colon + 1));
        if (val.isEmpty()) continue;
        kept.append(prop + QStringLiteral(":") + val);
    }

    if (kept.isEmpty()) return QString();
    return kept.join(QStringLiteral(";")) + QLatin1Char(';');
}

QHash<QString, QString> parseAttributes(const QStringView attrs) {
    QHash<QString, QString> out;
    int i = 0;
    const int n = attrs.size();
    while (i < n) {
        while (i < n && attrs[i].isSpace()) i++;
        if (i >= n) break;

        int keyStart = i;
        while (i < n && !attrs[i].isSpace() && attrs[i] != QLatin1Char('=') && attrs[i] != QLatin1Char('>')) i++;
        const auto keyView = attrs.mid(keyStart, i - keyStart).trimmed();
        if (keyView.isEmpty()) break;
        const auto key = lower(keyView);

        while (i < n && attrs[i].isSpace()) i++;
        if (i >= n || attrs[i] != QLatin1Char('=')) {
            // Boolean attribute; ignore for safety.
            continue;
        }
        i++; // '='
        while (i < n && attrs[i].isSpace()) i++;
        if (i >= n) break;

        QString value;
        const QChar quote = attrs[i];
        if (quote == QLatin1Char('"') || quote == QLatin1Char('\'')) {
            i++;
            const int valStart = i;
            while (i < n && attrs[i] != quote) i++;
            value = attrs.mid(valStart, i - valStart).toString();
            if (i < n && attrs[i] == quote) i++;
        } else {
            const int valStart = i;
            while (i < n && !attrs[i].isSpace() && attrs[i] != QLatin1Char('>')) i++;
            value = attrs.mid(valStart, i - valStart).toString();
        }

        out.insert(key, value);
    }
    return out;
}

QString buildAllowedTag(const QStringView tagName, const QHash<QString, QString>& attrs, bool closing, bool selfClosing) {
    const auto nameLower = lower(tagName);
    if (!isAllowedTagName(nameLower)) return QString();

    if (closing) {
        return QStringLiteral("</") + nameLower + QLatin1Char('>');
    }

    QString out = QStringLiteral("<") + nameLower;

    auto addAttr = [&out](const QString& k, const QString& v) {
        out += QLatin1Char(' ');
        out += k;
        out += QStringLiteral("=\"");
        out += v.toHtmlEscaped();
        out += QLatin1Char('"');
    };

    if (nameLower == QStringLiteral("a")) {
        const auto href = attrs.value(QStringLiteral("href"));
        if (!href.isEmpty() && isSafeHref(QStringView(href))) addAttr(QStringLiteral("href"), href);
        const auto title = attrs.value(QStringLiteral("title"));
        if (!title.isEmpty()) addAttr(QStringLiteral("title"), title);
        const auto style = sanitizeStyle(QStringView(attrs.value(QStringLiteral("style"))));
        if (!style.isEmpty()) addAttr(QStringLiteral("style"), style);
    } else if (nameLower == QStringLiteral("img")) {
        const auto src = attrs.value(QStringLiteral("src"));
        if (src.isEmpty() || !isSafeImgSrc(QStringView(src))) {
            return QString(); // drop unsafe images entirely
        }
        addAttr(QStringLiteral("src"), src);
        const auto alt = attrs.value(QStringLiteral("alt"));
        if (!alt.isEmpty()) addAttr(QStringLiteral("alt"), alt);
        const auto title = attrs.value(QStringLiteral("title"));
        if (!title.isEmpty()) addAttr(QStringLiteral("title"), title);
        const auto width = attrs.value(QStringLiteral("width"));
        if (!width.isEmpty()) addAttr(QStringLiteral("width"), width);
        const auto height = attrs.value(QStringLiteral("height"));
        if (!height.isEmpty()) addAttr(QStringLiteral("height"), height);
    } else if (nameLower == QStringLiteral("span")) {
        const auto style = sanitizeStyle(QStringView(attrs.value(QStringLiteral("style"))));
        if (!style.isEmpty()) addAttr(QStringLiteral("style"), style);
    }

    out += selfClosing ? QStringLiteral("/>") : QStringLiteral(">");
    return out;
}

QString sanitizeHtmlForNotes(const QString& html) {
    QString out;
    out.reserve(html.size());

    int i = 0;
    while (i < html.size()) {
        const int tagStart = html.indexOf(QLatin1Char('<'), i);
        if (tagStart < 0) {
            out += html.mid(i);
            break;
        }

        out += html.mid(i, tagStart - i);

        const int tagEnd = html.indexOf(QLatin1Char('>'), tagStart);
        if (tagEnd < 0) {
            out += html.mid(tagStart);
            break;
        }

        const auto tagInner = QStringView(html).mid(tagStart + 1, tagEnd - tagStart - 1).trimmed();
        if (tagInner.startsWith(QLatin1Char('!')) || tagInner.startsWith(QLatin1Char('?'))) {
            i = tagEnd + 1;
            continue;
        }

        bool closing = false;
        int p = 0;
        if (p < tagInner.size() && tagInner[p] == QLatin1Char('/')) {
            closing = true;
            p++;
        }
        while (p < tagInner.size() && tagInner[p].isSpace()) p++;
        const int nameStart = p;
        while (p < tagInner.size() && (tagInner[p].isLetterOrNumber() || tagInner[p] == QLatin1Char('-'))) p++;
        const auto nameView = tagInner.mid(nameStart, p - nameStart);
        const auto nameLower = lower(nameView);

        // Strip <script>/<style> blocks entirely (including contents).
        if (!closing && isStripElement(nameLower)) {
            const QString closeNeedle = QStringLiteral("</") + nameLower + QLatin1Char('>');
            const int closePos = html.indexOf(closeNeedle, tagEnd + 1, Qt::CaseInsensitive);
            if (closePos < 0) {
                i = tagEnd + 1;
                continue;
            }
            i = closePos + closeNeedle.size();
            continue;
        }

        const bool selfClosing = (!closing && tagInner.endsWith(QLatin1Char('/')));
        const auto attrsView = (!closing && p < tagInner.size()) ? tagInner.mid(p) : QStringView();

        const auto attrs = closing ? QHash<QString, QString>() : parseAttributes(attrsView);
        const auto rebuilt = buildAllowedTag(nameLower, attrs, closing, selfClosing);
        if (!rebuilt.isEmpty()) {
            out += rebuilt;
        }

        i = tagEnd + 1;
    }

    return out;
}

} // namespace

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
                                        CMARK_OPT_DEFAULT | CMARK_OPT_HARDBREAKS | CMARK_OPT_UNSAFE);
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

    return sanitizeHtmlForNotes(out);
}

} // namespace zinc::ui
