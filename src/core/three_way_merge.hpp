#pragma once

#include <string>
#include <string_view>

namespace zinc {

struct ThreeWayMergeResult {
    enum class Kind {
        Clean,
        Conflict,
        TooLargeFallback
    };

    Kind kind{Kind::Clean};
    std::string merged;

    [[nodiscard]] bool clean() const { return kind == Kind::Clean; }
};

// A small, deterministic, line-based 3-way merge:
// - If changes are non-overlapping, returns Kind::Clean.
// - If overlapping edits occur, returns Kind::Conflict and embeds diff3-style markers.
// - If inputs are too large for the DP diff, returns Kind::TooLargeFallback and a marker-based merge.
[[nodiscard]] ThreeWayMergeResult three_way_merge_text(std::string_view base,
                                                       std::string_view ours,
                                                       std::string_view theirs);

} // namespace zinc

