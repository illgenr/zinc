#pragma once

#include "core/types.hpp"
#include "core/result.hpp"
#include "crypto/noise_session.hpp"
#include <QObject>
#include <QTcpSocket>
#include <QTcpServer>
#include <memory>
#include <functional>

namespace zinc::network {

/**
 * Message types for the sync protocol.
 */
enum class MessageType : uint8_t {
    // Handshake
    NoiseMessage1 = 0x01,
    NoiseMessage2 = 0x02,
    NoiseMessage3 = 0x03,
    
    // Pairing
    PairingRequest = 0x10,
    PairingResponse = 0x11,
    PairingComplete = 0x12,
    PairingReject = 0x13,
    
    // Sync
    SyncRequest = 0x20,
    SyncResponse = 0x21,
    ChangeNotify = 0x22,
    ChangeAck = 0x23,
    
    // Control
    Ping = 0x30,
    Pong = 0x31,
    Disconnect = 0x3F,

    // Pages sync
    PagesSnapshot = 0x40
};

/**
 * Protocol message header.
 * 
 * Format:
 * - Magic (2 bytes): 0x5A 0x4E ("ZN")
 * - Version (1 byte)
 * - Type (1 byte)
 * - Length (4 bytes, big-endian)
 * - Payload (variable)
 */
struct MessageHeader {
    static constexpr uint8_t MAGIC[2] = {0x5A, 0x4E};  // "ZN"
    static constexpr uint8_t VERSION = 1;
    static constexpr size_t HEADER_SIZE = 8;
    
    MessageType type;
    uint32_t length;
};

/**
 * Connection - A secure connection to a peer.
 */
class Connection : public QObject {
    Q_OBJECT
    
public:
    enum class State {
        Disconnected,
        Connecting,
        Handshaking,
        Connected,
        Failed
    };
    
    explicit Connection(QObject* parent = nullptr);
    ~Connection() override;
    
    /**
     * Connect to a peer (as initiator).
     */
    void connectToPeer(const QHostAddress& host, uint16_t port,
                       const crypto::KeyPair& local_keys);
    
    /**
     * Accept a connection (as responder).
     */
    void acceptConnection(QTcpSocket* socket,
                         const crypto::KeyPair& local_keys);
    
    /**
     * Disconnect from the peer.
     */
    void disconnect();
    
    /**
     * Send a message to the peer (will be encrypted after handshake).
     */
    Result<void, Error> send(MessageType type, const std::vector<uint8_t>& payload);
    
    /**
     * Get the current state.
     */
    [[nodiscard]] State state() const { return state_; }
    
    /**
     * Get the remote peer's public key (after handshake).
     */
    [[nodiscard]] const crypto::PublicKey& remotePeerKey() const;
    
    /**
     * Check if the connection is established and encrypted.
     */
    [[nodiscard]] bool isConnected() const { return state_ == State::Connected; }

signals:
    void connected();
    void disconnected();
    void messageReceived(MessageType type, const std::vector<uint8_t>& payload);
    void error(const QString& message);
    void stateChanged(State state);

private slots:
    void onSocketConnected();
    void onSocketDisconnected();
    void onSocketError(QAbstractSocket::SocketError error);
    void onReadyRead();

private:
    State state_ = State::Disconnected;
    std::unique_ptr<QTcpSocket> socket_;
    std::unique_ptr<crypto::NoiseSession> noise_;
    crypto::NoiseRole noise_role_ = crypto::NoiseRole::Initiator;
    crypto::KeyPair local_keys_;
    QByteArray read_buffer_;
    
    void setState(State state);
    void processHandshake(MessageType type, const std::vector<uint8_t>& payload);
    void processMessage();
    Result<void, Error> sendRaw(MessageType type, const std::vector<uint8_t>& data);
};

/**
 * TransportServer - Listens for incoming connections.
 */
class TransportServer : public QObject {
    Q_OBJECT
    
public:
    explicit TransportServer(QObject* parent = nullptr);
    ~TransportServer() override;
    
    /**
     * Start listening on a port.
     * @param port Port to listen on (0 for auto-assign)
     * @return The actual port being listened on
     */
    Result<uint16_t, Error> listen(uint16_t port = 0);
    
    /**
     * Stop listening.
     */
    void close();
    
    /**
     * Get the port we're listening on.
     */
    [[nodiscard]] uint16_t port() const;
    
    /**
     * Check if we're listening.
     */
    [[nodiscard]] bool isListening() const;

signals:
    void newConnection(QTcpSocket* socket);
    void error(const QString& message);

private slots:
    void onNewConnection();

private:
    std::unique_ptr<QTcpServer> server_;
};

/**
 * Serialize a message header.
 */
std::vector<uint8_t> serializeHeader(const MessageHeader& header);

/**
 * Deserialize a message header.
 */
Result<MessageHeader, Error> deserializeHeader(const std::vector<uint8_t>& data);

} // namespace zinc::network
