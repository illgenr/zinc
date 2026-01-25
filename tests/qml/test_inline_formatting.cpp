#include <catch2/catch_test_macros.hpp>

#include "ui/InlineFormatting.hpp"

TEST_CASE("InlineFormatting: wraps selection and preserves inner selection", "[qml][formatting]") {
    zinc::ui::InlineFormatting fmt;

    const auto out = fmt.wrapSelection(QStringLiteral("hello world"),
                                       /*selectionStart=*/0,
                                       /*selectionEnd=*/5,
                                       /*cursorPosition=*/0,
                                       QStringLiteral("**"),
                                       QStringLiteral("**"),
                                       /*toggle=*/true);

    REQUIRE(out.value("text").toString() == QStringLiteral("**hello** world"));
    REQUIRE(out.value("selectionStart").toInt() == 2);
    REQUIRE(out.value("selectionEnd").toInt() == 7);
    REQUIRE(out.value("cursorPosition").toInt() == 7);
}

TEST_CASE("InlineFormatting: toggles off when selection is already wrapped", "[qml][formatting]") {
    zinc::ui::InlineFormatting fmt;

    const auto out = fmt.wrapSelection(QStringLiteral("**hello**"),
                                       /*selectionStart=*/2,
                                       /*selectionEnd=*/7,
                                       /*cursorPosition=*/0,
                                       QStringLiteral("**"),
                                       QStringLiteral("**"),
                                       /*toggle=*/true);

    REQUIRE(out.value("text").toString() == QStringLiteral("hello"));
    REQUIRE(out.value("selectionStart").toInt() == 0);
    REQUIRE(out.value("selectionEnd").toInt() == 5);
    REQUIRE(out.value("cursorPosition").toInt() == 5);
}

TEST_CASE("InlineFormatting: inserts wrappers at cursor when no selection", "[qml][formatting]") {
    zinc::ui::InlineFormatting fmt;

    const auto out = fmt.wrapSelection(QStringLiteral("hi"),
                                       /*selectionStart=*/-1,
                                       /*selectionEnd=*/-1,
                                       /*cursorPosition=*/2,
                                       QStringLiteral("<u>"),
                                       QStringLiteral("</u>"),
                                       /*toggle=*/false);

    REQUIRE(out.value("text").toString() == QStringLiteral("hi<u></u>"));
    REQUIRE(out.value("selectionStart").toInt() == 5);
    REQUIRE(out.value("selectionEnd").toInt() == 5);
    REQUIRE(out.value("cursorPosition").toInt() == 5);
}

