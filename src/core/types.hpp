#pragma once

#include <string>
#include <chrono>
#include <array>
#include <cstdint>
#include <compare>
#include <random>
#include <sstream>
#include <iomanip>

namespace zinc {

/**
 * UUID - Universally Unique Identifier.
 * 
 * A 128-bit identifier stored as 16 bytes. Provides generation,
 * parsing, and string conversion.
 */
class Uuid {
public:
    static constexpr size_t BYTE_SIZE = 16;
    using Bytes = std::array<uint8_t, BYTE_SIZE>;
    
    /**
     * Create a nil (all zeros) UUID.
     */
    constexpr Uuid() noexcept : bytes_{} {}
    
    /**
     * Create a UUID from raw bytes.
     */
    explicit constexpr Uuid(Bytes bytes) noexcept : bytes_(bytes) {}
    
    /**
     * Generate a new random UUID (version 4).
     */
    [[nodiscard]] static Uuid generate() {
        static thread_local std::random_device rd;
        static thread_local std::mt19937_64 gen(rd());
        static thread_local std::uniform_int_distribution<uint64_t> dist;
        
        Bytes bytes;
        auto* ptr = reinterpret_cast<uint64_t*>(bytes.data());
        ptr[0] = dist(gen);
        ptr[1] = dist(gen);
        
        // Set version 4 (random)
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        // Set variant (RFC 4122)
        bytes[8] = (bytes[8] & 0x3F) | 0x80;
        
        return Uuid(bytes);
    }
    
    /**
     * Parse a UUID from a string (accepts both hyphenated and non-hyphenated).
     */
    [[nodiscard]] static std::optional<Uuid> parse(std::string_view str) {
        // Remove hyphens
        std::string clean;
        clean.reserve(32);
        for (char c : str) {
            if (c != '-') clean += c;
        }
        
        if (clean.size() != 32) return std::nullopt;
        
        Bytes bytes;
        for (size_t i = 0; i < 16; ++i) {
            auto hex = clean.substr(i * 2, 2);
            try {
                bytes[i] = static_cast<uint8_t>(std::stoul(std::string(hex), nullptr, 16));
            } catch (...) {
                return std::nullopt;
            }
        }
        
        return Uuid(bytes);
    }
    
    /**
     * Convert to string representation (hyphenated, lowercase).
     * Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     */
    [[nodiscard]] std::string to_string() const {
        std::ostringstream oss;
        oss << std::hex << std::setfill('0');
        
        for (size_t i = 0; i < BYTE_SIZE; ++i) {
            if (i == 4 || i == 6 || i == 8 || i == 10) {
                oss << '-';
            }
            oss << std::setw(2) << static_cast<int>(bytes_[i]);
        }
        
        return oss.str();
    }
    
    /**
     * Check if this is a nil UUID (all zeros).
     */
    [[nodiscard]] constexpr bool is_nil() const noexcept {
        for (auto b : bytes_) {
            if (b != 0) return false;
        }
        return true;
    }
    
    /**
     * Get the raw bytes.
     */
    [[nodiscard]] constexpr const Bytes& bytes() const noexcept {
        return bytes_;
    }
    
    auto operator<=>(const Uuid&) const = default;
    bool operator==(const Uuid&) const = default;
    
private:
    Bytes bytes_;
};

/**
 * Timestamp - Represents a point in time.
 * 
 * Stored as milliseconds since Unix epoch for SQLite compatibility.
 */
class Timestamp {
public:
    using Duration = std::chrono::milliseconds;
    using Clock = std::chrono::system_clock;
    using TimePoint = std::chrono::time_point<Clock, Duration>;
    
    /**
     * Create a timestamp at the Unix epoch.
     */
    constexpr Timestamp() noexcept : millis_(0) {}
    
    /**
     * Create a timestamp from milliseconds since epoch.
     */
    explicit constexpr Timestamp(int64_t millis) noexcept : millis_(millis) {}
    
    /**
     * Create a timestamp from a time point.
     */
    explicit Timestamp(TimePoint tp) noexcept 
        : millis_(std::chrono::duration_cast<Duration>(tp.time_since_epoch()).count()) {}
    
    /**
     * Get the current time.
     */
    [[nodiscard]] static Timestamp now() {
        return Timestamp(std::chrono::time_point_cast<Duration>(Clock::now()));
    }
    
    /**
     * Get milliseconds since epoch.
     */
    [[nodiscard]] constexpr int64_t millis() const noexcept {
        return millis_;
    }
    
    /**
     * Convert to time point.
     */
    [[nodiscard]] TimePoint to_time_point() const noexcept {
        return TimePoint(Duration(millis_));
    }
    
    /**
     * Format as ISO 8601 string.
     */
    [[nodiscard]] std::string to_iso_string() const {
        auto tp = to_time_point();
        auto time_t = Clock::to_time_t(tp);
        std::ostringstream oss;
        oss << std::put_time(std::gmtime(&time_t), "%Y-%m-%dT%H:%M:%S");
        
        // Add milliseconds
        auto ms = millis_ % 1000;
        oss << '.' << std::setfill('0') << std::setw(3) << ms << 'Z';
        
        return oss.str();
    }
    
    auto operator<=>(const Timestamp&) const = default;
    bool operator==(const Timestamp&) const = default;
    
    Timestamp operator+(Duration d) const {
        return Timestamp(millis_ + d.count());
    }
    
    Timestamp operator-(Duration d) const {
        return Timestamp(millis_ - d.count());
    }
    
    Duration operator-(const Timestamp& other) const {
        return Duration(millis_ - other.millis_);
    }
    
private:
    int64_t millis_;
};

} // namespace zinc

// Hash specializations for use in std containers
namespace std {
    template<>
    struct hash<zinc::Uuid> {
        size_t operator()(const zinc::Uuid& uuid) const noexcept {
            const auto& bytes = uuid.bytes();
            size_t h = 0;
            for (size_t i = 0; i < bytes.size(); i += sizeof(size_t)) {
                size_t chunk = 0;
                for (size_t j = 0; j < sizeof(size_t) && i + j < bytes.size(); ++j) {
                    chunk |= static_cast<size_t>(bytes[i + j]) << (j * 8);
                }
                h ^= chunk + 0x9e3779b9 + (h << 6) + (h >> 2);
            }
            return h;
        }
    };
}

