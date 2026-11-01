import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已启用"
        case .requiresApproval: return "等待系统批准（系统设置 › 通用 › 登录项）"
        case .notRegistered: return "未启用"
        case .notFound: return "未找到应用"
        @unknown default: return "未知"
        }
    }

    /// Returns an error message on failure.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
