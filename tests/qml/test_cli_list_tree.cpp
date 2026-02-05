#include <catch2/catch_test_macros.hpp>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include "ui/DataStore.hpp"
#include "ui/cli/list_tree.hpp"

TEST_CASE("CLI: list tree shows notebooks and page hierarchy", "[qml][cli][list]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto output = zinc::ui::format_notebook_page_tree(
        store.getAllNotebooks(),
        store.getAllPages(),
        {});

    const auto expected = QStringLiteral(
        "My Notebook\n"
        "  - Getting Started\n"
        "  - Projects\n"
        "    - Work Project\n"
        "  - Personal\n");

    REQUIRE(output == expected);
}

TEST_CASE("CLI: list tree can output JSON", "[qml][cli][list][json]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    const auto output = zinc::ui::format_notebook_page_tree_json(
        store.getAllNotebooks(),
        store.getAllPages(),
        zinc::ui::ListTreeOptions{.includeIds = true});

    const auto parsed = QJsonDocument::fromJson(output.toUtf8());
    REQUIRE(parsed.isObject());

    const auto root = parsed.object();
    REQUIRE(root.contains(QStringLiteral("notebooks")));
    const auto notebooks = root.value(QStringLiteral("notebooks")).toArray();
    REQUIRE(notebooks.size() == 1);

    const auto nb = notebooks.at(0).toObject();
    REQUIRE(nb.value(QStringLiteral("name")).toString() == QStringLiteral("My Notebook"));
    REQUIRE(nb.value(QStringLiteral("notebookId")).toString() == QStringLiteral("00000000-0000-0000-0000-000000000001"));

    const auto pages = nb.value(QStringLiteral("pages")).toArray();
    REQUIRE(pages.size() == 3);
    REQUIRE(pages.at(0).toObject().value(QStringLiteral("title")).toString() == QStringLiteral("Getting Started"));
    REQUIRE(pages.at(1).toObject().value(QStringLiteral("title")).toString() == QStringLiteral("Projects"));
    REQUIRE(pages.at(2).toObject().value(QStringLiteral("title")).toString() == QStringLiteral("Personal"));

    const auto projectsChildren = pages.at(1).toObject().value(QStringLiteral("children")).toArray();
    REQUIRE(projectsChildren.size() == 1);
    REQUIRE(projectsChildren.at(0).toObject().value(QStringLiteral("title")).toString() == QStringLiteral("Work Project"));
}
