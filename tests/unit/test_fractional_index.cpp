#include <catch2/catch_test_macros.hpp>
#include "core/fractional_index.hpp"
#include <algorithm>
#include <vector>

using namespace zinc;

TEST_CASE("FractionalIndex basics", "[fractional_index]") {
    SECTION("Default constructor creates empty index") {
        FractionalIndex idx;
        REQUIRE(idx.is_empty());
        REQUIRE(idx.value() == "");
    }
    
    SECTION("String constructor creates non-empty index") {
        FractionalIndex idx("V");
        REQUIRE_FALSE(idx.is_empty());
        REQUIRE(idx.value() == "V");
    }
    
    SECTION("Invalid characters throw") {
        REQUIRE_THROWS_AS(FractionalIndex("!"), std::invalid_argument);
        REQUIRE_THROWS_AS(FractionalIndex("a-b"), std::invalid_argument);
    }
}

TEST_CASE("FractionalIndex::first()", "[fractional_index]") {
    auto idx = FractionalIndex::first();
    REQUIRE_FALSE(idx.is_empty());
    REQUIRE(idx.value() == "V");  // Midpoint character
}

TEST_CASE("FractionalIndex comparison", "[fractional_index]") {
    FractionalIndex a("a");
    FractionalIndex b("b");
    FractionalIndex aa("aa");
    
    REQUIRE(a < b);
    REQUIRE(a < aa);
    REQUIRE(aa < b);
    
    REQUIRE(a == FractionalIndex("a"));
    REQUIRE_FALSE(a == b);
}

TEST_CASE("FractionalIndex::between generates correct ordering", "[fractional_index]") {
    SECTION("Between two values") {
        FractionalIndex a("a");
        FractionalIndex b("c");
        auto middle = FractionalIndex::between(a, b);
        
        REQUIRE(a < middle);
        REQUIRE(middle < b);
    }
    
    SECTION("At beginning (before first)") {
        FractionalIndex first("V");
        auto before = FractionalIndex::between(FractionalIndex{}, first);
        
        REQUIRE(before < first);
    }
    
    SECTION("At end (after last)") {
        FractionalIndex last("V");
        auto after = FractionalIndex::between(last, FractionalIndex{});
        
        REQUIRE(last < after);
    }
    
    SECTION("Empty to empty gives first()") {
        auto idx = FractionalIndex::between(FractionalIndex{}, FractionalIndex{});
        REQUIRE(idx == FractionalIndex::first());
    }
    
    SECTION("Adjacent values") {
        FractionalIndex a("a");
        FractionalIndex b("b");
        auto middle = FractionalIndex::between(a, b);
        
        REQUIRE(a < middle);
        REQUIRE(middle < b);
    }
}

TEST_CASE("FractionalIndex::before and after", "[fractional_index]") {
    auto idx = FractionalIndex::first();
    
    auto before = idx.before();
    auto after = idx.after();
    
    REQUIRE(before < idx);
    REQUIRE(idx < after);
}

TEST_CASE("FractionalIndex many insertions maintain order", "[fractional_index]") {
    std::vector<FractionalIndex> indices;
    
    // Start with first element
    indices.push_back(FractionalIndex::first());
    
    // Insert 50 elements at random positions
    for (int i = 0; i < 50; ++i) {
        size_t pos = static_cast<size_t>(rand()) % (indices.size() + 1);
        
        FractionalIndex before = (pos > 0) ? indices[pos - 1] : FractionalIndex{};
        FractionalIndex after = (pos < indices.size()) ? indices[pos] : FractionalIndex{};
        
        auto new_idx = FractionalIndex::between(before, after);
        indices.insert(indices.begin() + static_cast<long>(pos), new_idx);
    }
    
    // Verify order is maintained
    for (size_t i = 1; i < indices.size(); ++i) {
        REQUIRE(indices[i - 1] < indices[i]);
    }
}

TEST_CASE("FractionalIndex sorting", "[fractional_index]") {
    std::vector<FractionalIndex> indices = {
        FractionalIndex("z"),
        FractionalIndex("a"),
        FractionalIndex("m"),
        FractionalIndex("A"),
        FractionalIndex("Z"),
    };
    
    std::sort(indices.begin(), indices.end());
    
    // Digits < uppercase < lowercase in base62
    REQUIRE(indices[0].value() == "A");
    REQUIRE(indices[1].value() == "Z");
    REQUIRE(indices[2].value() == "a");
    REQUIRE(indices[3].value() == "m");
    REQUIRE(indices[4].value() == "z");
}

TEST_CASE("FractionalIndex handles edge cases", "[fractional_index]") {
    SECTION("Between close values") {
        FractionalIndex a("V");
        FractionalIndex b("W");
        auto middle = FractionalIndex::between(a, b);
        
        REQUIRE(a < middle);
        REQUIRE(middle < b);
    }
    
    SECTION("Between same prefix different suffix") {
        FractionalIndex a("Va");
        FractionalIndex b("Vz");
        auto middle = FractionalIndex::between(a, b);
        
        REQUIRE(a < middle);
        REQUIRE(middle < b);
    }
    
    SECTION("Invalid order throws") {
        FractionalIndex a("b");
        FractionalIndex b("a");
        
        REQUIRE_THROWS_AS(FractionalIndex::between(a, b), std::invalid_argument);
    }
}

