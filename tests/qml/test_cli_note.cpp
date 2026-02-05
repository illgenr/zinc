#include <catch2/catch_test_macros.hpp>

#include <QString>

#include "ui/DataStore.hpp"
#include "ui/cli/note.hpp"

namespace {

QVariantMap makePage(const QString& pageId,
                     const QString& title,
                     const QString& contentMarkdown) {
    QVariantMap page;
    page.insert(QStringLiteral("pageId"), pageId);
    page.insert(QStringLiteral("title"), title);
    page.insert(QStringLiteral("parentId"), QStringLiteral(""));
    page.insert(QStringLiteral("depth"), 0);
    page.insert(QStringLiteral("sortOrder"), 0);
    page.insert(QStringLiteral("contentMarkdown"), contentMarkdown);
    return page;
}

} // namespace

TEST_CASE("CLI: note can render by id (markdown default)", "[qml][cli][note]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    store.savePage(makePage(QStringLiteral("p_cli_note_1"),
                            QStringLiteral("CLI Note One"),
                            QStringLiteral("Hello")));

    zinc::ui::NoteOptions options;
    options.pageId = QStringLiteral("p_cli_note_1");

    const auto result = zinc::ui::render_note(store, options);
    REQUIRE(result.is_ok());
    REQUIRE(result.unwrap() == QStringLiteral("Hello\n"));
}

TEST_CASE("CLI: note can render by name (markdown default)", "[qml][cli][note]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    store.savePage(makePage(QStringLiteral("p_cli_note_2"),
                            QStringLiteral("CLI Note Two"),
                            QStringLiteral("Body")));

    zinc::ui::NoteOptions options;
    options.name = QStringLiteral("CLI Note Two");

    const auto result = zinc::ui::render_note(store, options);
    REQUIRE(result.is_ok());
    REQUIRE(result.unwrap() == QStringLiteral("Body\n"));
}

TEST_CASE("CLI: note can render HTML", "[qml][cli][note][html]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    store.savePage(makePage(QStringLiteral("p_cli_note_3"),
                            QStringLiteral("CLI Note Three"),
                            QStringLiteral("# Title")));

    zinc::ui::NoteOptions options;
    options.pageId = QStringLiteral("p_cli_note_3");
    options.html = true;

    const auto result = zinc::ui::render_note(store, options);
    REQUIRE(result.is_ok());
    REQUIRE(result.unwrap().contains(QStringLiteral("<h1>Title</h1>")));
}

TEST_CASE("CLI: note errors on ambiguous name", "[qml][cli][note][error]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    store.savePage(makePage(QStringLiteral("p_cli_note_4a"),
                            QStringLiteral("Same Title"),
                            QStringLiteral("One")));
    store.savePage(makePage(QStringLiteral("p_cli_note_4b"),
                            QStringLiteral("Same Title"),
                            QStringLiteral("Two")));

    zinc::ui::NoteOptions options;
    options.name = QStringLiteral("Same Title");

    const auto result = zinc::ui::render_note(store, options);
    REQUIRE(result.is_err());
}

