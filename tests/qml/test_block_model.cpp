#include <catch2/catch_test_macros.hpp>

#include <QVariantList>
#include <QVariantMap>

#include "ui/MarkdownBlocks.hpp"
#include "ui/models/BlockModel.hpp"

namespace {

QVariantMap block(const QString& id,
                  const QString& type,
                  const QString& content,
                  int depth = 0,
                  bool checked = false,
                  bool collapsed = false,
                  const QString& language = {},
                  int headingLevel = 0) {
    QVariantMap b;
    b["blockId"] = id;
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

TEST_CASE("BlockModel: supports ListModel-like mutation APIs", "[qml][model]") {
    zinc::ui::BlockModel model;
    REQUIRE(model.count() == 0);

    model.append(block("a", "paragraph", "Hello"));
    REQUIRE(model.count() == 1);
    REQUIRE(model.get(0).value("blockId").toString() == QStringLiteral("a"));
    REQUIRE(model.get(0).value("blockType").toString() == QStringLiteral("paragraph"));
    REQUIRE(model.get(0).value("content").toString() == QStringLiteral("Hello"));

    model.setProperty(0, QStringLiteral("content"), QStringLiteral("World"));
    REQUIRE(model.get(0).value("content").toString() == QStringLiteral("World"));

    model.insert(0, block("b", "todo", "Task", 1, true));
    REQUIRE(model.count() == 2);
    REQUIRE(model.get(0).value("blockId").toString() == QStringLiteral("b"));
    REQUIRE(model.get(0).value("checked").toBool() == true);

    model.move(0, 1, 1);
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("b"));

    model.remove(1);
    REQUIRE(model.count() == 1);
    REQUIRE(model.get(0).value("blockId").toString() == QStringLiteral("a"));

    model.clear();
    REQUIRE(model.count() == 0);
}

TEST_CASE("BlockModel: markdown load/save matches MarkdownBlocks", "[qml][model][markdown]") {
    zinc::ui::MarkdownBlocks codec;

    QVariantList blocks;
    blocks.append(block("1", "heading", "Title", 0, false, false, {}, 2));
    blocks.append(block("2", "paragraph", "Hello\nWorld"));
    blocks.append(block("3", "bulleted", "- item 1\n- item 2"));
    blocks.append(block("4", "todo", "Task", 1, true));
    blocks.append(block("5", "code", "int main() {}", 0, false, false, "cpp"));
    blocks.append(block("6", "divider", ""));
    blocks.append(block("7", "link", "00000000-0000-0000-0000-000000000001|Example"));
    blocks.append(block("8", "toggle", "Summary", 0, false, true));

    const auto expected = codec.serializeContent(blocks);

    zinc::ui::BlockModel model;
    for (const auto& entry : blocks) {
        model.append(entry.toMap());
    }
    REQUIRE(model.serializeContentToMarkdown() == expected);

    zinc::ui::BlockModel reloaded;
    REQUIRE(reloaded.loadFromMarkdown(expected));
    REQUIRE(reloaded.count() == blocks.size());
    for (int i = 0; i < blocks.size(); ++i) {
        const auto got = reloaded.get(i);
        const auto want = blocks[i].toMap();
        REQUIRE(got.value("blockType") == want.value("blockType"));
        REQUIRE(got.value("content") == want.value("content"));
        REQUIRE(got.value("depth") == want.value("depth"));
        REQUIRE(got.value("checked") == want.value("checked"));
        REQUIRE(got.value("collapsed") == want.value("collapsed"));
        REQUIRE(got.value("language") == want.value("language"));
        REQUIRE(got.value("headingLevel") == want.value("headingLevel"));
        REQUIRE(!got.value("blockId").toString().isEmpty());
    }
}

