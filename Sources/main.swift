import AppKit

Settings.registerDefaults()

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--login-item"), index + 1 < arguments.count {
    switch arguments[index + 1] {
    case "enable":
        if let error = LoginItem.set(true) {
            FileHandle.standardError.write(Data(("error=\(error)\n").utf8))
            exit(1)
        }
    case "disable":
        if let error = LoginItem.set(false) {
            FileHandle.standardError.write(Data(("error=\(error)\n").utf8))
            exit(1)
        }
    default:
        break
    }
    print("login-item=\(LoginItem.statusText)")
    exit(0)
}
if arguments.contains("--details") {
    CLISampler.details()
    exit(0)
}
if arguments.contains("--processes") {
    CLISampler.processes()
    exit(0)
}
if arguments.contains("--process-deltas") {
    CLISampler.processDeltas()
    exit(0)
}
if let index = arguments.firstIndex(of: "--connectivity") {
    var host: String? = nil
    if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") {
        host = arguments[index + 1]
    }
    CLISampler.connectivity(icmpHost: host)
    exit(0)
}
if arguments.contains("--ip") {
    CLISampler.publicIP()
    exit(0)
}
if arguments.contains("--usage") {
    CLISampler.usage(seconds: 3)
    exit(0)
}
if let index = arguments.firstIndex(of: "--format"), index + 1 < arguments.count, let bytes = Int64(arguments[index + 1]) {
    CLISampler.format(bytes)
    exit(0)
}
if let index = arguments.firstIndex(of: "--render") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "/tmp/netdog-render"
    DebugRenderer.render(to: directory)
    exit(0)
}
if let index = arguments.firstIndex(of: "--sample") {
    let seconds = index + 1 < arguments.count ? (Double(arguments[index + 1]) ?? 3) : 3
    CLISampler.run(seconds: seconds)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
