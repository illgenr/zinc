#include <catch2/catch_test_macros.hpp>

#include "core/three_way_merge.hpp"

using zinc::ThreeWayMergeResult;
using zinc::three_way_merge_text;

TEST_CASE("three_way_merge_text: takes ours when theirs == base", "[unit][merge]") {
    const auto r = three_way_merge_text("a\nb\n", "a\nb\nc\n", "a\nb\n");
    REQUIRE(r.kind == ThreeWayMergeResult::Kind::Clean);
    REQUIRE(r.merged == "a\nb\nc\n");
}

TEST_CASE("three_way_merge_text: merges non-overlapping inserts cleanly", "[unit][merge]") {
    const std::string base = "a\nb\nc";
    const std::string ours = "a\nb\nc\nours";
    const std::string theirs = "theirs\na\nb\nc";

    const auto r = three_way_merge_text(base, ours, theirs);
    REQUIRE(r.kind == ThreeWayMergeResult::Kind::Clean);
    REQUIRE(r.merged == "theirs\na\nb\nc\nours");
}

TEST_CASE("three_way_merge_text: emits conflict markers for overlapping edits", "[unit][merge]") {
    const std::string base = "a\nb\nc";
    const std::string ours = "a\nb-ours\nc";
    const std::string theirs = "a\nb-theirs\nc";

    const auto r = three_way_merge_text(base, ours, theirs);
    REQUIRE(r.kind == ThreeWayMergeResult::Kind::Conflict);
    REQUIRE(r.merged.find("<<<<<<< ours") != std::string::npos);
    REQUIRE(r.merged.find("=======") != std::string::npos);
    REQUIRE(r.merged.find(">>>>>>> theirs") != std::string::npos);
}

