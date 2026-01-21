#include "core/three_way_merge.hpp"

#include <algorithm>
#include <cstddef>
#include <vector>

namespace zinc {
namespace {

using Lines = std::vector<std::string>;

Lines split_lines(std::string_view text) {
    Lines out;
    out.reserve(64);

    std::string current;
    current.reserve(64);
    for (const char c : text) {
        if (c == '\r') {
            continue;
        }
        if (c == '\n') {
            out.push_back(std::move(current));
            current = {};
            continue;
        }
        current.push_back(c);
    }
    out.push_back(std::move(current));
    return out;
}

std::string join_lines(const Lines& lines) {
    if (lines.empty()) return {};
    std::string out;
    size_t bytes = 0;
    for (const auto& l : lines) {
        bytes += l.size() + 1;
    }
    out.reserve(bytes);
    for (size_t i = 0; i < lines.size(); ++i) {
        out += lines[i];
        if (i + 1 < lines.size()) out.push_back('\n');
    }
    return out;
}

struct DiffEdits {
    std::vector<Lines> inserts_before; // size = base.size() + 1
    std::vector<bool> deletes;         // size = base.size()
};

DiffEdits diff_edits_from_base(const Lines& base, const Lines& other, size_t cell_limit) {
    const auto n = base.size();
    const auto m = other.size();

    DiffEdits edits{
        .inserts_before = std::vector<Lines>(n + 1),
        .deletes = std::vector<bool>(n, false),
    };

    if (n == 0) {
        edits.inserts_before[0] = other;
        return edits;
    }

    // LCS DP table (n+1)*(m+1) - ok for small-ish notes.
    if ((n + 1) * (m + 1) > cell_limit) {
        // Best-effort fallback: treat as all replaced at start.
        edits.deletes.assign(n, true);
        edits.inserts_before[0] = other;
        return edits;
    }

    std::vector<int> dp((n + 1) * (m + 1), 0);
    const auto at = [&](size_t i, size_t j) -> int& { return dp[i * (m + 1) + j]; };

    for (size_t i = 0; i < n; ++i) {
        for (size_t j = 0; j < m; ++j) {
            if (base[i] == other[j]) {
                at(i + 1, j + 1) = at(i, j) + 1;
            } else {
                at(i + 1, j + 1) = std::max(at(i, j + 1), at(i + 1, j));
            }
        }
    }

    // Backtrack to build edits (inserts_before + deletes).
    size_t i = n;
    size_t j = m;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && base[i - 1] == other[j - 1]) {
            --i;
            --j;
            continue;
        }
        if (j > 0 && (i == 0 || at(i, j - 1) >= at(i - 1, j))) {
            // Insert other[j-1] before base[i]
            edits.inserts_before[i].push_back(other[j - 1]);
            --j;
            continue;
        }
        if (i > 0) {
            edits.deletes[i - 1] = true;
            --i;
            continue;
        }
    }

    for (auto& bucket : edits.inserts_before) {
        std::reverse(bucket.begin(), bucket.end());
    }
    return edits;
}

bool lines_equal(const Lines& a, const Lines& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

Lines conflict_chunk(const Lines& ours, const Lines& theirs) {
    Lines out;
    out.reserve(ours.size() + theirs.size() + 5);
    out.push_back("<<<<<<< ours");
    out.insert(out.end(), ours.begin(), ours.end());
    out.push_back("=======");
    out.insert(out.end(), theirs.begin(), theirs.end());
    out.push_back(">>>>>>> theirs");
    return out;
}

} // namespace

ThreeWayMergeResult three_way_merge_text(std::string_view base_text,
                                        std::string_view ours_text,
                                        std::string_view theirs_text) {
    if (ours_text == theirs_text) {
        return ThreeWayMergeResult{ThreeWayMergeResult::Kind::Clean, std::string(ours_text)};
    }
    if (ours_text == base_text) {
        return ThreeWayMergeResult{ThreeWayMergeResult::Kind::Clean, std::string(theirs_text)};
    }
    if (theirs_text == base_text) {
        return ThreeWayMergeResult{ThreeWayMergeResult::Kind::Clean, std::string(ours_text)};
    }

    const auto base = split_lines(base_text);
    const auto ours = split_lines(ours_text);
    const auto theirs = split_lines(theirs_text);

    // Keep this small: we want deterministic behavior and bounded memory.
    static constexpr size_t cell_limit = 2'000'000; // ~8MB ints worst case

    const auto ours_edits = diff_edits_from_base(base, ours, cell_limit);
    const auto theirs_edits = diff_edits_from_base(base, theirs, cell_limit);

    bool clean = true;
    bool too_large = ((base.size() + 1) * (ours.size() + 1) > cell_limit) ||
                     ((base.size() + 1) * (theirs.size() + 1) > cell_limit);

    Lines merged;
    merged.reserve(std::max({base.size(), ours.size(), theirs.size()}) + 16);

    const auto emit_inserts = [&](const Lines& a, const Lines& b) {
        if (a.empty() && b.empty()) return;
        if (a.empty()) {
            merged.insert(merged.end(), b.begin(), b.end());
            return;
        }
        if (b.empty()) {
            merged.insert(merged.end(), a.begin(), a.end());
            return;
        }
        if (lines_equal(a, b)) {
            merged.insert(merged.end(), a.begin(), a.end());
            return;
        }
        clean = false;
        const auto chunk = conflict_chunk(a, b);
        merged.insert(merged.end(), chunk.begin(), chunk.end());
    };

    for (size_t i = 0; i < base.size(); ++i) {
        emit_inserts(ours_edits.inserts_before[i], theirs_edits.inserts_before[i]);

        const bool ours_deleted = ours_edits.deletes[i];
        const bool theirs_deleted = theirs_edits.deletes[i];
        if (ours_deleted || theirs_deleted) {
            // If either side deleted the base line and the other side did not change it,
            // deletion is safe to apply. Overlaps are handled via inserts conflicts.
            continue;
        }
        merged.push_back(base[i]);
    }
    emit_inserts(ours_edits.inserts_before[base.size()], theirs_edits.inserts_before[base.size()]);

    if (too_large) {
        return ThreeWayMergeResult{ThreeWayMergeResult::Kind::TooLargeFallback, join_lines(merged)};
    }
    return ThreeWayMergeResult{
        clean ? ThreeWayMergeResult::Kind::Clean : ThreeWayMergeResult::Kind::Conflict,
        join_lines(merged),
    };
}

} // namespace zinc

