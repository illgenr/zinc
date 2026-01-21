#include "network/transport.hpp"
#include <QDebug>
#include <limits>

namespace zinc::network {

namespace {
bool sync_debug_enabled() {
    return qEnvironmentVariableIsSet("ZINC_DEBUG_SYNC");
}

QString state_name(Connection::State state) {
    switch (state) {
        case Connection::State::Disconnected: return QStringLiteral("Disconnected");
        case Connection::State::Connecting: return QStringLiteral("Connecting");
        case Connection::State::Handshaking: return QStringLiteral("Handshaking");
        case Connection::State::Connected: return QStringLiteral("Connected");
        case Connection::State::Failed: return QStringLiteral("Failed");
    }
    return QStringLiteral("Unknown");
}

QString type_name(MessageType type) {
    switch (type) {
        case MessageType::NoiseMessage1: return QStringLiteral("NoiseMessage1");
        case MessageType::NoiseMessage2: return QStringLiteral("NoiseMessage2");
        case MessageType::NoiseMessage3: return QStringLiteral("NoiseMessage3");
        case MessageType::Hello: return QStringLiteral("Hello");
        case MessageType::PairingRequest: return QStringLiteral("PairingRequest");
        case MessageType::PairingResponse: return QStringLiteral("PairingResponse");
        case MessageType::PairingComplete: return QStringLiteral("PairingComplete");
        case MessageType::PairingReject: return QStringLiteral("PairingReject");
        case MessageType::SyncRequest: return QStringLiteral("SyncRequest");
        case MessageType::SyncResponse: return QStringLiteral("SyncResponse");
        case MessageType::ChangeNotify: return QStringLiteral("ChangeNotify");
        case MessageType::ChangeAck: return QStringLiteral("ChangeAck");
        case MessageType::Ping: return QStringLiteral("Ping");
        case MessageType::Pong: return QStringLiteral("Pong");
        case MessageType::Disconnect: return QStringLiteral("Disconnect");
        case MessageType::PagesSnapshot: return QStringLiteral("PagesSnapshot");
    }
    return QStringLiteral("Unknown");
}
} // namespace

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

QHostAddress Connection::peerAddress() const {
    return socket_ ? socket_->peerAddress() : QHostAddress{};
}

uint16_t Connection::peerPort() const {
    return socket_ ? static_cast<uint16_t>(socket_->peerPort()) : 0;
}

void Connection::connectToPeer(const QHostAddress& host, uint16_t port,
                               const crypto::KeyPair& local_keys) {
    local_keys_ = local_keys;
    noise_role_ = crypto::NoiseRole::Initiator;
    noise_ = std::make_unique<crypto::NoiseSession>(
        crypto::NoiseRole::Initiator, local_keys_);
    connect_host_ = host;
    connect_port_ = port;
    
    setState(State::Connecting);
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: socket connectToHost host=" << host.toString() << "port=" << port;
    }
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

    connect_host_ = socket_ ? socket_->peerAddress() : QHostAddress{};
    connect_port_ = socket_ ? static_cast<uint16_t>(socket_->peerPort()) : 0;
    
    setState(State::Handshaking);
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: socket accepted from"
                << (socket_ ? socket_->peerAddress().toString() : QStringLiteral("<null>"))
                << (socket_ ? socket_->peerPort() : 0);
    }
    // Wait for initiator's message 1
}

void Connection::disconnect() {
    if (state_ != State::Disconnected) {
        if (sync_debug_enabled()) {
            qInfo() << "SYNC: socket disconnect state=" << state_name(state_);
        }
        // Try to send disconnect message
        if (state_ == State::Connected) {
            send(MessageType::Disconnect, {});
        }
        
        socket_->disconnectFromHost();
        connect_host_ = QHostAddress{};
        connect_port_ = 0;
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
        if (sync_debug_enabled()) {
            qInfo() << "SYNC: socket state" << state_name(state_) << "->" << state_name(state);
        }
        state_ = state;
        emit stateChanged(state);
    }
}

void Connection::onSocketConnected() {
    setState(State::Handshaking);
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: socket connected, starting handshake";
    }
    
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
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: socket disconnected state=" << state_name(state_);
    }
    connect_host_ = QHostAddress{};
    connect_port_ = 0;
    setState(State::Disconnected);
    emit disconnected();
}

void Connection::onSocketError(QAbstractSocket::SocketError err) {
    if (sync_debug_enabled()) {
        qInfo() << "SYNC: socket error" << static_cast<int>(err) << socket_->errorString()
                << "state=" << state_name(state_);
    }
    const auto host = connect_host_.isNull() ? socket_->peerAddress() : connect_host_;
    const auto port = connect_port_ != 0 ? connect_port_ : static_cast<uint16_t>(socket_->peerPort());
    const auto where = (host.isNull() || port == 0)
        ? QStringLiteral("")
        : QStringLiteral(" (%1:%2)").arg(host.toString()).arg(port);
    emit error(socket_->errorString() + where);
    if (state_ == State::Connecting || state_ == State::Handshaking) {
        setState(State::Failed);
    }
}

void Connection::onReadyRead() {
    read_buffer_.append(socket_->readAll());

    // Defensive: reject unreasonably large messages to avoid allocation spikes or integer overflows.
    static constexpr size_t kMaxMessagePayloadBytes = 10 * 1024 * 1024; // 10 MiB
    
    while (read_buffer_.size() >= static_cast<int>(MessageHeader::HEADER_SIZE)) {
        // Try to parse header
        std::vector<uint8_t> header_data(
            read_buffer_.begin(), 
            read_buffer_.begin() + MessageHeader::HEADER_SIZE
        );
        
        auto header_result = deserializeHeader(header_data);
        if (header_result.is_err()) {
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: invalid header, disconnecting:" << QString::fromStdString(header_result.unwrap_err().message);
            }
            emit error("Invalid message header");
            disconnect();
            return;
        }
        
        auto header = header_result.unwrap();
        const size_t payload_size = static_cast<size_t>(header.length);
        if (payload_size > kMaxMessagePayloadBytes) {
            emit error("Message too large");
            disconnect();
            return;
        }
        if (payload_size > (std::numeric_limits<size_t>::max() - MessageHeader::HEADER_SIZE)) {
            emit error("Invalid message length");
            disconnect();
            return;
        }
        const size_t total_size = MessageHeader::HEADER_SIZE + payload_size;
        
        const size_t available = static_cast<size_t>(read_buffer_.size());
        if (available < total_size) {
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
                if (sync_debug_enabled()) {
                    qInfo() << "SYNC: handshake rx" << type_name(header.type) << "bytes=" << payload.size();
                }
                processHandshake(header.type, payload);
            } else if (sync_debug_enabled()) {
                qInfo() << "SYNC: ignoring non-handshake msg during handshaking:" << type_name(header.type);
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
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: handshake complete (initiator)";
            }
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
            if (sync_debug_enabled()) {
                qInfo() << "SYNC: handshake complete (responder)";
            }
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
