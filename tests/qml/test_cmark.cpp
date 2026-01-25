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

TEST_CASE("Cmark: allows safe inline HTML tags", "[qml][cmark]") {
    zinc::ui::Cmark cmark;
    const auto html = cmark.toHtml(QStringLiteral("A <u>U</u> <span style=\"color:#ff0000; font-size:12pt;\">S</span>."));
    REQUIRE(html.contains(QStringLiteral("<u>U</u>")));
    REQUIRE(html.contains(QStringLiteral("<span style=\"color:#ff0000;font-size:12pt;\">S</span>")));
}

TEST_CASE("Cmark: strips unsafe script tags", "[qml][cmark]") {
    zinc::ui::Cmark cmark;
    const auto html = cmark.toHtml(QStringLiteral("X <script>alert(1)</script> Y"));
    REQUIRE(!html.contains(QStringLiteral("<script")));
    REQUIRE(!html.contains(QStringLiteral("alert(1)")));
    REQUIRE(html.contains(QStringLiteral("X")));
    REQUIRE(html.contains(QStringLiteral("Y")));
}
