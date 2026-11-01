import Foundation

struct Bandwidth {
    var upload: Int64 = 0
    var download: Int64 = 0
}

/// Byte-based speed formatting, ported from Stats' Units.getReadableTuple.
/// Decimal units (1000-based) and "0 KB/s" for anything under 1 KB/s.
enum Units {
    static func readableSpeed(_ bytes: Int64, omitUnits: Bool = false) -> String {
        let (value, unit) = readableTuple(bytes)
        return omitUnits ? value : "\(value) \(unit)"
    }

    static func readableTuple(_ bytes: Int64) -> (String, String) {
        let value = Double(max(bytes, 0))
        switch value {
        case ..<1_000:
            return ("0", "KB/s")
        case 1_000..<1_000_000:
            return (String(format: "%.0f", value / 1_000), "KB/s")
        case 1_000_000..<100_000_000:
            return (String(format: "%.1f", value / 1_000_000), "MB/s")
        case 100_000_000..<1_000_000_000:
            return (String(format: "%.0f", value / 1_000_000), "MB/s")
        case 1_000_000_000..<1_000_000_000_000:
            return (String(format: "%.1f", value / 1_000_000_000), "GB/s")
        default:
            return (String(format: "%.1f", value / 1_000_000_000_000), "TB/s")
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func readableMemory(_ bytes: Int64) -> String {
        return self.byteFormatter.string(fromByteCount: max(bytes, 0))
    }
}
