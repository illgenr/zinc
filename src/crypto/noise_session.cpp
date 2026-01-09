#include "crypto/noise_session.hpp"
#include <cstring>
#include <algorithm>

namespace zinc::crypto {

NoiseSession::NoiseSession(NoiseRole role, const KeyPair& local_static)
    : role_(role)
    , local_static_(local_static)
{
    // Initialize chaining key with protocol name
    const char* protocol_name = "Noise_XX_25519_ChaChaPoly_BLAKE2b";
    hash_state_ = std::vector<uint8_t>(protocol_name, protocol_name + strlen(protocol_name));
    
    // Initialize chaining key
    auto h = hash(hash_state_, SYMMETRIC_KEY_SIZE);
    std::copy(h.begin(), h.end(), chaining_key_.begin());
}

std::vector<uint8_t> NoiseSession::dh(const SecretKey& secret, const PublicKey& pub) {
#ifdef ZINC_HAS_SODIUM
    std::vector<uint8_t> shared(crypto_scalarmult_BYTES);
    crypto_scalarmult(shared.data(), secret.data(), pub.data());
    return shared;
#else
    // Simple XOR-based shared secret (NOT secure)
    std::vector<uint8_t> shared(SYMMETRIC_KEY_SIZE);
    for (size_t i = 0; i < SYMMETRIC_KEY_SIZE; ++i) {
        shared[i] = secret[i] ^ pub[i];
    }
    return shared;
#endif
}

void NoiseSession::mix_key(const std::vector<uint8_t>& input_key_material) {
    std::vector<uint8_t> to_hash;
    to_hash.insert(to_hash.end(), chaining_key_.begin(), chaining_key_.end());
    to_hash.insert(to_hash.end(), input_key_material.begin(), input_key_material.end());
    
    auto h = hash(to_hash, SYMMETRIC_KEY_SIZE * 2);
    std::copy(h.begin(), h.begin() + SYMMETRIC_KEY_SIZE, chaining_key_.begin());
}

void NoiseSession::mix_hash(const std::vector<uint8_t>& data) {
    hash_state_.insert(hash_state_.end(), data.begin(), data.end());
    hash_state_ = hash(hash_state_, 64);
}

void NoiseSession::split_keys() {
    std::vector<uint8_t> temp = hash(
        std::vector<uint8_t>(chaining_key_.begin(), chaining_key_.end()),
        SYMMETRIC_KEY_SIZE * 2
    );
    
    if (role_ == NoiseRole::Initiator) {
        std::copy(temp.begin(), temp.begin() + SYMMETRIC_KEY_SIZE, send_key_.begin());
        std::copy(temp.begin() + SYMMETRIC_KEY_SIZE, temp.end(), recv_key_.begin());
    } else {
        std::copy(temp.begin(), temp.begin() + SYMMETRIC_KEY_SIZE, recv_key_.begin());
        std::copy(temp.begin() + SYMMETRIC_KEY_SIZE, temp.end(), send_key_.begin());
    }
    
    state_ = NoiseState::Transport;
}

Result<NoiseMessage1, Error> NoiseSession::create_message1() {
    if (role_ != NoiseRole::Initiator || state_ != NoiseState::Initial) {
        return Result<NoiseMessage1, Error>::err(Error{"Invalid state for message 1"});
    }
    
    local_ephemeral_ = generate_keypair();
    mix_hash(std::vector<uint8_t>(local_ephemeral_.public_key.begin(), local_ephemeral_.public_key.end()));
    
    state_ = NoiseState::WaitingForResponse;
    return Result<NoiseMessage1, Error>::ok(NoiseMessage1{local_ephemeral_.public_key});
}

Result<NoiseMessage2, Error> NoiseSession::process_message1(
    const NoiseMessage1& msg,
    std::span<const uint8_t> payload
) {
    if (role_ != NoiseRole::Responder || state_ != NoiseState::Initial) {
        return Result<NoiseMessage2, Error>::err(Error{"Invalid state for processing message 1"});
    }
    
    remote_ephemeral_ = msg.ephemeral;
    mix_hash(std::vector<uint8_t>(remote_ephemeral_.begin(), remote_ephemeral_.end()));
    
    local_ephemeral_ = generate_keypair();
    mix_hash(std::vector<uint8_t>(local_ephemeral_.public_key.begin(), local_ephemeral_.public_key.end()));
    
    auto ee = dh(local_ephemeral_.secret_key, remote_ephemeral_);
    mix_key(ee);
    
    auto encrypt_result = encrypt_symmetric(
        std::span<const uint8_t>(local_static_.public_key.begin(), local_static_.public_key.end()),
        chaining_key_
    );
    if (encrypt_result.is_err()) {
        return Result<NoiseMessage2, Error>::err(encrypt_result.unwrap_err());
    }
    auto encrypted_static = std::move(encrypt_result).unwrap();
    mix_hash(encrypted_static);
    
    auto es = dh(local_static_.secret_key, remote_ephemeral_);
    mix_key(es);
    
    auto payload_result = encrypt_symmetric(payload, chaining_key_);
    if (payload_result.is_err()) {
        return Result<NoiseMessage2, Error>::err(payload_result.unwrap_err());
    }
    auto encrypted_payload = std::move(payload_result).unwrap();
    mix_hash(encrypted_payload);
    
    state_ = NoiseState::WaitingForFinal;
    
    return Result<NoiseMessage2, Error>::ok(NoiseMessage2{
        local_ephemeral_.public_key,
        std::move(encrypted_static),
        std::move(encrypted_payload)
    });
}

Result<NoiseMessage3, Error> NoiseSession::process_message2(
    const NoiseMessage2& msg,
    std::span<const uint8_t> payload
) {
    if (role_ != NoiseRole::Initiator || state_ != NoiseState::WaitingForResponse) {
        return Result<NoiseMessage3, Error>::err(Error{"Invalid state for processing message 2"});
    }
    
    remote_ephemeral_ = msg.ephemeral;
    mix_hash(std::vector<uint8_t>(remote_ephemeral_.begin(), remote_ephemeral_.end()));
    
    auto ee = dh(local_ephemeral_.secret_key, remote_ephemeral_);
    mix_key(ee);
    
    mix_hash(msg.encrypted_static);
    auto static_result = decrypt_symmetric(msg.encrypted_static, chaining_key_);
    if (static_result.is_err()) {
        return Result<NoiseMessage3, Error>::err(static_result.unwrap_err());
    }
    auto remote_static_bytes = std::move(static_result).unwrap();
    if (remote_static_bytes.size() != PUBLIC_KEY_SIZE) {
        return Result<NoiseMessage3, Error>::err(Error{"Invalid static key size"});
    }
    std::copy(remote_static_bytes.begin(), remote_static_bytes.end(), remote_static_.begin());
    
    auto es = dh(local_ephemeral_.secret_key, remote_static_);
    mix_key(es);
    
    mix_hash(msg.encrypted_payload);
    
    auto encrypt_result = encrypt_symmetric(
        std::span<const uint8_t>(local_static_.public_key.begin(), local_static_.public_key.end()),
        chaining_key_
    );
    if (encrypt_result.is_err()) {
        return Result<NoiseMessage3, Error>::err(encrypt_result.unwrap_err());
    }
    auto encrypted_static = std::move(encrypt_result).unwrap();
    mix_hash(encrypted_static);
    
    auto se = dh(local_static_.secret_key, remote_ephemeral_);
    mix_key(se);
    
    auto payload_result = encrypt_symmetric(payload, chaining_key_);
    if (payload_result.is_err()) {
        return Result<NoiseMessage3, Error>::err(payload_result.unwrap_err());
    }
    auto encrypted_payload = std::move(payload_result).unwrap();
    mix_hash(encrypted_payload);
    
    split_keys();
    
    return Result<NoiseMessage3, Error>::ok(NoiseMessage3{
        std::move(encrypted_static),
        std::move(encrypted_payload)
    });
}

Result<std::vector<uint8_t>, Error> NoiseSession::process_message3(const NoiseMessage3& msg) {
    if (role_ != NoiseRole::Responder || state_ != NoiseState::WaitingForFinal) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Invalid state for processing message 3"});
    }
    
    mix_hash(msg.encrypted_static);
    auto static_result = decrypt_symmetric(msg.encrypted_static, chaining_key_);
    if (static_result.is_err()) {
        return Result<std::vector<uint8_t>, Error>::err(static_result.unwrap_err());
    }
    auto remote_static_bytes = std::move(static_result).unwrap();
    if (remote_static_bytes.size() != PUBLIC_KEY_SIZE) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Invalid static key size"});
    }
    std::copy(remote_static_bytes.begin(), remote_static_bytes.end(), remote_static_.begin());
    
    auto se = dh(local_ephemeral_.secret_key, remote_static_);
    mix_key(se);
    
    mix_hash(msg.encrypted_payload);
    auto payload_result = decrypt_symmetric(msg.encrypted_payload, chaining_key_);
    if (payload_result.is_err()) {
        return Result<std::vector<uint8_t>, Error>::err(payload_result.unwrap_err());
    }
    
    split_keys();
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(payload_result).unwrap());
}

Result<std::vector<uint8_t>, Error> NoiseSession::encrypt(std::span<const uint8_t> plaintext) {
    if (state_ != NoiseState::Transport) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Transport not ready"});
    }
    
    std::vector<uint8_t> nonce(SECRETBOX_NONCE_SIZE, 0);
    std::memcpy(nonce.data(), &send_nonce_, sizeof(send_nonce_));
    ++send_nonce_;
    
#ifdef ZINC_HAS_SODIUM
    std::vector<uint8_t> ciphertext(nonce.size() + plaintext.size() + SECRETBOX_MAC_SIZE);
    std::copy(nonce.begin(), nonce.end(), ciphertext.begin());
    
    int result = crypto_secretbox_easy(
        ciphertext.data() + nonce.size(),
        plaintext.data(), plaintext.size(),
        nonce.data(),
        send_key_.data()
    );
    
    if (result != 0) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Encryption failed"});
    }
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(ciphertext));
#else
    // Use the symmetric encryption wrapper
    return encrypt_symmetric(plaintext, send_key_);
#endif
}

Result<std::vector<uint8_t>, Error> NoiseSession::decrypt(std::span<const uint8_t> ciphertext) {
    if (state_ != NoiseState::Transport) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Transport not ready"});
    }
    
#ifdef ZINC_HAS_SODIUM
    if (ciphertext.size() < SECRETBOX_NONCE_SIZE + SECRETBOX_MAC_SIZE) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Ciphertext too short"});
    }
    
    const uint8_t* nonce = ciphertext.data();
    const uint8_t* encrypted = ciphertext.data() + SECRETBOX_NONCE_SIZE;
    size_t encrypted_len = ciphertext.size() - SECRETBOX_NONCE_SIZE;
    
    std::vector<uint8_t> plaintext(encrypted_len - SECRETBOX_MAC_SIZE);
    
    int result = crypto_secretbox_open_easy(
        plaintext.data(),
        encrypted, encrypted_len,
        nonce,
        recv_key_.data()
    );
    
    if (result != 0) {
        return Result<std::vector<uint8_t>, Error>::err(Error{"Decryption failed"});
    }
    
    ++recv_nonce_;
    
    return Result<std::vector<uint8_t>, Error>::ok(std::move(plaintext));
#else
    ++recv_nonce_;
    return decrypt_symmetric(ciphertext, recv_key_);
#endif
}

// Serialization helpers
std::vector<uint8_t> serialize_message1(const NoiseMessage1& msg) {
    return std::vector<uint8_t>(msg.ephemeral.begin(), msg.ephemeral.end());
}

std::vector<uint8_t> serialize_message2(const NoiseMessage2& msg) {
    std::vector<uint8_t> data;
    data.insert(data.end(), msg.ephemeral.begin(), msg.ephemeral.end());
    
    uint32_t static_len = static_cast<uint32_t>(msg.encrypted_static.size());
    data.push_back(static_len & 0xFF);
    data.push_back((static_len >> 8) & 0xFF);
    data.push_back((static_len >> 16) & 0xFF);
    data.push_back((static_len >> 24) & 0xFF);
    data.insert(data.end(), msg.encrypted_static.begin(), msg.encrypted_static.end());
    
    data.insert(data.end(), msg.encrypted_payload.begin(), msg.encrypted_payload.end());
    
    return data;
}

std::vector<uint8_t> serialize_message3(const NoiseMessage3& msg) {
    std::vector<uint8_t> data;
    
    uint32_t static_len = static_cast<uint32_t>(msg.encrypted_static.size());
    data.push_back(static_len & 0xFF);
    data.push_back((static_len >> 8) & 0xFF);
    data.push_back((static_len >> 16) & 0xFF);
    data.push_back((static_len >> 24) & 0xFF);
    data.insert(data.end(), msg.encrypted_static.begin(), msg.encrypted_static.end());
    
    data.insert(data.end(), msg.encrypted_payload.begin(), msg.encrypted_payload.end());
    
    return data;
}

Result<NoiseMessage1, Error> deserialize_message1(std::span<const uint8_t> data) {
    if (data.size() != PUBLIC_KEY_SIZE) {
        return Result<NoiseMessage1, Error>::err(Error{"Invalid message 1 size"});
    }
    
    NoiseMessage1 msg;
    std::copy(data.begin(), data.end(), msg.ephemeral.begin());
    return Result<NoiseMessage1, Error>::ok(msg);
}

Result<NoiseMessage2, Error> deserialize_message2(std::span<const uint8_t> data) {
    if (data.size() < PUBLIC_KEY_SIZE + 4) {
        return Result<NoiseMessage2, Error>::err(Error{"Invalid message 2 size"});
    }
    
    NoiseMessage2 msg;
    std::copy(data.begin(), data.begin() + PUBLIC_KEY_SIZE, msg.ephemeral.begin());
    
    size_t offset = PUBLIC_KEY_SIZE;
    uint32_t static_len = data[offset] | (data[offset + 1] << 8) | 
                          (data[offset + 2] << 16) | (data[offset + 3] << 24);
    offset += 4;
    
    if (data.size() < offset + static_len) {
        return Result<NoiseMessage2, Error>::err(Error{"Invalid message 2 static size"});
    }
    
    msg.encrypted_static = std::vector<uint8_t>(
        data.begin() + offset, 
        data.begin() + offset + static_len
    );
    offset += static_len;
    
    msg.encrypted_payload = std::vector<uint8_t>(data.begin() + offset, data.end());
    
    return Result<NoiseMessage2, Error>::ok(msg);
}

Result<NoiseMessage3, Error> deserialize_message3(std::span<const uint8_t> data) {
    if (data.size() < 4) {
        return Result<NoiseMessage3, Error>::err(Error{"Invalid message 3 size"});
    }
    
    NoiseMessage3 msg;
    
    uint32_t static_len = data[0] | (data[1] << 8) | (data[2] << 16) | (data[3] << 24);
    size_t offset = 4;
    
    if (data.size() < offset + static_len) {
        return Result<NoiseMessage3, Error>::err(Error{"Invalid message 3 static size"});
    }
    
    msg.encrypted_static = std::vector<uint8_t>(
        data.begin() + offset, 
        data.begin() + offset + static_len
    );
    offset += static_len;
    
    msg.encrypted_payload = std::vector<uint8_t>(data.begin() + offset, data.end());
    
    return Result<NoiseMessage3, Error>::ok(msg);
}

} // namespace zinc::crypto
