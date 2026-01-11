#include "network/transport.hpp"
#include <QDebug>

namespace zinc::network {

// ============================================================================
// Connection
// ============================================================================

Connection::Connection(QObject* parent)
    : QObject(parent)
    , socket_(std::make_unique<QTcpSocket>(this))
{
    connect(socket_.get(), &QTcpSocket::connected, 
            this, &Connection::onSocketConnected);
    connect(socket_.get(), &QTcpSocket::disconnected, 
            this, &Connection::onSocketDisconnected);
    connect(socket_.get(), &QTcpSocket::errorOccurred,
            this, &Connection::onSocketError);
    connect(socket_.get(), &QTcpSocket::readyRead, 
            this, &Connection::onReadyRead);
}

Connection::~Connection() {
    disconnect();
}

void Connection::connectToPeer(const QHostAddress& host, uint16_t port,
                               const crypto::KeyPair& local_keys) {
    local_keys_ = local_keys;
    noise_role_ = crypto::NoiseRole::Initiator;
    noise_ = std::make_unique<crypto::NoiseSession>(
        crypto::NoiseRole::Initiator, local_keys_);
    
    setState(State::Connecting);
    socket_->connectToHost(host, port);
}

void Connection::acceptConnection(QTcpSocket* socket,
                                  const crypto::KeyPair& local_keys) {
    local_keys_ = local_keys;
    noise_role_ = crypto::NoiseRole::Responder;
    noise_ = std::make_unique<crypto::NoiseSession>(
        crypto::NoiseRole::Responder, local_keys_);
    
    // Take ownership of socket
    socket->setParent(this);
    socket_.reset(socket);
    
    connect(socket_.get(), &QTcpSocket::disconnected, 
            this, &Connection::onSocketDisconnected);
    connect(socket_.get(), &QTcpSocket::errorOccurred,
            this, &Connection::onSocketError);
    connect(socket_.get(), &QTcpSocket::readyRead, 
            this, &Connection::onReadyRead);
    
    setState(State::Handshaking);
    // Wait for initiator's message 1
}

void Connection::disconnect() {
    if (state_ != State::Disconnected) {
        // Try to send disconnect message
        if (state_ == State::Connected) {
            send(MessageType::Disconnect, {});
        }
        
        socket_->disconnectFromHost();
        setState(State::Disconnected);
    }
}

Result<void, Error> Connection::send(MessageType type, 
                                     const std::vector<uint8_t>& payload) {
    if (state_ == State::Connected && noise_ && noise_->is_transport_ready()) {
        // Encrypt the payload
        auto encrypted = noise_->encrypt(payload);
        if (encrypted.is_err()) {
            return Result<void, Error>::err(encrypted.unwrap_err());
        }
        return sendRaw(type, encrypted.unwrap());
    } else if (state_ == State::Handshaking) {
        // During handshake, send unencrypted
        return sendRaw(type, payload);
    }
    
    return Result<void, Error>::err(Error{"Not connected"});
}

const crypto::PublicKey& Connection::remotePeerKey() const {
    static crypto::PublicKey empty{};
    if (noise_) {
        return noise_->remote_static_key();
    }
    return empty;
}

void Connection::setState(State state) {
    if (state_ != state) {
        state_ = state;
        emit stateChanged(state);
    }
}

void Connection::onSocketConnected() {
    setState(State::Handshaking);
    
    // Initiator sends message 1
    auto msg1_result = noise_->create_message1();
    if (msg1_result.is_err()) {
        emit error(QString::fromStdString(msg1_result.unwrap_err().message));
        setState(State::Failed);
        return;
    }
    
    auto msg1_bytes = crypto::serialize_message1(msg1_result.unwrap());
    sendRaw(MessageType::NoiseMessage1, msg1_bytes);
}

void Connection::onSocketDisconnected() {
    setState(State::Disconnected);
    emit disconnected();
}

void Connection::onSocketError(QAbstractSocket::SocketError err) {
    emit error(socket_->errorString());
    if (state_ == State::Connecting || state_ == State::Handshaking) {
        setState(State::Failed);
    }
}

void Connection::onReadyRead() {
    read_buffer_.append(socket_->readAll());
    
    while (read_buffer_.size() >= static_cast<int>(MessageHeader::HEADER_SIZE)) {
        // Try to parse header
        std::vector<uint8_t> header_data(
            read_buffer_.begin(), 
            read_buffer_.begin() + MessageHeader::HEADER_SIZE
        );
        
        auto header_result = deserializeHeader(header_data);
        if (header_result.is_err()) {
            emit error("Invalid message header");
            disconnect();
            return;
        }
        
        auto header = header_result.unwrap();
        size_t total_size = MessageHeader::HEADER_SIZE + header.length;
        
        if (read_buffer_.size() < static_cast<int>(total_size)) {
            // Need more data
            return;
        }
        
        // Extract payload
        std::vector<uint8_t> payload(
            read_buffer_.begin() + MessageHeader::HEADER_SIZE,
            read_buffer_.begin() + total_size
        );
        
        read_buffer_.remove(0, static_cast<int>(total_size));
        
        // Process based on state
        if (state_ == State::Handshaking) {
            // Handle handshake messages
            if (header.type == MessageType::NoiseMessage1 ||
                header.type == MessageType::NoiseMessage2 ||
                header.type == MessageType::NoiseMessage3) {
                processHandshake(header.type, payload);
            }
        } else if (state_ == State::Connected) {
            // Decrypt and emit
            if (noise_ && noise_->is_transport_ready()) {
                auto decrypted = noise_->decrypt(payload);
                if (decrypted.is_err()) {
                    emit error("Decryption failed");
                    continue;
                }
                emit messageReceived(header.type, decrypted.unwrap());
            }
        }
    }
}

void Connection::processHandshake(MessageType type, const std::vector<uint8_t>& payload) {
    if (!noise_) {
        emit error("Noise session not initialized");
        setState(State::Failed);
        socket_->disconnectFromHost();
        return;
    }

    if (type == MessageType::NoiseMessage1 && noise_role_ == crypto::NoiseRole::Responder) {
        auto msg1 = crypto::deserialize_message1(payload);
        if (msg1.is_err()) {
            emit error(QString::fromStdString(msg1.unwrap_err().message));
            setState(State::Failed);
            socket_->disconnectFromHost();
            return;
        }

        auto msg2 = noise_->process_message1(msg1.unwrap(), {});
        if (msg2.is_err()) {
            emit error(QString::fromStdString(msg2.unwrap_err().message));
            setState(State::Failed);
            socket_->disconnectFromHost();
            return;
        }

        auto msg2_bytes = crypto::serialize_message2(msg2.unwrap());
        sendRaw(MessageType::NoiseMessage2, msg2_bytes);
        return;
    }

    if (type == MessageType::NoiseMessage2 && noise_role_ == crypto::NoiseRole::Initiator) {
        auto msg2 = crypto::deserialize_message2(payload);
        if (msg2.is_err()) {
            emit error(QString::fromStdString(msg2.unwrap_err().message));
            setState(State::Failed);
            socket_->disconnectFromHost();
            return;
        }

        auto msg3 = noise_->process_message2(msg2.unwrap(), {});
        if (msg3.is_err()) {
            emit error(QString::fromStdString(msg3.unwrap_err().message));
            setState(State::Failed);
            socket_->disconnectFromHost();
            return;
        }

        auto msg3_bytes = crypto::serialize_message3(msg3.unwrap());
        sendRaw(MessageType::NoiseMessage3, msg3_bytes);

        if (noise_->is_transport_ready()) {
            setState(State::Connected);
            emit connected();
        }
        return;
    }

    if (type == MessageType::NoiseMessage3 && noise_role_ == crypto::NoiseRole::Responder) {
        auto msg3 = crypto::deserialize_message3(payload);
        if (msg3.is_err()) {
            emit error(QString::fromStdString(msg3.unwrap_err().message));
            setState(State::Failed);
            socket_->disconnectFromHost();
            return;
        }

        auto final_payload = noise_->process_message3(msg3.unwrap());
        if (final_payload.is_err()) {
            emit error(QString::fromStdString(final_payload.unwrap_err().message));
            setState(State::Failed);
            socket_->disconnectFromHost();
            return;
        }

        if (noise_->is_transport_ready()) {
            setState(State::Connected);
            emit connected();
        }
        return;
    }
}

Result<void, Error> Connection::sendRaw(MessageType type, 
                                         const std::vector<uint8_t>& data) {
    MessageHeader header;
    header.type = type;
    header.length = static_cast<uint32_t>(data.size());
    
    auto header_bytes = serializeHeader(header);
    
    socket_->write(reinterpret_cast<const char*>(header_bytes.data()), 
                   header_bytes.size());
    socket_->write(reinterpret_cast<const char*>(data.data()), data.size());
    socket_->flush();
    
    return Result<void, Error>::ok();
}

// ============================================================================
// TransportServer
// ============================================================================

TransportServer::TransportServer(QObject* parent)
    : QObject(parent)
    , server_(std::make_unique<QTcpServer>(this))
{
    connect(server_.get(), &QTcpServer::newConnection,
            this, &TransportServer::onNewConnection);
}

TransportServer::~TransportServer() {
    close();
}

Result<uint16_t, Error> TransportServer::listen(uint16_t port) {
    if (!server_->listen(QHostAddress::Any, port)) {
        return Result<uint16_t, Error>::err(
            Error{server_->errorString().toStdString()});
    }
    
    return Result<uint16_t, Error>::ok(server_->serverPort());
}

void TransportServer::close() {
    server_->close();
}

uint16_t TransportServer::port() const {
    return server_->serverPort();
}

bool TransportServer::isListening() const {
    return server_->isListening();
}

void TransportServer::onNewConnection() {
    while (server_->hasPendingConnections()) {
        QTcpSocket* socket = server_->nextPendingConnection();
        emit newConnection(socket);
    }
}

// ============================================================================
// Serialization
// ============================================================================

std::vector<uint8_t> serializeHeader(const MessageHeader& header) {
    std::vector<uint8_t> data(MessageHeader::HEADER_SIZE);
    
    data[0] = MessageHeader::MAGIC[0];
    data[1] = MessageHeader::MAGIC[1];
    data[2] = MessageHeader::VERSION;
    data[3] = static_cast<uint8_t>(header.type);
    data[4] = (header.length >> 24) & 0xFF;
    data[5] = (header.length >> 16) & 0xFF;
    data[6] = (header.length >> 8) & 0xFF;
    data[7] = header.length & 0xFF;
    
    return data;
}

Result<MessageHeader, Error> deserializeHeader(const std::vector<uint8_t>& data) {
    if (data.size() < MessageHeader::HEADER_SIZE) {
        return Result<MessageHeader, Error>::err(Error{"Header too short"});
    }
    
    if (data[0] != MessageHeader::MAGIC[0] || data[1] != MessageHeader::MAGIC[1]) {
        return Result<MessageHeader, Error>::err(Error{"Invalid magic"});
    }
    
    if (data[2] != MessageHeader::VERSION) {
        return Result<MessageHeader, Error>::err(Error{"Unsupported version"});
    }
    
    MessageHeader header;
    header.type = static_cast<MessageType>(data[3]);
    header.length = (static_cast<uint32_t>(data[4]) << 24) |
                    (static_cast<uint32_t>(data[5]) << 16) |
                    (static_cast<uint32_t>(data[6]) << 8) |
                    static_cast<uint32_t>(data[7]);
    
    return Result<MessageHeader, Error>::ok(header);
}

} // namespace zinc::network
