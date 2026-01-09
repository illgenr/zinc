#pragma once

#include "crypto/keys.hpp"
#include "crypto/encryption.hpp"
#include "core/result.hpp"
#include <vector>
#include <memory>
#include <cstring>

#ifdef ZINC_HAS_SODIUM
#include <sodium.h>
#endif

namespace zinc::crypto {

/**
 * NoiseSession - Implements Noise Protocol XX handshake for secure channels.
 * 
 * Noise_XX pattern:
 *   -> e                     (initiator sends ephemeral)
 *   <- e, ee, s, es         (responder sends ephemeral, static, mixed keys)
 *   -> s, se                (initiator sends static, mixes keys)
 * 
 * After handshake, both parties have:
 * - Forward secrecy (ephemeral keys)
 * - Mutual authentication (static keys)
 * - Encrypted channel
 */

enum class NoiseRole {
    Initiator,
    Responder
};

enum class NoiseState {
    Initial,
    WaitingForEphemeral,
    WaitingForResponse,
    WaitingForFinal,
    Transport,
    Failed
};

/**
 * Handshake message types
 */
struct NoiseMessage1 {
    PublicKey ephemeral;
};

struct NoiseMessage2 {
    PublicKey ephemeral;
    std::vector<uint8_t> encrypted_static;
    std::vector<uint8_t> encrypted_payload;
};

struct NoiseMessage3 {
    std::vector<uint8_t> encrypted_static;
    std::vector<uint8_t> encrypted_payload;
};

/**
 * NoiseSession - Manages a Noise Protocol session.
 */
class NoiseSession {
public:
    NoiseSession(NoiseRole role, const KeyPair& local_static);
    
    [[nodiscard]] NoiseState state() const { return state_; }
    [[nodiscard]] bool is_transport_ready() const { return state_ == NoiseState::Transport; }
    [[nodiscard]] const PublicKey& remote_static_key() const { return remote_static_; }
    
    // Handshake operations
    [[nodiscard]] Result<NoiseMessage1, Error> create_message1();
    [[nodiscard]] Result<NoiseMessage2, Error> process_message1(
        const NoiseMessage1& msg, std::span<const uint8_t> payload = {});
    [[nodiscard]] Result<NoiseMessage3, Error> process_message2(
        const NoiseMessage2& msg, std::span<const uint8_t> payload = {});
    [[nodiscard]] Result<std::vector<uint8_t>, Error> process_message3(const NoiseMessage3& msg);
    
    // Transport operations
    [[nodiscard]] Result<std::vector<uint8_t>, Error> encrypt(std::span<const uint8_t> plaintext);
    [[nodiscard]] Result<std::vector<uint8_t>, Error> decrypt(std::span<const uint8_t> ciphertext);

private:
    NoiseRole role_;
    NoiseState state_ = NoiseState::Initial;
    
    KeyPair local_static_;
    PublicKey remote_static_;
    KeyPair local_ephemeral_;
    PublicKey remote_ephemeral_;
    
    SymmetricKey chaining_key_;
    SymmetricKey send_key_;
    SymmetricKey recv_key_;
    uint64_t send_nonce_ = 0;
    uint64_t recv_nonce_ = 0;
    
    std::vector<uint8_t> hash_state_;
    
    void mix_key(const std::vector<uint8_t>& input_key_material);
    void mix_hash(const std::vector<uint8_t>& data);
    [[nodiscard]] std::vector<uint8_t> dh(const SecretKey& secret, const PublicKey& pub);
    void split_keys();
};

// Serialization
[[nodiscard]] std::vector<uint8_t> serialize_message1(const NoiseMessage1& msg);
[[nodiscard]] std::vector<uint8_t> serialize_message2(const NoiseMessage2& msg);
[[nodiscard]] std::vector<uint8_t> serialize_message3(const NoiseMessage3& msg);

[[nodiscard]] Result<NoiseMessage1, Error> deserialize_message1(std::span<const uint8_t> data);
[[nodiscard]] Result<NoiseMessage2, Error> deserialize_message2(std::span<const uint8_t> data);
[[nodiscard]] Result<NoiseMessage3, Error> deserialize_message3(std::span<const uint8_t> data);

} // namespace zinc::crypto
