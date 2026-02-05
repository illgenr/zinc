#include "ui/cli/note.hpp"

#include <QVariantList>
#include <QVariantMap>

#include "ui/Cmark.hpp"
#include "ui/DataStore.hpp"

namespace zinc::ui {

namespace {

[[nodiscard]] bool is_exact_title_match(const QVariantMap& page, const QString& name) {
    return page.value(QStringLiteral("title")).toString() == name;
}

[[nodiscard]] QString ensure_trailing_newline(QString text) {
    if (!text.isEmpty() && !text.endsWith(QLatin1Char('\n'))) {
        text += QLatin1Char('\n');
    }
    return text;
}

[[nodiscard]] Result<QVariantMap> resolve_page_by_id(DataStore& store, const QString& pageId) {
    const auto page = store.getPage(pageId);
    if (page.isEmpty()) {
        return Result<QVariantMap>::err(Error{("Page not found: " + pageId).toStdString()});
    }
    return Result<QVariantMap>::ok(page);
}

[[nodiscard]] Result<QVariantMap> resolve_page_by_name(DataStore& store, const QString& name) {
    const auto pages = store.getAllPages();

    QStringList ids;
    ids.reserve(pages.size());
    for (const auto& entry : pages) {
        const auto page = entry.toMap();
        if (is_exact_title_match(page, name)) {
            ids.append(page.value(QStringLiteral("pageId")).toString());
        }
    }

    if (ids.isEmpty()) {
        return Result<QVariantMap>::err(Error{("Page not found by name: " + name).toStdString()});
    }
    if (ids.size() > 1) {
        return Result<QVariantMap>::err(Error{("Multiple pages match name: " + name).toStdString()});
    }

    return resolve_page_by_id(store, ids.at(0));
}

[[nodiscard]] Result<QVariantMap> resolve_page(DataStore& store, const NoteOptions& options) {
    const bool hasId = !options.pageId.trimmed().isEmpty();
    const auto trimmedName = options.name.trimmed();
    const bool hasName = !trimmedName.isEmpty();

    if (hasId == hasName) {
        return Result<QVariantMap>::err(Error{"Provide exactly one of --id or --name"});
    }

    if (hasId) {
        return resolve_page_by_id(store, options.pageId.trimmed());
    }
    return resolve_page_by_name(store, trimmedName);
}

} // namespace

Result<QString> render_note(DataStore& store, const NoteOptions& options) {
    return resolve_page(store, options).map([&options](const QVariantMap& page) -> QString {
        const auto markdown = page.value(QStringLiteral("contentMarkdown")).toString();
        if (!options.html) {
            return ensure_trailing_newline(markdown);
        }
        const Cmark cmark;
        return ensure_trailing_newline(cmark.toHtml(markdown));
    });
}

} // namespace zinc::ui
