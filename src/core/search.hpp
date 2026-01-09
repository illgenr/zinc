#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include <string>
#include <vector>

namespace zinc {

/**
 * SearchResult - A single search result.
 */
struct SearchResult {
    Uuid block_id;
    Uuid page_id;
    std::string page_title;
    std::string snippet;      // Highlighted snippet of matching text
    double rank;              // FTS5 rank score
    
    bool operator==(const SearchResult&) const = default;
};

/**
 * SearchQuery - Parsed search query with options.
 */
struct SearchQuery {
    std::string text;
    bool match_case{false};
    bool whole_word{false};
    std::optional<Uuid> page_filter;  // Search within specific page
    int limit{50};
    int offset{0};
};

/**
 * Highlight matches in text with markers.
 * 
 * @param text The original text
 * @param query The search query
 * @param marker_start Start marker (e.g., "<mark>")
 * @param marker_end End marker (e.g., "</mark>")
 * @return Text with matches highlighted
 */
[[nodiscard]] inline std::string highlight_matches(
    std::string_view text,
    std::string_view query,
    std::string_view marker_start = "<mark>",
    std::string_view marker_end = "</mark>"
) {
    if (query.empty()) return std::string(text);
    
    std::string result;
    result.reserve(text.size() * 2);
    
    // Simple case-insensitive highlighting
    auto lower_text = std::string(text);
    auto lower_query = std::string(query);
    std::transform(lower_text.begin(), lower_text.end(), 
                  lower_text.begin(), ::tolower);
    std::transform(lower_query.begin(), lower_query.end(), 
                  lower_query.begin(), ::tolower);
    
    size_t pos = 0;
    size_t last_pos = 0;
    
    while ((pos = lower_text.find(lower_query, last_pos)) != std::string::npos) {
        // Add text before match
        result.append(text.substr(last_pos, pos - last_pos));
        // Add highlighted match (using original case)
        result.append(marker_start);
        result.append(text.substr(pos, query.size()));
        result.append(marker_end);
        last_pos = pos + query.size();
    }
    
    // Add remaining text
    result.append(text.substr(last_pos));
    
    return result;
}

/**
 * Create a snippet around a match.
 * 
 * @param text The full text
 * @param query The search query
 * @param context_chars Number of characters before/after match to include
 * @return Snippet with ellipsis if truncated
 */
[[nodiscard]] inline std::string create_snippet(
    std::string_view text,
    std::string_view query,
    size_t context_chars = 50
) {
    if (query.empty() || text.empty()) {
        // Return beginning of text
        if (text.size() <= context_chars * 2) {
            return std::string(text);
        }
        return std::string(text.substr(0, context_chars * 2)) + "...";
    }
    
    // Find first match (case-insensitive)
    auto lower_text = std::string(text);
    auto lower_query = std::string(query);
    std::transform(lower_text.begin(), lower_text.end(), 
                  lower_text.begin(), ::tolower);
    std::transform(lower_query.begin(), lower_query.end(), 
                  lower_query.begin(), ::tolower);
    
    size_t match_pos = lower_text.find(lower_query);
    if (match_pos == std::string::npos) {
        // No match, return beginning
        if (text.size() <= context_chars * 2) {
            return std::string(text);
        }
        return std::string(text.substr(0, context_chars * 2)) + "...";
    }
    
    // Calculate snippet bounds
    size_t start = (match_pos > context_chars) ? match_pos - context_chars : 0;
    size_t end = std::min(text.size(), match_pos + query.size() + context_chars);
    
    std::string snippet;
    if (start > 0) snippet += "...";
    snippet += text.substr(start, end - start);
    if (end < text.size()) snippet += "...";
    
    return snippet;
}

} // namespace zinc

