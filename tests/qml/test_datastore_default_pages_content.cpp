#include <catch2/catch_test_macros.hpp>

#include <QFile>
#include <QString>

#include "ui/DataStore.hpp"

namespace {

QString readResourceText(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    const auto bytes = file.readAll();
    return QString::fromUtf8(bytes);
}

} // namespace

TEST_CASE("DataStore: seedDefaultPages loads markdown from default_pages resources", "[qml][datastore]") {
    zinc::ui::DataStore store;
    REQUIRE(store.initialize());
    REQUIRE(store.resetDatabase());

    struct Expected {
        const char* id;
        const char* resourcePath;
    };

    static constexpr Expected expectedPages[] = {
        {"1", ":/zinc/default_pages/My_Notebook/Getting_Started.md"},
        {"2", ":/zinc/default_pages/My_Notebook/Projects.md"},
        {"3", ":/zinc/default_pages/My_Notebook/Work_Project.md"},
        {"4", ":/zinc/default_pages/My_Notebook/Personal.md"},
    };

    for (const auto& expected : expectedPages) {
        const auto expectedBody = readResourceText(QString::fromLatin1(expected.resourcePath));
        REQUIRE_FALSE(expectedBody.isNull());

        const auto page = store.getPage(QString::fromLatin1(expected.id));
        REQUIRE(page.value("pageId").toString() == QString::fromLatin1(expected.id));
        REQUIRE(page.value("contentMarkdown").toString() == expectedBody);
    }
}
