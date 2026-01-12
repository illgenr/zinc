#include "ui/Cmark.hpp"

#include <cmark.h>

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
                                        CMARK_OPT_DEFAULT);
    if (!html) {
        return QString();
    }

    const QString out = QString::fromUtf8(html);
    free(html);
    return out;
}

} // namespace zinc::ui

