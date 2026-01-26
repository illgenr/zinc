#include <catch2/catch_test_macros.hpp>

#include "ui/InlineRichText.hpp"

namespace {

QVariantList runsFrom(const QVariantMap& parsed) {
    return parsed.value(QStringLiteral("runs")).toList();
}

QString textFrom(const QVariantMap& parsed) {
    return parsed.value(QStringLiteral("text")).toString();
}

QVariantMap formatBoldToggle() {
    QVariantMap m;
    m.insert(QStringLiteral("type"), QStringLiteral("bold"));
    m.insert(QStringLiteral("toggle"), true);
    return m;
}

QVariantMap formatFontFamily(const QString& family) {
    QVariantMap m;
    m.insert(QStringLiteral("type"), QStringLiteral("fontFamily"));
    m.insert(QStringLiteral("value"), family);
    return m;
}

} // namespace

TEST_CASE("InlineRichText: parse strips supported tags and returns runs", "[qml][formatting]") {
    zinc::ui::InlineRichText rt;

    const auto parsed =
        rt.parse(QStringLiteral("<span style='font-family: \"DejaVu Sans\"; font-size: 12pt;'>Hi</span> there"));

    REQUIRE(textFrom(parsed) == QStringLiteral("Hi there"));

    const auto runs = runsFrom(parsed);
    REQUIRE(runs.size() >= 2);

    const auto first = runs[0].toMap();
    REQUIRE(first.value("start").toInt() == 0);
    REQUIRE(first.value("end").toInt() == 2);
    const auto attrs = first.value("attrs").toMap();
    REQUIRE(attrs.value("fontFamily").toString() == QStringLiteral("DejaVu Sans"));
    REQUIRE(attrs.value("fontPointSize").toInt() == 12);
}

TEST_CASE("InlineRichText: serialize preserves spans via HTML tags", "[qml][formatting]") {
    zinc::ui::InlineRichText rt;

    const auto parsed = rt.parse(QStringLiteral("<span style='font-family: \"DejaVu Sans\";'>Hi</span>"));
    const auto out = rt.serialize(textFrom(parsed), runsFrom(parsed));

    REQUIRE(out.contains(QStringLiteral("<span style='")));
    REQUIRE(out.contains(QStringLiteral("font-family:")));
    REQUIRE(out.contains(QStringLiteral("Hi")));
    REQUIRE(out.contains(QStringLiteral("</span>")));
}

TEST_CASE("InlineRichText: reconcileTextChange keeps formatting on insertion", "[qml][formatting]") {
    zinc::ui::InlineRichText rt;

    const auto parsed = rt.parse(QStringLiteral("<span style='font-family: \"DejaVu Sans\";'>Hi</span>"));
    const auto beforeText = textFrom(parsed);
    const auto beforeRuns = runsFrom(parsed);

    const auto afterText = QStringLiteral("Hi!");
    const auto reconciled =
        rt.reconcileTextChange(beforeText, afterText, beforeRuns, /*typingAttrs=*/{}, /*cursorPosition=*/3);

    const auto outRuns = runsFrom(reconciled);
    const auto out = rt.serialize(afterText, outRuns);
    REQUIRE(out.contains(QStringLiteral("Hi!")));
    REQUIRE(out.contains(QStringLiteral("font-family")));
}

TEST_CASE("InlineRichText: applyFormat toggles bold for selection", "[qml][formatting]") {
    zinc::ui::InlineRichText rt;

    const auto parsed = rt.parse(QStringLiteral("hello"));
    const auto out = rt.applyFormat(textFrom(parsed),
                                    runsFrom(parsed),
                                    /*selectionStart=*/0,
                                    /*selectionEnd=*/5,
                                    /*cursorPosition=*/5,
                                    formatBoldToggle(),
                                    /*typingAttrs=*/{});

    const auto s = rt.serialize(out.value("text").toString(), out.value("runs").toList());
    REQUIRE(s.contains(QStringLiteral("<b>hello</b>")));
}

TEST_CASE("InlineRichText: applyFormat updates typing attrs without selection", "[qml][formatting]") {
    zinc::ui::InlineRichText rt;

    const auto parsed = rt.parse(QStringLiteral("hello"));
    const auto out = rt.applyFormat(textFrom(parsed),
                                    runsFrom(parsed),
                                    /*selectionStart=*/2,
                                    /*selectionEnd=*/2,
                                    /*cursorPosition=*/2,
                                    formatFontFamily(QStringLiteral("DejaVu Sans")),
                                    /*typingAttrs=*/{});

    const auto typing = out.value(QStringLiteral("typingAttrs")).toMap();
    REQUIRE(typing.value(QStringLiteral("fontFamily")).toString() == QStringLiteral("DejaVu Sans"));
}
