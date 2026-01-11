#pragma once

#include "crypto/keys.hpp"
#include "core/result.hpp"
#include <vector>
#include <span>
#include <cstring>

#ifdef ZINC_HAS_SODIUM
#include <sodium.h>
#endif

namespace zinc::crypto {

// Nonce sizes
constexpr size_t SECRETBOX_NONCE_SIZE = 24;
constexpr size_t BOX_NONCE_SIZE = 24;

// MAC (authentication tag) sizes
constexpr size_t SECRETBOX_MAC_SIZE = 16;
constexpr size_t BOX_MAC_SIZE = 16;

/**
 * Encrypt data with a symmetric key.
 * Note: Without libsodium, this uses a simple XOR (NOT secure, for testing only).
 */
[[nodiscard]] inline Result<std::vector<uint8_t>, Error> encrypt_symmetric(
    std::span<const uint8_t> plaintext,
    const SymmetricKey& key
) {
    // Generate random nonce
    std::vector<uint8_t> nonce(SECRETBOX_NONCE_SIZE);
    detail::fill_random(nonce.data(), nonce.size());
    
#ifdef ZINC_HAS_SODIUM
    // Allocate output: nonce + ciphertext + mac
    std::vector<uint8_t> output(nonce.size() + plaintext.size() + SECRETBOX_MAC_SIZE);
    
    // Copy nonce to output
    std::copy(nonce.begin(), nonce.end(), output.begin());
    
    // Encrypt
    int result = crypto_secretbox_easy(
        output.data() + nonce.size(),
        plaintext.data(), plaintext.size(),
        nonce.data(),
        key.data()
    );
    
    if (result != 0) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Encryption failed"});
    }
#else
    // Simple XOR cipher (NOT secure, for testing only)
    std::vector<uint8_t> output(nonce.size() + plaintext.size() + SECRETBOX_MAC_SIZE);
    std::copy(nonce.begin(), nonce.end(), output.begin());
    
    for (size_t i = 0; i < plaintext.size(); ++i) {
        output[nonce.size() + i] = plaintext[i] ^ key[i % SYMMETRIC_KEY_SIZE] ^ nonce[i % SECRETBOX_NONCE_SIZE];
    }
    
    // Simple MAC (just XOR all bytes)
    uint8_t mac = 0;
    for (size_t i = 0; i < plaintext.size(); ++i) {
        mac ^= plaintext[i];
    }
    for (size_t i = 0; i < SECRETBOX_MAC_SIZE; ++i) {
        output[nonce.size() + plaintext.size() + i] = mac ^ key[i];
    }
#endif
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(output));
}

/**
 * Decrypt data with a symmetric key.
 */
[[nodiscard]] inline Result<std::vector<uint8_t>, Error> decrypt_symmetric(
    std::span<const uint8_t> ciphertext,
    const SymmetricKey& key
) {
    if (ciphertext.size() < SECRETBOX_NONCE_SIZE + SECRETBOX_MAC_SIZE) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Ciphertext too short"});
    }
    
#ifdef ZINC_HAS_SODIUM
    // Extract nonce
    const uint8_t* nonce = ciphertext.data();
    const uint8_t* encrypted = ciphertext.data() + SECRETBOX_NONCE_SIZE;
    size_t encrypted_len = ciphertext.size() - SECRETBOX_NONCE_SIZE;
    
    // Allocate output
    std::vector<uint8_t> plaintext(encrypted_len - SECRETBOX_MAC_SIZE);
    
    // Decrypt
    int result = crypto_secretbox_open_easy(
        plaintext.data(),
        encrypted, encrypted_len,
        nonce,
        key.data()
    );
    
    if (result != 0) {
        return Result<std::vector<uint8_t>, Error>::err(
            Error{"Decryption failed (invalid key or corrupted data)"});
    }
#else
    // Simple XOR decipher
    const uint8_t* nonce = ciphertext.data();
    size_t plaintext_size = ciphertext.size() - SECRETBOX_NONCE_SIZE - SECRETBOX_MAC_SIZE;
    std::vector<uint8_t> plaintext(plaintext_size);
    
    for (size_t i = 0; i < plaintext_size; ++i) {
        plaintext[i] = ciphertext[SECRETBOX_NONCE_SIZE + i] ^ key[i % SYMMETRIC_KEY_SIZE] ^ nonce[i % SECRETBOX_NONCE_SIZE];
    }

    // Validate the simple MAC used in encrypt_symmetric (NOT secure, test-only).
    uint8_t mac = 0;
    for (size_t i = 0; i < plaintext.size(); ++i) {
        mac ^= plaintext[i];
    }
    const size_t mac_offset = SECRETBOX_NONCE_SIZE + plaintext_size;
    for (size_t i = 0; i < SECRETBOX_MAC_SIZE; ++i) {
        const uint8_t expected = mac ^ key[i];
        if (ciphertext[mac_offset + i] != expected) {
            return Result<std::vector<uint8_t>, Error>::err(
                Error{"Decryption failed (invalid key or corrupted data)"});
        }
    }
#endif
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(plaintext));
}

/**
 * Encrypt data with a recipient's public key.
 */
[[nodiscard]] inline Result<std::vector<uint8_t>, Error> encrypt_asymmetric(
    std::span<const uint8_t> plaintext,
    const PublicKey& recipient_public_key,
    const SecretKey& sender_secret_key
) {
#ifdef ZINC_HAS_SODIUM
    // Generate random nonce
    std::vector<uint8_t> nonce(BOX_NONCE_SIZE);
    randombytes_buf(nonce.data(), nonce.size());
    
    // Allocate output
    std::vector<uint8_t> output(nonce.size() + plaintext.size() + BOX_MAC_SIZE);
    
    // Copy nonce to output
    std::copy(nonce.begin(), nonce.end(), output.begin());
    
    // Encrypt
    int result = crypto_box_easy(
        output.data() + nonce.size(),
        plaintext.data(), plaintext.size(),
        nonce.data(),
        recipient_public_key.data(),
        sender_secret_key.data()
    );
    
    if (result != 0) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Encryption failed"});
    }
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(output));
#else
    // Derive a shared key and use symmetric encryption
    SymmetricKey shared_key;
    for (size_t i = 0; i < SYMMETRIC_KEY_SIZE; ++i) {
        shared_key[i] = recipient_public_key[i] ^ sender_secret_key[i];
    }
    return encrypt_symmetric(plaintext, shared_key);
#endif
}

/**
 * Decrypt data encrypted with our public key.
 */
[[nodiscard]] inline Result<std::vector<uint8_t>, Error> decrypt_asymmetric(
    std::span<const uint8_t> ciphertext,
    const PublicKey& sender_public_key,
    const SecretKey& recipient_secret_key
) {
#ifdef ZINC_HAS_SODIUM
    if (ciphertext.size() < BOX_NONCE_SIZE + BOX_MAC_SIZE) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Ciphertext too short"});
    }
    
    // Extract nonce
    const uint8_t* nonce = ciphertext.data();
    const uint8_t* encrypted = ciphertext.data() + BOX_NONCE_SIZE;
    size_t encrypted_len = ciphertext.size() - BOX_NONCE_SIZE;
    
    // Allocate output
    std::vector<uint8_t> plaintext(encrypted_len - BOX_MAC_SIZE);
    
    // Decrypt
    int result = crypto_box_open_easy(
        plaintext.data(),
        encrypted, encrypted_len,
        nonce,
        sender_public_key.data(),
        recipient_secret_key.data()
    );
    
    if (result != 0) {
        return Result<std::vector<uint8_t>, Error>::err(
            Error{"Decryption failed (invalid key or corrupted data)"});
    }
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(plaintext));
#else
    // Derive a shared key and use symmetric decryption
    SymmetricKey shared_key;
    for (size_t i = 0; i < SYMMETRIC_KEY_SIZE; ++i) {
        shared_key[i] = sender_public_key[i] ^ recipient_secret_key[i];
    }
    return decrypt_symmetric(ciphertext, shared_key);
#endif
}

/**
 * Sign a message (stub without libsodium).
 */
[[nodiscard]] inline Signature sign(
    std::span<const uint8_t> message,
    const std::array<uint8_t, 64>& secret_key
) {
    Signature sig;
#ifdef ZINC_HAS_SODIUM
    crypto_sign_detached(sig.data(), nullptr, message.data(), message.size(), secret_key.data());
#else
    // Simple non-secure signature
    std::fill(sig.begin(), sig.end(), 0);
    for (size_t i = 0; i < message.size() && i < SIGNATURE_SIZE; ++i) {
        sig[i] = message[i] ^ secret_key[i % 64];
    }
#endif
    return sig;
}

/**
 * Verify a signature (stub without libsodium).
 */
[[nodiscard]] inline bool verify_signature(
    std::span<const uint8_t> message,
    const Signature& signature,
    const std::array<uint8_t, 32>& public_key
) {
#ifdef ZINC_HAS_SODIUM
    return crypto_sign_verify_detached(
        signature.data(),
        message.data(), message.size(),
        public_key.data()
    ) == 0;
#else
    // Stub - always returns true for testing
    (void)message;
    (void)signature;
    (void)public_key;
    return true;
#endif
}

} // namespace zinc::crypto
