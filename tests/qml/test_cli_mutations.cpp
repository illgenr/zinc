#include <catch2/catch_test_macros.hpp>

#include <QString>

#include "ui/DataStore.hpp"
#include "ui/cli/mutations.hpp"

TEST_CASE("CLI: can create and delete notebooks", "[qml][cli][notebook]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto created = zinc::ui::create_notebook(store, zinc::ui::CreateNotebookOptions{.name = QStringLiteral("Work")});
    REQUIRE(created.is_ok());
    const auto notebookId = created.unwrap();
    REQUIRE_FALSE(notebookId.isEmpty());

    const auto deleted = zinc::ui::delete_notebook(store, zinc::ui::DeleteNotebookOptions{.notebookId = notebookId});
    REQUIRE(deleted.is_ok());
    REQUIRE(store.getNotebook(notebookId).isEmpty());
}

TEST_CASE("CLI: can create and delete pages", "[qml][cli][page]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto pageCreated = zinc::ui::create_page(store, zinc::ui::CreatePageOptions{.title = QStringLiteral("Hello")});
    REQUIRE(pageCreated.is_ok());
    const auto pageId = pageCreated.unwrap();
    REQUIRE_FALSE(pageId.isEmpty());
    REQUIRE_FALSE(store.getPage(pageId).isEmpty());

    const auto deleted = zinc::ui::delete_page(store, zinc::ui::DeletePageOptions{.pageId = pageId});
    REQUIRE(deleted.is_ok());
    REQUIRE(store.getPage(pageId).isEmpty());
}

TEST_CASE("CLI: page-create can create a child page under a parent", "[qml][cli][page][parent]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto parentCreated = zinc::ui::create_page(store, zinc::ui::CreatePageOptions{.title = QStringLiteral("Parent")});
    REQUIRE(parentCreated.is_ok());
    const auto parentId = parentCreated.unwrap();

    const auto childCreated = zinc::ui::create_page(store, zinc::ui::CreatePageOptions{
                                                              .title = QStringLiteral("Child"),
                                                              .parentPageId = parentId,
                                                          });
    REQUIRE(childCreated.is_ok());
    const auto childId = childCreated.unwrap();

    const auto child = store.getPage(childId);
    REQUIRE(child.value(QStringLiteral("parentId")).toString() == parentId);
    REQUIRE(child.value(QStringLiteral("depth")).toInt() == store.getPage(parentId).value(QStringLiteral("depth")).toInt() + 1);
}

