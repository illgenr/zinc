#include <catch2/catch_test_macros.hpp>

#include "ui/Cmark.hpp"

TEST_CASE("Cmark: renders markdown to HTML", "[qml][cmark]") {
    zinc::ui::Cmark cmark;
    const auto html = cmark.toHtml(QStringLiteral("*Hi*"));
    REQUIRE(html.contains(QStringLiteral("<em>Hi</em>")));
}

