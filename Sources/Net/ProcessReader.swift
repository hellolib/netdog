import AppKit
import Darwin
import Foundation

struct ProcessUsage {
    var pid: Int
    var name: String
    var download: Int
    var upload: Int
    var lastActive: Date
}

final class ProcessReader: Reader<[ProcessUsage]> {
    static let maxCount = Settings.maxProcessCount

    private var previous: [ProcessUsage] = []

    init(interval: TimeInterval = 2, handler: @escaping ([ProcessUsage]) -> Void) {
        super.init(label: "netdog.process", interval: interval, handler: handler)
    }

    override func read() {
        let limit = Settings.processCount
        guard limit > 0 else { return }

        guard let output = Self.nettopOutput() else { return }
        let list = Self.parse(output)

        var processes: [ProcessUsage] = []
        if self.previous.isEmpty {
            self.previous = list
            processes = list
        } else {
            for old in self.previous {
                guard let index = list.firstIndex(where: { $0.pid == old.pid }) else { continue }
                let current = list[index]

                var download = current.download - old.download
                var upload = current.upload - old.upload
                let lastActive = download == 0 && upload == 0 ? old.lastActive : Date()

                if download < 0 { download = 0 }
                if upload < 0 { upload = 0 }

                processes.append(ProcessUsage(
                    pid: current.pid,
                    name: current.name,
                    download: download,
                    upload: upload,
                    lastActive: lastActive
                ))
            }
            self.previous = list
        }

        // Same ordering as Stats: by max(download, upload), then min, then recency.
        let sorted = processes.sorted {
            let leftMax = max($0.download, $0.upload)
            let rightMax = max($1.download, $1.upload)
            if leftMax != rightMax { return leftMax > rightMax }

            let leftMin = min($0.download, $0.upload)
            let rightMin = min($1.download, $1.upload)
            if leftMin != rightMin { return leftMin > rightMin }

            return $0.lastActive > $1.lastActive
        }

        self.emit(Array(sorted.prefix(limit)))
    }

    /// One raw nettop sample (cumulative bytes per process, all interfaces).
    static func snapshot() -> [ProcessUsage] {
        guard let output = self.nettopOutput() else { return [] }
        let list = self.parse(output)
        return Array(list.sorted { max($0.download, $0.upload) > max($1.download, $1.upload) }.prefix(self.maxCount))
    }

    /// System-wide cumulative bytes across all processes, used when the
    /// bandwidth reader type is "processes based" (Stats' readProcessBandwidth).
    static func totalBytes() -> Bandwidth? {
        guard let output = self.nettopOutput() else { return nil }
        var total = Bandwidth()
        var firstLine = true
        output.enumerateLines { line, _ in
            if firstLine {
                firstLine = false
                return
            }
            let fields = line.split(separator: ",")
            guard fields.count >= 3 else { return }
            total.download += Int64(Int(fields[1]) ?? 0)
            total.upload += Int64(Int(fields[2]) ?? 0)
        }
        return total
    }

    private static func nettopOutput() -> String? {
        return Shell.run(
            path: "/usr/bin/nettop",
            arguments: ["-P", "-L", "1", "-n", "-k", "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch"],
            environment: ["NSUnbufferedIO": "YES", "LC_ALL": "en_US.UTF-8"],
            timeout: 5
        )
    }

    private static func processName(pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = buffer.withUnsafeMutableBytes { raw -> Int32 in
            proc_name(pid_t(pid), raw.baseAddress, UInt32(raw.count))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parse(_ output: String) -> [ProcessUsage] {
        var list: [ProcessUsage] = []
        var firstLine = true
        output.enumerateLines { line, _ in
            if firstLine {
                firstLine = false
                return
            }
            let fields = line.split(separator: ",")
            guard fields.count >= 3 else { return }

            let nameParts = fields[0].split(separator: ".")
            guard let pidString = nameParts.last, let pid = Int(pidString) else { return }

            var name = nameParts.dropLast().joined(separator: ".")
            if let app = NSRunningApplication(processIdentifier: pid_t(pid)), let localized = app.localizedName {
                name = localized
            } else if let fullName = self.processName(pid: pid) {
                // nettop truncates long names, libproc has the real one.
                name = fullName
            }
            if name.isEmpty {
                name = "\(pid)"
            }

            list.append(ProcessUsage(
                pid: pid,
                name: name,
                download: Int(fields[1]) ?? 0,
                upload: Int(fields[2]) ?? 0,
                lastActive: Date()
            ))
        }
        return list
    }
}

enum Shell {
    static func run(path: String, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        if let environment {
            task.environment = environment
        }

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem {
            if task.isRunning {
                task.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        watchdog.cancel()

        return String(data: data, encoding: .utf8)
    }
}
