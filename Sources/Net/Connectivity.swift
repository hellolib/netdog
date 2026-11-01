import Darwin
import Foundation

struct Connectivity {
    var status = false
    var latency: Double = 0
    var jitter: Double = 0
}

enum ConnectivityMode: String {
    case auto
    case icmp
    case http
}

/// ICMP echo probe with an HTTP HEAD fallback, ported from Stats'
/// ConnectivityReader but socket-driven instead of CFSocket/runloop based.
final class ConnectivityReader: Reader<Connectivity> {
    private enum Mode {
        case icmp
        case http
    }

    private enum ProbeResult {
        case success(Double)
        case timeout
        case unsupported
        case failure
    }

    private let icmpTimeout: TimeInterval = 1.5
    private let httpTimeout: TimeInterval = 4
    private let fallbackAfter = 3

    private var icmpHost: String
    private var httpURL: URL
    private var configuredMode: ConnectivityMode
    private var mode: Mode = .icmp
    private var consecutiveFailures = 0
    private var previousLatency: Double?
    private var jitter: Double = 0
    private var sequence: UInt16 = 0
    private let identifier: UInt16 = UInt16.random(in: 0..<UInt16.max)
    private let payload: [UInt8] = (0..<8).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }

    init(
        interval: TimeInterval = 1,
        icmpHost: String? = nil,
        httpURL: URL? = nil,
        mode: ConnectivityMode? = nil,
        handler: @escaping (Connectivity) -> Void
    ) {
        self.icmpHost = icmpHost ?? Settings.icmpHost
        self.httpURL = httpURL ?? Settings.httpURL
        self.configuredMode = mode ?? Settings.connectivityMode
        super.init(label: "netdog.connectivity", interval: interval, handler: handler)
        if self.configuredMode == .http {
            self.mode = .http
        }
    }

    func reconfigure(icmpHost: String, httpURL: URL, mode: ConnectivityMode) {
        self.onQueue { [weak self] in
            guard let self else { return }
            self.icmpHost = icmpHost
            self.httpURL = httpURL
            self.configuredMode = mode
            self.mode = mode == .http ? .http : .icmp
            self.consecutiveFailures = 0
        }
    }

    override func read() {
        switch self.mode {
        case .http:
            self.checkHTTP()
        case .icmp:
            switch self.probeICMP() {
            case .success(let latency):
                self.consecutiveFailures = 0
                self.record(latency)
            case .timeout, .failure:
                self.consecutiveFailures += 1
                self.emit(Connectivity(status: false))
                if self.configuredMode == .auto, self.consecutiveFailures >= self.fallbackAfter {
                    self.mode = .http
                    self.checkHTTP()
                }
            case .unsupported:
                self.mode = .http
                self.checkHTTP()
            }
        }
    }

    // MARK: - ICMP

    private func probeICMP() -> ProbeResult {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return .unsupported }
        defer { close(fd) }

        guard var address = self.resolve(self.icmpHost) else { return .failure }

        self.sequence &+= 1
        let packet = self.makePacket()
        let start = DispatchTime.now()

        let sent = withUnsafePointer(to: &address) { pointer -> Int in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                sendto(fd, packet, packet.count, 0, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return .unsupported }

        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        var ready: Int32 = 0
        repeat {
            ready = poll(&descriptor, 1, Int32(self.icmpTimeout * 1000))
        } while ready < 0 && errno == EINTR
        guard ready > 0 else { return .timeout }

        var buffer = [UInt8](repeating: 0, count: 1500)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else { return .failure }

        let latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        guard self.validate(Array(buffer[0..<received])) else { return .failure }
        return .success(latency)
    }

    private func makePacket() -> [UInt8] {
        // type, code, checksum, identifier, sequence, payload
        var packet: [UInt8] = [8, 0, 0, 0]
        packet.append(UInt8(self.identifier >> 8))
        packet.append(UInt8(self.identifier & 0xFF))
        packet.append(UInt8(self.sequence >> 8))
        packet.append(UInt8(self.sequence & 0xFF))
        packet.append(contentsOf: self.payload)

        let sum = Self.checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    private func validate(_ bytes: [UInt8]) -> Bool {
        let offset = Self.icmpOffset(bytes)
        let header = offset ?? 0
        guard bytes.count >= header + 16 else { return false }
        guard bytes[header] == 0, bytes[header + 1] == 0 else { return false }
        // The kernel rewrites the identifier for datagram ICMP sockets, so the
        // payload fingerprint is what proves this is our echo reply.
        return Array(bytes[(header + 8)..<(header + 16)]) == self.payload
    }

    /// Unprivileged ICMP sockets hand back the bare ICMP message, but be
    /// tolerant of an IPv4 header prefix.
    private static func icmpOffset(_ bytes: [UInt8]) -> Int? {
        guard let first = bytes.first else { return nil }
        guard first >> 4 == 4 else { return 0 }
        guard bytes.count >= 20, bytes[9] == UInt8(IPPROTO_ICMP) else { return nil }
        let headerLength = Int(first & 0x0F) * 4
        guard bytes.count >= headerLength + 8 else { return nil }
        return headerLength
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    private func resolve(_ host: String) -> sockaddr_in? {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        if inet_pton(AF_INET, host, &address.sin_addr) == 1 {
            return address
        }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        guard let raw = first.pointee.ai_addr else { return nil }
        return raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    // MARK: - HTTP

    private func checkHTTP() {
        var request = URLRequest(url: self.httpURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: self.httpTimeout)
        request.httpMethod = "HEAD"

        let semaphore = DispatchSemaphore(value: 0)
        let start = DispatchTime.now()
        var success = false
        var latency: Double = 0

        URLSession.shared.dataTask(with: request) { _, response, error in
            latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            if let http = response as? HTTPURLResponse {
                success = (200...399).contains(http.statusCode) && error == nil
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + self.httpTimeout + 1)

        if success {
            self.consecutiveFailures = 0
            self.record(latency)
        } else {
            self.emit(Connectivity(status: false))
        }
    }

    // MARK: - results

    private func record(_ latency: Double) {
        if let previous = self.previousLatency {
            let delta = abs(latency - previous)
            self.jitter += (delta - self.jitter) / 16.0
        } else {
            self.jitter = 0
        }
        self.previousLatency = latency
        self.emit(Connectivity(status: true, latency: latency, jitter: self.jitter))
    }
}
