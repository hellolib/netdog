import Foundation

struct Bandwidth {
    var upload: Int64 = 0
    var download: Int64 = 0
}

enum SizeUnit: String, CaseIterable {
    case KB
    case MB
    case GB
    case TB

    var divisor: Double {
        switch self {
        case .KB: return 1_000
        case .MB: return 1_000_000
        case .GB: return 1_000_000_000
        case .TB: return 1_000_000_000_000
        }
    }

    var prefix: String {
        switch self {
        case .KB: return "K"
        case .MB: return "M"
        case .GB: return "G"
        case .TB: return "T"
        }
    }
}

/// Speed formatting ported from Stats' Units.getReadableTuple:
/// decimal units, optional bit base, optional fixed unit.
enum Units {
    static func readableSpeed(
        _ bytes: Int64,
        base: DataSizeBase = Settings.base,
        unit: String = Settings.speedUnit,
        omitUnits: Bool = false
    ) -> String {
        let (value, suffix) = readableTuple(bytes, base: base, unit: unit)
        return omitUnits ? value : "\(value) \(suffix)"
    }

    static func readableTuple(
        _ bytes: Int64,
        base: DataSizeBase = Settings.base,
        unit: String = Settings.speedUnit
    ) -> (String, String) {
        let stringBase = base == .byte ? "B" : "b"
        let multiplier: Double = base == .byte ? 1 : 8
        let safeBytes = Double(max(bytes, 0))

        if unit != "auto", let sizeUnit = SizeUnit(rawValue: unit) {
            let value = safeBytes / sizeUnit.divisor * multiplier
            return (String(format: "%.2f", value), "\(sizeUnit.prefix)\(stringBase)/s")
        }

        let value = safeBytes * multiplier
        switch value {
        case ..<1_000:
            return ("0", "K\(stringBase)/s")
        case 1_000..<1_000_000:
            return (String(format: "%.0f", value / 1_000), "K\(stringBase)/s")
        case 1_000_000..<100_000_000:
            return (String(format: "%.1f", value / 1_000_000), "M\(stringBase)/s")
        case 100_000_000..<1_000_000_000:
            return (String(format: "%.0f", value / 1_000_000), "M\(stringBase)/s")
        case 1_000_000_000..<1_000_000_000_000:
            return (String(format: "%.1f", value / 1_000_000_000), "G\(stringBase)/s")
        default:
            return (String(format: "%.1f", value / 1_000_000_000_000), "T\(stringBase)/s")
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

    static func bytes(_ value: Int, unit: String) -> Int64 {
        guard let sizeUnit = SizeUnit(rawValue: unit) else { return Int64(value) }
        return Int64(Double(value) * sizeUnit.divisor)
    }
}
