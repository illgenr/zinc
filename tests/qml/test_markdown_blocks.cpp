#include <catch2/catch_test_macros.hpp>

#include <QVariantList>
#include <QVariantMap>

#include "ui/MarkdownBlocks.hpp"

namespace {

QVariantMap block(const QString& type,
                  const QString& content,
                  int depth = 0,
                  bool checked = false,
                  bool collapsed = false,
                  const QString& language = {},
                  int headingLevel = 0) {
    QVariantMap b;
    b["blockType"] = type;
    b["content"] = content;
    b["depth"] = depth;
    b["checked"] = checked;
    b["collapsed"] = collapsed;
    b["language"] = language;
    b["headingLevel"] = headingLevel;
    return b;
}

} // namespace

TEST_CASE("MarkdownBlocks: serialize/parse round-trip", "[qml][markdown]") {
    zinc::ui::MarkdownBlocks codec;

    QVariantList blocks;
    blocks.append(block("heading", "Title", 0, false, false, {}, 2));
    blocks.append(block("paragraph", "Hello\nWorld"));
    blocks.append(block("bulleted", "- item 1\n  continuation\n- item 2"));
    blocks.append(block("todo", "Task", 1, true));
    blocks.append(block("image", "file:///tmp/example.png"));
    blocks.append(block("columns", R"({"cols":["Left","Right"]})"));
    blocks.append(block("quote", "A\nB"));
    blocks.append(block("code", "int main() {\n  return 0;\n}", 0, false, false, "cpp"));
    blocks.append(block("divider", ""));
    blocks.append(block("link", "00000000-0000-0000-0000-000000000001|Example"));
    blocks.append(block("toggle", "Summary", 0, false, true));

    const auto markdown = codec.serialize(blocks);
    REQUIRE(codec.isZincBlocksPayload(markdown));

    const auto parsed = codec.parse(markdown);
    REQUIRE(parsed.size() == blocks.size());

    for (int i = 0; i < blocks.size(); ++i) {
        const auto a = blocks[i].toMap();
        const auto b = parsed[i].toMap();
        REQUIRE(b.value("blockType") == a.value("blockType"));
        REQUIRE(b.value("content") == a.value("content"));
        REQUIRE(b.value("depth") == a.value("depth"));
        REQUIRE(b.value("checked") == a.value("checked"));
        REQUIRE(b.value("collapsed") == a.value("collapsed"));
        REQUIRE(b.value("language") == a.value("language"));
        REQUIRE(b.value("headingLevel") == a.value("headingLevel"));
    }
}

TEST_CASE("MarkdownBlocks: parseWithSpans returns raw slices", "[qml][markdown]") {
    zinc::ui::MarkdownBlocks codec;

    const auto md = QStringLiteral(
        "<!-- zinc-blocks v1 -->\n"
        "\n"
        "## Title\n"
        "\n"
        "<!-- zinc-columns v1 {\"cols\":[\"A\",\"B\"]} -->\n"
        "\n"
        "![](/tmp/example.png)\n"
        "\n"
        "- item 1\n"
        "  continuation\n"
        "- item 2\n"
        "\n"
        "- [ ] Task\n"
        "\n"
        "---\n"
        "\n"
        "[Example](zinc://page/00000000-0000-0000-0000-000000000001)\n"
        "\n");

    const auto spans = codec.parseWithSpans(md);
    REQUIRE(spans.size() == 7);

    REQUIRE(spans[0].toMap().value("blockType").toString() == QStringLiteral("heading"));
    REQUIRE(spans[0].toMap().value("raw").toString() == QStringLiteral("## Title\n"));

    REQUIRE(spans[1].toMap().value("blockType").toString() == QStringLiteral("columns"));
    REQUIRE(spans[1].toMap().value("raw").toString().startsWith("<!-- zinc-columns"));

    REQUIRE(spans[2].toMap().value("blockType").toString() == QStringLiteral("image"));
    REQUIRE(spans[2].toMap().value("raw").toString() == QStringLiteral("![](/tmp/example.png)\n"));

    REQUIRE(spans[3].toMap().value("blockType").toString() == QStringLiteral("bulleted"));
    REQUIRE(spans[3].toMap().value("raw").toString().startsWith("- item 1"));

    REQUIRE(spans[4].toMap().value("blockType").toString() == QStringLiteral("todo"));
    REQUIRE(spans[4].toMap().value("raw").toString() == QStringLiteral("- [ ] Task\n"));

    REQUIRE(spans[5].toMap().value("blockType").toString() == QStringLiteral("divider"));
    REQUIRE(spans[5].toMap().value("raw").toString() == QStringLiteral("---\n"));

    REQUIRE(spans[6].toMap().value("blockType").toString() == QStringLiteral("link"));
    REQUIRE(spans[6].toMap().value("raw").toString().startsWith("[Example]("));
}
