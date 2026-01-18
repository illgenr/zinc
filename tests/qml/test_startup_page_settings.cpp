#include <catch2/catch_test_macros.hpp>

#include <QSettings>
#include <QVariantList>
#include <QVariantMap>

#include "ui/DataStore.hpp"

namespace {

constexpr auto kKeyStartupMode = "ui/startup_mode";
constexpr auto kKeyStartupFixedPageId = "ui/startup_fixed_page_id";
constexpr auto kKeyLastViewedPageId = "ui/last_viewed_page_id";

QVariantList make_pages(const QStringList& ids) {
    QVariantList pages;
    pages.reserve(ids.size());
    for (const auto& id : ids) {
        QVariantMap page;
        page.insert(QStringLiteral("pageId"), id);
        page.insert(QStringLiteral("title"), id);
        pages.push_back(page);
    }
    return pages;
}

} // namespace

TEST_CASE("Startup page settings: defaults to last viewed mode", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyStartupMode));
    settings.remove(QString::fromLatin1(kKeyStartupFixedPageId));
    settings.remove(QString::fromLatin1(kKeyLastViewedPageId));

    zinc::ui::DataStore store;
    REQUIRE(store.startupPageMode() == 0);
}

TEST_CASE("Startup page settings: persists mode and page ids", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyStartupMode));
    settings.remove(QString::fromLatin1(kKeyStartupFixedPageId));
    settings.remove(QString::fromLatin1(kKeyLastViewedPageId));

    zinc::ui::DataStore store;
    store.setStartupPageMode(1);
    store.setStartupFixedPageId(QStringLiteral("fixed"));
    store.setLastViewedPageId(QStringLiteral("last"));

    REQUIRE(settings.value(QString::fromLatin1(kKeyStartupMode)).toInt() == 1);
    REQUIRE(settings.value(QString::fromLatin1(kKeyStartupFixedPageId)).toString() == QStringLiteral("fixed"));
    REQUIRE(settings.value(QString::fromLatin1(kKeyLastViewedPageId)).toString() == QStringLiteral("last"));
}

TEST_CASE("Startup page settings: resolves page id from pages list", "[qml][settings]") {
    QSettings settings;
    settings.remove(QString::fromLatin1(kKeyStartupMode));
    settings.remove(QString::fromLatin1(kKeyStartupFixedPageId));
    settings.remove(QString::fromLatin1(kKeyLastViewedPageId));

    zinc::ui::DataStore store;

    const auto pages = make_pages({QStringLiteral("a"), QStringLiteral("b"), QStringLiteral("c")});

    SECTION("Last viewed mode prefers last viewed id") {
        store.setStartupPageMode(0);
        store.setLastViewedPageId(QStringLiteral("b"));
        REQUIRE(store.resolveStartupPageId(pages) == QStringLiteral("b"));
    }

    SECTION("Last viewed mode falls back to first page when missing") {
        store.setStartupPageMode(0);
        store.setLastViewedPageId(QStringLiteral("missing"));
        REQUIRE(store.resolveStartupPageId(pages) == QStringLiteral("a"));
    }

    SECTION("Fixed mode prefers fixed id when present") {
        store.setStartupPageMode(1);
        store.setStartupFixedPageId(QStringLiteral("c"));
        store.setLastViewedPageId(QStringLiteral("b"));
        REQUIRE(store.resolveStartupPageId(pages) == QStringLiteral("c"));
    }

    SECTION("Fixed mode falls back to last viewed, then first") {
        store.setStartupPageMode(1);
        store.setStartupFixedPageId(QStringLiteral("missing"));
        store.setLastViewedPageId(QStringLiteral("b"));
        REQUIRE(store.resolveStartupPageId(pages) == QStringLiteral("b"));

        store.setLastViewedPageId(QStringLiteral("also-missing"));
        REQUIRE(store.resolveStartupPageId(pages) == QStringLiteral("a"));
    }
}
