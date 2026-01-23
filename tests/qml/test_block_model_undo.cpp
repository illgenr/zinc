#include <catch2/catch_test_macros.hpp>

#include <QVariantMap>

#include "ui/models/BlockModel.hpp"

namespace {

QVariantMap block(const QString& id, const QString& type, const QString& content) {
    QVariantMap b;
    b["blockId"] = id;
    b["blockType"] = type;
    b["content"] = content;
    b["depth"] = 0;
    b["checked"] = false;
    b["collapsed"] = false;
    b["language"] = QString();
    b["headingLevel"] = 0;
    return b;
}

} // namespace

TEST_CASE("BlockModel: undo/redo merges consecutive content edits", "[qml][model][undo]") {
    zinc::ui::BlockModel model;
    model.append(block("a", "paragraph", "Hi"));

    model.setProperty(0, QStringLiteral("content"), QStringLiteral("H"));
    model.setProperty(0, QStringLiteral("content"), QStringLiteral("He"));
    model.setProperty(0, QStringLiteral("content"), QStringLiteral("Hel"));
    REQUIRE(model.get(0).value("content").toString() == QStringLiteral("Hel"));

    model.undo();
    REQUIRE(model.get(0).value("content").toString() == QStringLiteral("Hi"));

    model.redo();
    REQUIRE(model.get(0).value("content").toString() == QStringLiteral("Hel"));
}

TEST_CASE("BlockModel: undo/redo insert/remove/move", "[qml][model][undo]") {
    zinc::ui::BlockModel model;
    model.append(block("a", "paragraph", "A"));
    model.append(block("b", "paragraph", "B"));
    model.append(block("c", "paragraph", "C"));

    model.insert(1, block("x", "paragraph", "X"));
    REQUIRE(model.count() == 4);
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("x"));

    model.undo();
    REQUIRE(model.count() == 3);
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("b"));

    model.redo();
    REQUIRE(model.count() == 4);
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("x"));

    model.remove(1);
    REQUIRE(model.count() == 3);
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("b"));

    model.undo();
    REQUIRE(model.count() == 4);
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("x"));

    model.move(1, 3, 1); // move x to end
    REQUIRE(model.get(3).value("blockId").toString() == QStringLiteral("x"));

    model.undo();
    REQUIRE(model.get(1).value("blockId").toString() == QStringLiteral("x"));
}

