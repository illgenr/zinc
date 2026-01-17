#include <catch2/catch_test_macros.hpp>

#include "ui/Cmark.hpp"

TEST_CASE("Cmark: renders markdown to HTML", "[qml][cmark]") {
    zinc::ui::Cmark cmark;
    const auto html = cmark.toHtml(QStringLiteral("*Hi*"));
    REQUIRE(html.contains(QStringLiteral("<em>Hi</em>")));
}

TEST_CASE("Cmark: styles ISO dates as muted text", "[qml][cmark]") {
    zinc::ui::Cmark cmark;
    const auto html = cmark.toHtml(QStringLiteral("Today is 2026-01-16."));
    REQUIRE(html.contains(QStringLiteral("2026-01-16")));
    REQUIRE(html.contains(QStringLiteral("href=\"zinc://date/2026-01-16\"")));
    REQUIRE(html.contains(QStringLiteral("style=\"color:#888888;")));
}
