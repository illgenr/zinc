#pragma once

#include "core/result.hpp"
#include "core/types.hpp"
#include <vector>
#include <array>
#include <string>
#include <random>
#include <cstring>

#ifdef ZINC_HAS_SODIUM
#include <sodium.h>
#endif

namespace zinc::crypto {

// Key sizes (compatible with libsodium when available)
constexpr size_t PUBLIC_KEY_SIZE = 32;
constexpr size_t SECRET_KEY_SIZE = 32;
constexpr size_t SYMMETRIC_KEY_SIZE = 32;
constexpr size_t SEED_SIZE = 32;
constexpr size_t SIGNATURE_SIZE = 64;
constexpr size_t SALT_SIZE = 16;

// Type aliases for clarity
using PublicKey = std::array<uint8_t, PUBLIC_KEY_SIZE>;
using SecretKey = std::array<uint8_t, SECRET_KEY_SIZE>;
using SymmetricKey = std::array<uint8_t, SYMMETRIC_KEY_SIZE>;
using Seed = std::array<uint8_t, SEED_SIZE>;
using Signature = std::array<uint8_t, SIGNATURE_SIZE>;
using Salt = std::array<uint8_t, SALT_SIZE>;

/**
 * KeyPair - A public/private key pair for asymmetric cryptography.
 */
struct KeyPair {
    PublicKey public_key;
    SecretKey secret_key;
};

/**
 * SigningKeyPair - A public/private key pair for digital signatures.
 */
struct SigningKeyPair {
    std::array<uint8_t, 32> public_key;
    std::array<uint8_t, 64> secret_key;
};

namespace detail {
    inline std::mt19937& get_rng() {
        static std::random_device rd;
        static std::mt19937 gen(rd());
        return gen;
    }
    
    inline void fill_random(uint8_t* data, size_t len) {
#ifdef ZINC_HAS_SODIUM
        randombytes_buf(data, len);
#else
        std::uniform_int_distribution<uint16_t> dist(0, 255);
        for (size_t i = 0; i < len; ++i) {
            data[i] = static_cast<uint8_t>(dist(get_rng()));
        }
#endif
    }
}

/**
 * Initialize the crypto library.
 */
[[nodiscard]] inline Result<void, Error> init() {
#ifdef ZINC_HAS_SODIUM
    if (sodium_init() < 0) {
        return Result<void, Error>::err(Error{"Failed to initialize libsodium"});
    }
#endif
    return Result<void, Error>::ok();
}

/**
 * Generate a new random key pair.
 * Note: Without libsodium, this generates random bytes (NOT cryptographically secure for real use).
 */
[[nodiscard]] inline KeyPair generate_keypair() {
    KeyPair kp;
#ifdef ZINC_HAS_SODIUM
    crypto_box_keypair(kp.public_key.data(), kp.secret_key.data());
#else
    detail::fill_random(kp.public_key.data(), PUBLIC_KEY_SIZE);
    detail::fill_random(kp.secret_key.data(), SECRET_KEY_SIZE);
#endif
    return kp;
}

/**
 * Generate a key pair from a seed (deterministic).
 */
[[nodiscard]] inline KeyPair keypair_from_seed(const Seed& seed) {
    KeyPair kp;
#ifdef ZINC_HAS_SODIUM
    crypto_box_seed_keypair(kp.public_key.data(), kp.secret_key.data(), seed.data());
#else
    // Simple deterministic derivation (NOT secure, just for testing)
    std::memcpy(kp.public_key.data(), seed.data(), PUBLIC_KEY_SIZE);
    for (size_t i = 0; i < SECRET_KEY_SIZE; ++i) {
        kp.secret_key[i] = seed[i] ^ 0xFF;
    }
#endif
    return kp;
}

/**
 * Generate a new signing key pair.
 */
[[nodiscard]] inline SigningKeyPair generate_signing_keypair() {
    SigningKeyPair kp;
#ifdef ZINC_HAS_SODIUM
    crypto_sign_keypair(kp.public_key.data(), kp.secret_key.data());
#else
    detail::fill_random(kp.public_key.data(), 32);
    detail::fill_random(kp.secret_key.data(), 64);
#endif
    return kp;
}

/**
 * Generate a random symmetric key.
 */
[[nodiscard]] inline SymmetricKey generate_symmetric_key() {
    SymmetricKey key;
#ifdef ZINC_HAS_SODIUM
    crypto_secretbox_keygen(key.data());
#else
    detail::fill_random(key.data(), SYMMETRIC_KEY_SIZE);
#endif
    return key;
}

/**
 * Derive a symmetric key from a password using Argon2id (when available).
 */
[[nodiscard]] inline Result<SymmetricKey, Error> derive_key_from_password(
    const std::string& password,
    const Salt& salt
) {
    SymmetricKey key;
    
#ifdef ZINC_HAS_SODIUM
    int result = crypto_pwhash(
        key.data(), key.size(),
        password.c_str(), password.size(),
        salt.data(),
        crypto_pwhash_OPSLIMIT_INTERACTIVE,
        crypto_pwhash_MEMLIMIT_INTERACTIVE,
        crypto_pwhash_ALG_DEFAULT
    );
    
    if (result != 0) {
        return Result<SymmetricKey, Error>::err(Error{"Key derivation failed"});
    }
#else
    // Simple fallback (NOT secure)
    size_t key_idx = 0;
    for (size_t i = 0; i < password.size() && key_idx < SYMMETRIC_KEY_SIZE; ++i, ++key_idx) {
        key[key_idx] = static_cast<uint8_t>(password[i]) ^ salt[key_idx % SALT_SIZE];
    }
    for (; key_idx < SYMMETRIC_KEY_SIZE; ++key_idx) {
        key[key_idx] = salt[key_idx % SALT_SIZE];
    }
#endif
    
    return Result<SymmetricKey, Error>::ok(key);
}

/**
 * Generate a random salt.
 */
[[nodiscard]] inline Salt generate_salt() {
    Salt salt;
    detail::fill_random(salt.data(), salt.size());
    return salt;
}

/**
 * Generate random bytes.
 */
[[nodiscard]] inline std::vector<uint8_t> random_bytes(size_t count) {
    std::vector<uint8_t> bytes(count);
    detail::fill_random(bytes.data(), count);
    return bytes;
}

/**
 * Generate a 6-digit numeric pairing code.
 */
[[nodiscard]] inline std::string generate_pairing_code() {
    std::vector<uint8_t> bytes(4);
    detail::fill_random(bytes.data(), bytes.size());
    uint32_t code = (bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24));
    code = code % 1000000;  // 6 digits
    
    char buffer[7];
    snprintf(buffer, sizeof(buffer), "%06u", code);
    return buffer;
}

/**
 * Compute hash.
 */
[[nodiscard]] inline std::vector<uint8_t> hash(
    const std::vector<uint8_t>& data,
    size_t hash_size = 32
) {
#ifdef ZINC_HAS_SODIUM
    std::vector<uint8_t> out(hash_size);
    crypto_generichash(out.data(), hash_size, data.data(), data.size(), nullptr, 0);
    return out;
#else
    // Simple non-cryptographic hash (for testing only)
    std::vector<uint8_t> out(hash_size, 0);
    for (size_t i = 0; i < data.size(); ++i) {
        out[i % hash_size] ^= data[i];
        out[(i + 1) % hash_size] += data[i];
    }
    return out;
#endif
}

/**
 * Compute fingerprint (short hash) of a public key.
 */
[[nodiscard]] inline std::vector<uint8_t> fingerprint(const PublicKey& key) {
    return hash(std::vector<uint8_t>(key.begin(), key.end()), 8);
}

/**
 * Encode bytes as Base64.
 */
[[nodiscard]] inline std::string to_base64(const std::vector<uint8_t>& data) {
    static const char* chars = 
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    
    std::string result;
    result.reserve((data.size() + 2) / 3 * 4);
    
    for (size_t i = 0; i < data.size(); i += 3) {
        uint32_t n = static_cast<uint32_t>(data[i]) << 16;
        if (i + 1 < data.size()) n |= static_cast<uint32_t>(data[i + 1]) << 8;
        if (i + 2 < data.size()) n |= static_cast<uint32_t>(data[i + 2]);
        
        result += chars[(n >> 18) & 0x3F];
        result += chars[(n >> 12) & 0x3F];
        result += (i + 1 < data.size()) ? chars[(n >> 6) & 0x3F] : '=';
        result += (i + 2 < data.size()) ? chars[n & 0x3F] : '=';
    }
    
    return result;
}

/**
 * Decode Base64 to bytes.
 */
[[nodiscard]] inline Result<std::vector<uint8_t>, Error> from_base64(const std::string& b64) {
    static const int8_t decode_table[256] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
        52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
        15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    };
    
    std::vector<uint8_t> result;
    result.reserve(b64.size() * 3 / 4);
    
    uint32_t accum = 0;
    int bits = 0;
    
    for (char c : b64) {
        if (c == '=') break;
        int8_t val = decode_table[static_cast<uint8_t>(c)];
        if (val < 0) {
            return Result<std::vector<uint8_t>, Error>::err(Error{"Invalid Base64"});
        }
        accum = (accum << 6) | val;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            result.push_back(static_cast<uint8_t>((accum >> bits) & 0xFF));
        }
    }
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(result));
}

/**
 * Securely zero memory.
 */
inline void secure_zero(void* ptr, size_t len) {
#ifdef ZINC_HAS_SODIUM
    sodium_memzero(ptr, len);
#else
    volatile uint8_t* p = static_cast<volatile uint8_t*>(ptr);
    while (len--) {
        *p++ = 0;
    }
#endif
}

/**
 * Constant-time comparison.
 */
[[nodiscard]] inline bool secure_compare(
    const std::vector<uint8_t>& a,
    const std::vector<uint8_t>& b
) {
    if (a.size() != b.size()) return false;
#ifdef ZINC_HAS_SODIUM
    return sodium_memcmp(a.data(), b.data(), a.size()) == 0;
#else
    volatile uint8_t diff = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        diff |= a[i] ^ b[i];
    }
    return diff == 0;
#endif
}

} // namespace zinc::crypto
