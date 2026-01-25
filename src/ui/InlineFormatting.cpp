#include "ui/InlineFormatting.hpp"

#include <algorithm>

namespace zinc::ui {
namespace {

struct FormatResult {
    QString text;
    int selectionStart = 0;
    int selectionEnd = 0;
    int cursorPosition = 0;
};

FormatResult wrapSelectionImpl(const QString& text,
                               int selectionStart,
                               int selectionEnd,
                               int cursorPosition,
                               const QString& prefix,
                               const QString& suffix,
                               bool toggle) {
    const auto clamp = [](int v, int lo, int hi) { return std::max(lo, std::min(v, hi)); };

    const int len = text.size();
    const int safeCursor = clamp(cursorPosition >= 0 ? cursorPosition : 0, 0, len);

    const bool selectionValid = selectionStart >= 0 && selectionEnd >= 0;
    const int aRaw = selectionValid ? selectionStart : safeCursor;
    const int bRaw = selectionValid ? selectionEnd : safeCursor;
    const int a = clamp(std::min(aRaw, bRaw), 0, len);
    const int b = clamp(std::max(aRaw, bRaw), 0, len);
    const bool hasSelection = selectionValid && a != b;

    if (!hasSelection) {
        const int pos = safeCursor;
        FormatResult out;
        out.text = text.left(pos) + prefix + suffix + text.mid(pos);
        out.cursorPosition = pos + prefix.size();
        out.selectionStart = out.cursorPosition;
        out.selectionEnd = out.cursorPosition;
        return out;
    }

    const int prefixLen = prefix.size();
    const int suffixLen = suffix.size();
    const bool canUnwrap =
        toggle && prefixLen > 0 && suffixLen > 0 && a >= prefixLen && (b + suffixLen) <= len &&
        text.mid(a - prefixLen, prefixLen) == prefix && text.mid(b, suffixLen) == suffix;

    if (canUnwrap) {
        const int wrapStart = a - prefixLen;
        const int wrapEnd = b + suffixLen;
        const QString inner = text.mid(a, b - a);

        FormatResult out;
        out.text = text.left(wrapStart) + inner + text.mid(wrapEnd);
        out.selectionStart = wrapStart;
        out.selectionEnd = wrapStart + (b - a);
        out.cursorPosition = out.selectionEnd;
        return out;
    }

    FormatResult out;
    out.text = text.left(a) + prefix + text.mid(a, b - a) + suffix + text.mid(b);
    out.selectionStart = a + prefixLen;
    out.selectionEnd = b + prefixLen;
    out.cursorPosition = out.selectionEnd;
    return out;
}

QVariantMap toVariantMap(const FormatResult& r) {
    QVariantMap m;
    m.insert(QStringLiteral("text"), r.text);
    m.insert(QStringLiteral("selectionStart"), r.selectionStart);
    m.insert(QStringLiteral("selectionEnd"), r.selectionEnd);
    m.insert(QStringLiteral("cursorPosition"), r.cursorPosition);
    return m;
}

} // namespace

InlineFormatting::InlineFormatting(QObject* parent)
    : QObject(parent) {}

QVariantMap InlineFormatting::wrapSelection(const QString& text,
                                           int selectionStart,
                                           int selectionEnd,
                                           int cursorPosition,
                                           const QString& prefix,
                                           const QString& suffix,
                                           bool toggle) const {
    return toVariantMap(wrapSelectionImpl(text, selectionStart, selectionEnd, cursorPosition, prefix, suffix, toggle));
}

} // namespace zinc::ui

