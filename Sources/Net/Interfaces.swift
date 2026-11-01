import Darwin
import Foundation
import SystemConfiguration

/// Ported from Stats UsageReader: primary interface via SCDynamicStore,
/// with utun/VPN interfaces traced back to the physical link.
enum InterfaceResolver {
    static let virtualPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "wg"]

    static func primary() -> String {
        if let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let name = global["PrimaryInterface"] as? String, !name.isEmpty {
            if isVirtual(name), let physical = self.physical() {
                return physical
            }
            return name
        }
        return self.physical() ?? ""
    }

    static func isVirtual(_ name: String) -> Bool {
        return virtualPrefixes.contains { name.hasPrefix($0) }
    }

    private static func physical() -> String? {
        if let setup = SCDynamicStoreCopyValue(nil, "Setup:/Network/Global/IPv4" as CFString) as? [String: Any],
           let order = setup["ServiceOrder"] as? [String] {
            for serviceID in order {
                guard let service = SCDynamicStoreCopyValue(nil, "State:/Network/Service/\(serviceID)/IPv4" as CFString) as? [String: Any],
                      service["Router"] != nil,
                      let name = service["InterfaceName"] as? String,
                      !isVirtual(name) else {
                    continue
                }
                return name
            }
        }

        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0 else { return nil }
        defer { freeifaddrs(interfaceAddresses) }

        var pointer = interfaceAddresses
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  flags & IFF_POINTOPOINT == 0,
                  let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: current.pointee.ifa_name)
            if !isVirtual(name) {
                return name
            }
        }

        return nil
    }
}

/// Raw byte counters for one interface, read from the routing table
/// (same NET_RT_IFLIST2 source Stats uses).
enum InterfaceCounters {
    static func bytes(for name: String) -> Bandwidth? {
        let index = if_nametoindex(name)
        guard index != 0 else { return nil }

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var size: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }

        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= size {
            var header = if_msghdr()
            buffer.withUnsafeBytes { src in
                _ = memcpy(&header, src.baseAddress?.advanced(by: offset), MemoryLayout<if_msghdr>.size)
            }
            guard header.ifm_msglen > 0 else { return nil }

            if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= size {
                var header2 = if_msghdr2()
                buffer.withUnsafeBytes { src in
                    _ = memcpy(&header2, src.baseAddress?.advanced(by: offset), MemoryLayout<if_msghdr2>.size)
                }
                if header2.ifm_index == index {
                    return Bandwidth(
                        upload: Int64(clamping: header2.ifm_data.ifi_obytes),
                        download: Int64(clamping: header2.ifm_data.ifi_ibytes)
                    )
                }
            }

            offset += Int(header.ifm_msglen)
        }

        return nil
    }
}
