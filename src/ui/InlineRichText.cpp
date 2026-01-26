#include "ui/InlineRichText.hpp"

#include <QColor>
#include <QRegularExpression>
#include <QStringBuilder>

#include <cmath>
#include <algorithm>

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

QVariantMap attrsToVariantMap(const InlineAttrs& a) {
    QVariantMap m;
    if (!a.fontFamily.isEmpty()) {
        m.insert(QStringLiteral("fontFamily"), a.fontFamily);
    }
    if (a.fontPointSize > 0) {
        m.insert(QStringLiteral("fontPointSize"), a.fontPointSize);
    }
    if (a.hasColor) {
        m.insert(QStringLiteral("color"), a.color.name(QColor::HexRgb));
    }
    if (a.bold) {
        m.insert(QStringLiteral("bold"), true);
    }
    if (a.italic) {
        m.insert(QStringLiteral("italic"), true);
    }
    if (a.underline) {
        m.insert(QStringLiteral("underline"), true);
    }
    if (a.strike) {
        m.insert(QStringLiteral("strike"), true);
    }
    return m;
}

QVariantMap runToVariantMap(const Run& r) {
    QVariantMap m;
    m.insert(QStringLiteral("start"), r.start);
    m.insert(QStringLiteral("end"), r.end);
    m.insert(QStringLiteral("attrs"), attrsToVariantMap(r.attrs));
    return m;
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

QVariantList runsToVariantList(const std::vector<Run>& runs) {
    QVariantList out;
    out.reserve(static_cast<int>(runs.size()));
    for (const auto& r : runs) {
        out.push_back(runToVariantMap(r));
    }
    return out;
}

std::vector<Run> normalizeRuns(const std::vector<Run>& runs, int textLen) {
    const auto clamp = [](int v, int lo, int hi) { return std::max(lo, std::min(v, hi)); };

    std::vector<Run> out;
    out.reserve(runs.size() + 1);

    int pos = 0;
    InlineAttrs empty;
    for (const auto& r0 : runs) {
        const int a = clamp(r0.start, 0, textLen);
        const int b = clamp(r0.end, 0, textLen);
        if (b <= a) {
            continue;
        }
        if (a > pos) {
            out.push_back(Run{pos, a, empty});
        }
        if (!out.empty() && out.back().end == a && out.back().attrs == r0.attrs) {
            out.back().end = b;
        } else {
            out.push_back(Run{a, b, r0.attrs});
        }
        pos = b;
    }
    if (pos < textLen) {
        if (!out.empty() && out.back().end == pos && out.back().attrs == empty) {
            out.back().end = textLen;
        } else {
            out.push_back(Run{pos, textLen, empty});
        }
    }

    // Merge any adjacent equals (can happen after clamping).
    std::vector<Run> merged;
    merged.reserve(out.size());
    for (const auto& r : out) {
        if (r.end <= r.start) continue;
        if (!merged.empty() && merged.back().end == r.start && merged.back().attrs == r.attrs) {
            merged.back().end = r.end;
        } else {
            merged.push_back(r);
        }
    }
    return merged;
}

InlineAttrs attrsAtPos(const std::vector<Run>& runs, int pos) {
    if (runs.empty()) return InlineAttrs{};
    const int p = std::max(0, pos);
    auto it = std::upper_bound(runs.begin(), runs.end(), p, [](int value, const Run& r) { return value < r.start; });
    if (it == runs.begin()) {
        return runs.front().attrs;
    }
    --it;
    if (p >= it->start && p < it->end) {
        return it->attrs;
    }
    return runs.front().attrs;
}

struct Diff {
    int start = 0;
    int removedLen = 0;
    int insertedLen = 0;
};

Diff diffSingleChange(const QString& before, const QString& after) {
    const int aLen = before.size();
    const int bLen = after.size();

    int prefix = 0;
    const int prefixMax = std::min(aLen, bLen);
    while (prefix < prefixMax && before[prefix] == after[prefix]) {
        ++prefix;
    }

    int suffix = 0;
    while (suffix < (aLen - prefix) && suffix < (bLen - prefix) &&
           before[aLen - 1 - suffix] == after[bLen - 1 - suffix]) {
        ++suffix;
    }

    const int removed = (aLen - prefix - suffix);
    const int inserted = (bLen - prefix - suffix);

    Diff d;
    d.start = prefix;
    d.removedLen = std::max(0, removed);
    d.insertedLen = std::max(0, inserted);
    return d;
}

std::vector<Run> applyDelta(std::vector<Run> runs,
                            int start,
                            int removedLen,
                            int insertedLen,
                            const InlineAttrs& insertAttrs,
                            int textLenAfter) {
    const int end = start + removedLen;
    const int delta = insertedLen - removedLen;

    std::vector<Run> out;
    out.reserve(runs.size() + 2);

    for (const auto& r : runs) {
        if (r.end <= start) {
            out.push_back(r);
            continue;
        }
        if (r.start >= end) {
            Run shifted = r;
            shifted.start += delta;
            shifted.end += delta;
            out.push_back(shifted);
            continue;
        }
        // Overlapping removal: keep left part and/or right part.
        if (r.start < start) {
            out.push_back(Run{r.start, start, r.attrs});
        }
        if (r.end > end) {
            out.push_back(Run{start + insertedLen, (r.end + delta), r.attrs});
        }
    }

    if (insertedLen > 0) {
        out.push_back(Run{start, start + insertedLen, insertAttrs});
    }

    std::sort(out.begin(), out.end(), [](const Run& a, const Run& b) { return a.start < b.start; });
    return normalizeRuns(out, textLenAfter);
}

InlineAttrs parseStyleToAttrs(const QString& style) {
    InlineAttrs out;
    const auto s = style;

    const auto fontFamilyRe = QRegularExpression(QStringLiteral(R"(font-family\s*:\s*([^;]+))"),
                                                 QRegularExpression::CaseInsensitiveOption);
    const auto fontSizeRe =
        QRegularExpression(QStringLiteral(R"(font-size\s*:\s*([0-9]+)\s*(pt|px)?)"),
                           QRegularExpression::CaseInsensitiveOption);
    const auto colorRe = QRegularExpression(QStringLiteral(R"(color\s*:\s*(#[0-9a-fA-F]{6}))"));

    if (const auto m = fontFamilyRe.match(s); m.hasMatch()) {
        auto v = m.captured(1).trimmed();
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\''))) {
            v = v.mid(1, v.size() - 2);
        }
        out.fontFamily = v;
    }

    if (const auto m = fontSizeRe.match(s); m.hasMatch()) {
        const int n = m.captured(1).toInt();
        const auto unit = m.captured(2).toLower();
        if (unit == QStringLiteral("px")) {
            out.fontPointSize = std::max(1, static_cast<int>(std::round(static_cast<double>(n) * 0.75)));
        } else {
            out.fontPointSize = std::max(1, n);
        }
    }

    if (const auto m = colorRe.match(s); m.hasMatch()) {
        const QColor c(m.captured(1));
        if (c.isValid()) {
            out.color = c;
            out.hasColor = true;
        }
    }

    return out;
}

InlineAttrs mergeAttrs(const InlineAttrs& base, const InlineAttrs& overlay) {
    InlineAttrs out = base;
    if (!overlay.fontFamily.isEmpty()) out.fontFamily = overlay.fontFamily;
    if (overlay.fontPointSize > 0) out.fontPointSize = overlay.fontPointSize;
    if (overlay.hasColor) {
        out.color = overlay.color;
        out.hasColor = true;
    }
    out.bold = base.bold || overlay.bold;
    out.italic = base.italic || overlay.italic;
    out.underline = base.underline || overlay.underline;
    out.strike = base.strike || overlay.strike;
    return out;
}

struct TagState {
    InlineAttrs overlay;
    InlineAttrs prev;
};

} // namespace

InlineRichText::InlineRichText(QObject* parent)
    : QObject(parent) {}

QVariantMap InlineRichText::parse(const QString& markup) const {
    QString plain;
    plain.reserve(markup.size());

    std::vector<TagState> stack;
    InlineAttrs current;

    std::vector<Run> runs;
    runs.reserve(16);
    int runStart = 0;
    InlineAttrs runAttrs = current;

    const auto flushRunTo = [&](int pos) {
        if (pos < runStart) return;
        if (pos == runStart) {
            runAttrs = current;
            return;
        }
        runs.push_back(Run{runStart, pos, runAttrs});
        runStart = pos;
        runAttrs = current;
    };

    const auto maybeSwitchAttrs = [&](int pos) {
        if (!(runAttrs == current)) {
            flushRunTo(pos);
        }
    };

    const int n = markup.size();
    int i = 0;
    while (i < n) {
        const QChar ch = markup[i];
        if (ch != '<') {
            maybeSwitchAttrs(plain.size());
            plain.append(ch);
            ++i;
            continue;
        }

        const int gt = markup.indexOf('>', i + 1);
        if (gt < 0) {
            maybeSwitchAttrs(plain.size());
            plain.append(ch);
            ++i;
            continue;
        }

        const QString tag = markup.mid(i, gt - i + 1);

        auto consume = [&] {
            i = gt + 1;
        };

        const auto tagLower = tag.toLower();
        if (tagLower.startsWith(QStringLiteral("<span")) && tagLower.contains(QStringLiteral("style="))) {
            // Extract style='...'/style="..."
            const auto styleAttrRe = QRegularExpression(QStringLiteral(R"(style\s*=\s*(['"])(.*?)\1)"),
                                                        QRegularExpression::CaseInsensitiveOption);
            const auto m = styleAttrRe.match(tag);
            if (m.hasMatch()) {
                const auto overlay = parseStyleToAttrs(m.captured(2));
                stack.push_back(TagState{overlay, current});
                current = mergeAttrs(current, overlay);
                consume();
                continue;
            }
        } else if (tagLower == QStringLiteral("</span>")) {
            if (!stack.empty()) {
                current = stack.back().prev;
                stack.pop_back();
            }
            consume();
            continue;
        } else if (tagLower == QStringLiteral("<b>") || tagLower == QStringLiteral("<strong>")) {
            InlineAttrs overlay;
            overlay.bold = true;
            stack.push_back(TagState{overlay, current});
            current = mergeAttrs(current, overlay);
            consume();
            continue;
        } else if (tagLower == QStringLiteral("</b>") || tagLower == QStringLiteral("</strong>")) {
            // Pop until matching bold opener.
            if (!stack.empty()) {
                current = stack.back().prev;
                stack.pop_back();
            }
            consume();
            continue;
        } else if (tagLower == QStringLiteral("<i>") || tagLower == QStringLiteral("<em>")) {
            InlineAttrs overlay;
            overlay.italic = true;
            stack.push_back(TagState{overlay, current});
            current = mergeAttrs(current, overlay);
            consume();
            continue;
        } else if (tagLower == QStringLiteral("</i>") || tagLower == QStringLiteral("</em>")) {
            if (!stack.empty()) {
                current = stack.back().prev;
                stack.pop_back();
            }
            consume();
            continue;
        } else if (tagLower == QStringLiteral("<u>")) {
            InlineAttrs overlay;
            overlay.underline = true;
            stack.push_back(TagState{overlay, current});
            current = mergeAttrs(current, overlay);
            consume();
            continue;
        } else if (tagLower == QStringLiteral("</u>")) {
            if (!stack.empty()) {
                current = stack.back().prev;
                stack.pop_back();
            }
            consume();
            continue;
        } else if (tagLower == QStringLiteral("<s>") || tagLower == QStringLiteral("<del>") ||
                   tagLower == QStringLiteral("<strike>")) {
            InlineAttrs overlay;
            overlay.strike = true;
            stack.push_back(TagState{overlay, current});
            current = mergeAttrs(current, overlay);
            consume();
            continue;
        } else if (tagLower == QStringLiteral("</s>") || tagLower == QStringLiteral("</del>") ||
                   tagLower == QStringLiteral("</strike>")) {
            if (!stack.empty()) {
                current = stack.back().prev;
                stack.pop_back();
            }
            consume();
            continue;
        }

        // Unknown tag: keep as literal text.
        maybeSwitchAttrs(plain.size());
        plain.append(tag);
        consume();
    }

    // Flush final run.
    flushRunTo(plain.size());
    runs = normalizeRuns(runs, plain.size());

    QVariantMap out;
    out.insert(QStringLiteral("text"), plain);
    out.insert(QStringLiteral("runs"), runsToVariantList(runs));
    return out;
}

QString InlineRichText::serialize(const QString& text, const QVariantList& runsVar) const {
    auto runs = normalizeRuns(runsFromVariantList(runsVar), text.size());

    auto quoteCssString = [](const QString& s) {
        QString escaped;
        escaped.reserve(s.size() + 8);
        for (const auto ch : s) {
            if (ch == '\\' || ch == '"') escaped.append('\\');
            escaped.append(ch);
        }
        QString out;
        out.reserve(escaped.size() + 2);
        out.append('"');
        out.append(escaped);
        out.append('"');
        return out;
    };

    auto styleStringFor = [&](const InlineAttrs& a) -> QString {
        QString out;
        if (!a.fontFamily.isEmpty()) {
            out += QStringLiteral("font-family: ");
            out += quoteCssString(a.fontFamily);
            out += QLatin1Char(';');
        }
        if (a.fontPointSize > 0) {
            if (!out.isEmpty()) out += QLatin1Char(' ');
            out += QStringLiteral("font-size: ");
            out += QString::number(a.fontPointSize);
            out += QStringLiteral("pt;");
        }
        if (a.hasColor) {
            if (!out.isEmpty()) out += QLatin1Char(' ');
            out += QStringLiteral("color: ");
            out += a.color.name(QColor::HexRgb);
            out += QLatin1Char(';');
        }
        return out;
    };

    QString out;
    out.reserve(text.size() + 32);

    for (const auto& r : runs) {
        const QString segment = text.mid(r.start, r.end - r.start);
        const auto style = styleStringFor(r.attrs);

        if (r.attrs.bold) out.append(QStringLiteral("<b>"));
        if (r.attrs.italic) out.append(QStringLiteral("<i>"));
        if (r.attrs.underline) out.append(QStringLiteral("<u>"));
        if (r.attrs.strike) out.append(QStringLiteral("<s>"));
        if (!style.isEmpty()) {
            // HTML attribute uses single quotes; escape any single quotes in style.
            QString htmlStyle = style;
            htmlStyle.replace('\'', QStringLiteral("&#39;"));
            out.append(QStringLiteral("<span style='"));
            out.append(htmlStyle);
            out.append(QStringLiteral("'>"));
        }

        out.append(segment);

        if (!style.isEmpty()) out.append(QStringLiteral("</span>"));
        if (r.attrs.strike) out.append(QStringLiteral("</s>"));
        if (r.attrs.underline) out.append(QStringLiteral("</u>"));
        if (r.attrs.italic) out.append(QStringLiteral("</i>"));
        if (r.attrs.bold) out.append(QStringLiteral("</b>"));
    }

    return out;
}

QVariantMap InlineRichText::attrsAt(const QVariantList& runsVar, int pos) const {
    const auto runs = normalizeRuns(runsFromVariantList(runsVar), std::max(0, pos + 1));
    return attrsToVariantMap(attrsAtPos(runs, pos));
}

QVariantMap InlineRichText::reconcileTextChange(const QString& beforeText,
                                                const QString& afterText,
                                                const QVariantList& runsVar,
                                                const QVariantMap& typingAttrsVar,
                                                int cursorPosition) const {
    const auto diff = diffSingleChange(beforeText, afterText);
    auto runs = normalizeRuns(runsFromVariantList(runsVar), beforeText.size());

    InlineAttrs insertAttrs;
    const auto typingAttrs = attrsFromVariantMap(typingAttrsVar);
    const bool hasTyping = !typingAttrsVar.isEmpty();

    if (diff.insertedLen > 0 && hasTyping) {
        insertAttrs = typingAttrs;
    } else {
        const int inheritPos = diff.start > 0 ? (diff.start - 1) : diff.start;
        insertAttrs = attrsAtPos(runs, inheritPos);
    }

    runs = applyDelta(std::move(runs), diff.start, diff.removedLen, diff.insertedLen, insertAttrs, afterText.size());

    QVariantMap out;
    out.insert(QStringLiteral("runs"), runsToVariantList(runs));

    // Keep typing attrs stable unless the edit was pure deletion (so caret moved into new context).
    QVariantMap nextTyping = typingAttrsVar;
    if (diff.insertedLen == 0 && diff.removedLen > 0) {
        const int last = static_cast<int>(afterText.size()) - 1;
        const int p = std::max(0, std::min(cursorPosition, last));
        nextTyping = attrsToVariantMap(attrsAtPos(runs, p));
    }
    out.insert(QStringLiteral("typingAttrs"), nextTyping);
    out.insert(QStringLiteral("changeStart"), diff.start);
    out.insert(QStringLiteral("removedLen"), diff.removedLen);
    out.insert(QStringLiteral("insertedLen"), diff.insertedLen);
    return out;
}

QVariantMap InlineRichText::applyFormat(const QString& text,
                                        const QVariantList& runsVar,
                                        int selectionStart,
                                        int selectionEnd,
                                        int cursorPosition,
                                        const QVariantMap& format,
                                        const QVariantMap& typingAttrsVar) const {
    auto runs = normalizeRuns(runsFromVariantList(runsVar), text.size());
    const int len = text.size();

    const int a = std::max(0, std::min(selectionStart, selectionEnd));
    const int b = std::max(0, std::max(selectionStart, selectionEnd));
    const bool hasSelection = selectionStart >= 0 && selectionEnd >= 0 && a != b;

    const auto type = format.value(QStringLiteral("type")).toString();
    const bool toggle = format.value(QStringLiteral("toggle")).toBool();

    auto applyToAttrs = [&](InlineAttrs attrs, bool enable) -> InlineAttrs {
        if (type == QStringLiteral("bold")) attrs.bold = enable;
        if (type == QStringLiteral("italic")) attrs.italic = enable;
        if (type == QStringLiteral("underline")) attrs.underline = enable;
        if (type == QStringLiteral("strike")) attrs.strike = enable;
        if (type == QStringLiteral("fontFamily")) attrs.fontFamily = format.value(QStringLiteral("value")).toString();
        if (type == QStringLiteral("fontSizePt")) attrs.fontPointSize = format.value(QStringLiteral("value")).toInt();
        if (type == QStringLiteral("color")) {
            const QColor c(format.value(QStringLiteral("value")).toString());
            if (c.isValid()) {
                attrs.color = c;
                attrs.hasColor = true;
            }
        }
        return attrs;
    };

    if (!hasSelection) {
        // No selection -> update typing attrs (so subsequent inserts pick it up).
        InlineAttrs base = attrsFromVariantMap(typingAttrsVar);
        if (typingAttrsVar.isEmpty()) {
            base = attrsAtPos(runs, std::max(0, std::min(cursorPosition, len - 1)));
        }
        bool enable = true;
        if (toggle && (type == QStringLiteral("bold") || type == QStringLiteral("italic") ||
                       type == QStringLiteral("underline") || type == QStringLiteral("strike"))) {
            const bool currently =
                (type == QStringLiteral("bold") && base.bold) || (type == QStringLiteral("italic") && base.italic) ||
                (type == QStringLiteral("underline") && base.underline) ||
                (type == QStringLiteral("strike") && base.strike);
            enable = !currently;
        }
        const auto nextTyping = attrsToVariantMap(applyToAttrs(base, enable));

        QVariantMap out;
        out.insert(QStringLiteral("text"), text);
        out.insert(QStringLiteral("runs"), runsToVariantList(runs));
        out.insert(QStringLiteral("typingAttrs"), nextTyping);
        out.insert(QStringLiteral("selectionStart"), a);
        out.insert(QStringLiteral("selectionEnd"), b);
        out.insert(QStringLiteral("cursorPosition"), std::max(0, std::min(cursorPosition, len)));
        return out;
    }

    // Determine toggle target based on whether all selected text already has the attribute.
    bool enable = true;
    if (toggle && (type == QStringLiteral("bold") || type == QStringLiteral("italic") || type == QStringLiteral("underline") ||
                   type == QStringLiteral("strike"))) {
        bool all = true;
        for (const auto& r : runs) {
            const int rs = r.start;
            const int re = r.end;
            if (re <= a || rs >= b) continue;
            if (type == QStringLiteral("bold")) all = all && r.attrs.bold;
            if (type == QStringLiteral("italic")) all = all && r.attrs.italic;
            if (type == QStringLiteral("underline")) all = all && r.attrs.underline;
            if (type == QStringLiteral("strike")) all = all && r.attrs.strike;
        }
        enable = !all;
    }

    // Split runs around selection boundaries and apply.
    std::vector<Run> updated;
    updated.reserve(runs.size() + 4);

    for (const auto& r : runs) {
        if (r.end <= a || r.start >= b) {
            updated.push_back(r);
            continue;
        }
        if (r.start < a) {
            updated.push_back(Run{r.start, a, r.attrs});
        }
        const int midStart = std::max(r.start, a);
        const int midEnd = std::min(r.end, b);
        updated.push_back(Run{midStart, midEnd, applyToAttrs(r.attrs, enable)});
        if (r.end > b) {
            updated.push_back(Run{b, r.end, r.attrs});
        }
    }

    updated = normalizeRuns(updated, len);

    QVariantMap out;
    out.insert(QStringLiteral("text"), text);
    out.insert(QStringLiteral("runs"), runsToVariantList(updated));
    out.insert(QStringLiteral("typingAttrs"), typingAttrsVar);
    out.insert(QStringLiteral("selectionStart"), a);
    out.insert(QStringLiteral("selectionEnd"), b);
    out.insert(QStringLiteral("cursorPosition"), b);
    return out;
}

} // namespace zinc::ui
