#include <catch2/catch_test_macros.hpp>
#include <rapidcheck.h>
#include "core/fractional_index.hpp"
#include <algorithm>

using namespace zinc;

namespace rc {

// Generator for valid FractionalIndex strings
template<>
struct Arbitrary<FractionalIndex> {
    static Gen<FractionalIndex> arbitrary() {
        return gen::map(
            gen::container<std::string>(
                gen::elementOf(std::string(FractionalIndex::DIGITS))
            ),
            [](std::string s) {
                if (s.empty()) return FractionalIndex::first();
                return FractionalIndex(s);
            }
        );
    }
};

} // namespace rc

TEST_CASE("Property: between always produces ordered result", "[property][fractional_index]") {
    rc::check("between(a, b) produces a < middle < b when a < b",
        [](const FractionalIndex& a, const FractionalIndex& b) {
            if (a >= b) return true;  // Skip invalid inputs
            
            auto middle = FractionalIndex::between(a, b);
            RC_ASSERT(a < middle);
            RC_ASSERT(middle < b);
            return true;
        }
    );
}

TEST_CASE("Property: before produces smaller index", "[property][fractional_index]") {
    rc::check("idx.before() < idx",
        [](const FractionalIndex& idx) {
            if (idx.is_empty()) return true;
            
            auto before = idx.before();
            RC_ASSERT(before < idx);
            return true;
        }
    );
}

TEST_CASE("Property: after produces larger index", "[property][fractional_index]") {
    rc::check("idx < idx.after()",
        [](const FractionalIndex& idx) {
            if (idx.is_empty()) return true;
            
            auto after = idx.after();
            RC_ASSERT(idx < after);
            return true;
        }
    );
}

TEST_CASE("Property: repeated insertions maintain order", "[property][fractional_index]") {
    rc::check("repeated between() calls maintain strict ordering",
        [](std::vector<bool> directions) {
            if (directions.size() < 2) return true;
            
            std::vector<FractionalIndex> indices;
            indices.push_back(FractionalIndex::first());
            
            for (bool insert_after : directions) {
                if (insert_after) {
                    // Insert at end
                    auto new_idx = FractionalIndex::between(
                        indices.back(), 
                        FractionalIndex{}
                    );
                    indices.push_back(new_idx);
                } else {
                    // Insert at beginning
                    auto new_idx = FractionalIndex::between(
                        FractionalIndex{},
                        indices.front()
                    );
                    indices.insert(indices.begin(), new_idx);
                }
            }
            
            // Verify strict ordering
            for (size_t i = 1; i < indices.size(); ++i) {
                RC_ASSERT(indices[i - 1] < indices[i]);
            }
            
            return true;
        }
    );
}

TEST_CASE("Property: comparison is transitive", "[property][fractional_index]") {
    rc::check("if a < b and b < c then a < c",
        [](const FractionalIndex& a, const FractionalIndex& b, const FractionalIndex& c) {
            if (a < b && b < c) {
                RC_ASSERT(a < c);
            }
            return true;
        }
    );
}

TEST_CASE("Property: equality is reflexive and symmetric", "[property][fractional_index]") {
    rc::check("equality properties",
        [](const FractionalIndex& a, const FractionalIndex& b) {
            // Reflexive
            RC_ASSERT(a == a);
            
            // Symmetric
            if (a == b) {
                RC_ASSERT(b == a);
            }
            
            return true;
        }
    );
}

TEST_CASE("Property: string round-trip preserves value", "[property][fractional_index]") {
    rc::check("FractionalIndex(idx.value()) == idx",
        [](const FractionalIndex& idx) {
            auto round_tripped = FractionalIndex(idx.value());
            RC_ASSERT(round_tripped == idx);
            return true;
        }
    );
}

