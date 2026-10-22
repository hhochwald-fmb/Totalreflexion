import Darwin
import Foundation
import Network

/// Address of the remote iPad, usable with BSD sockets (IPv4 is mapped into IPv6).
struct RemoteAddress {
    var storage = sockaddr_in6()

    init?(endpoint: NWEndpoint) {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        storage.sin6_family = sa_family_t(AF_INET6)
        storage.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        switch host {
        case let .ipv4(address):
            setMapped(address)
        case let .ipv6(address):
            if let mapped = address.asIPv4 {
                setMapped(mapped)
            } else {
                withUnsafeMutableBytes(of: &storage.sin6_addr) { $0.copyBytes(from: address.rawValue) }
                if let interface = address.interface {
                    storage.sin6_scope_id = if_nametoindex(interface.name)
                }
            }
        default:
            return nil
        }
    }

    private mutating func setMapped(_ address: IPv4Address) {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[10] = 0xFF
        bytes[11] = 0xFF
        bytes.replaceSubrange(12..<16, with: address.rawValue)
        withUnsafeMutableBytes(of: &storage.sin6_addr) { $0.copyBytes(from: bytes) }
    }

    func with(port: UInt16) -> RemoteAddress {
        var copy = self
        copy.storage.sin6_port = port.bigEndian
        return copy
    }
}

/// Dual-stack UDP socket bound to an ephemeral port.
final class UDPSocket {
    let port: UInt16
    private let descriptor: Int32
    private let source: DispatchSourceRead

    init?(queue: DispatchQueue, onPacket: @escaping (Data) -> Void) {
        let socketFD = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0, let boundPort = bindDualStack(socketFD) else {
            if socketFD >= 0 { Darwin.close(socketFD) }
            return nil
        }
        descriptor = socketFD
        port = boundPort
        source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65536)
            let count = recv(socketFD, &buffer, buffer.count, 0)
            if count > 0 {
                onPacket(Data(buffer[0..<count]))
            }
        }
        source.setCancelHandler { Darwin.close(socketFD) }
        source.resume()
    }

    func send(_ data: Data, to address: RemoteAddress) {
        var target = address.storage
        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(descriptor, bytes.baseAddress, data.count, 0, sockaddrPointer,
                           socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }

    func close() {
        source.cancel()
    }
}

/// Dual-stack TCP listener on an ephemeral port that hands each accepted connection's bytes to a handler.
final class TCPStreamListener {
    let port: UInt16
    private let listenSource: DispatchSourceRead
    private var clientSource: DispatchSourceRead?
    private let queue: DispatchQueue

    init?(queue: DispatchQueue, onData: @escaping (Data) -> Void, onClose: @escaping () -> Void) {
        let socketFD = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0, let boundPort = bindDualStack(socketFD), listen(socketFD, 4) == 0 else {
            if socketFD >= 0 { Darwin.close(socketFD) }
            return nil
        }
        self.queue = queue
        port = boundPort
        listenSource = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        listenSource.setCancelHandler { Darwin.close(socketFD) }
        listenSource.setEventHandler { [weak self] in
            let clientFD = accept(socketFD, nil, nil)
            guard clientFD >= 0 else { return }
            self?.attach(clientFD: clientFD, onData: onData, onClose: onClose)
        }
        listenSource.resume()
    }

    private func attach(clientFD: Int32, onData: @escaping (Data) -> Void, onClose: @escaping () -> Void) {
        clientSource?.cancel()
        var enabled: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        var bufferSize: Int32 = 4 * 1024 * 1024
        setsockopt(clientFD, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))

        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        source.setEventHandler { [weak source] in
            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            let count = recv(clientFD, &buffer, buffer.count, 0)
            if count > 0 {
                onData(Data(buffer[0..<count]))
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                source?.cancel()
                onClose()
            }
        }
        source.setCancelHandler { Darwin.close(clientFD) }
        source.resume()
        clientSource = source
    }

    func close() {
        clientSource?.cancel()
        clientSource = nil
        listenSource.cancel()
    }
}

private func bindDualStack(_ socketFD: Int32) -> UInt16? {
    var off: Int32 = 0
    setsockopt(socketFD, IPPROTO_IPV6, IPV6_V6ONLY, &off, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in6()
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_addr = in6addr_any
    address.sin6_port = 0
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
    }
    guard bound == 0 else { return nil }
    var length = socklen_t(MemoryLayout<sockaddr_in6>.size)
    let named = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) }
    }
    guard named == 0 else { return nil }
    return UInt16(bigEndian: address.sin6_port)
}
