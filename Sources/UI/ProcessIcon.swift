import AppKit
import Darwin

/// Process icons resolved lazily from the running application or its executable.
final class ProcessIconCache {
    static let shared = ProcessIconCache()

    private var cache: [Int: NSImage] = [:]
    private lazy var fallback: NSImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) ?? NSImage()

    func icon(for pid: Int) -> NSImage {
        if let cached = self.cache[pid] {
            return cached
        }
        let image = NSRunningApplication(processIdentifier: pid_t(pid))?.icon
            ?? self.iconFromExecutable(pid)
            ?? self.fallback
        self.cache[pid] = image
        return image
    }

    private func iconFromExecutable(_ pid: Int) -> NSImage? {
        // PROC_PIDPATHINFO_MAXSIZE is not exposed to Swift; 4*MAXPATHLEN = 4096.
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }
}
