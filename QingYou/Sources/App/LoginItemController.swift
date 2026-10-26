import AppKit
import Combine
import CoreServices
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?
    private let service: LoginItemService
    private let openSettings: () -> Void
    private let defaults: UserDefaults
    private let defaultAppliedKey = "loginItemDefaultApplied"

    init(service: LoginItemService = SMAppService.mainApp,
         defaults: UserDefaults = .standard,
         openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }) {
        self.service = service
        self.defaults = defaults
        self.openSettings = openSettings
        status = service.status
    }

    // 系统才是登录项状态的来源，不在 JSON 中保存另一份容易失真的开关。
    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }
    var detail: String {
        switch status {
        case .enabled: return "已开启。登录 Mac 后驻留菜单栏，不弹出主窗口。"
        case .requiresApproval: return "尚未启用，请在系统设置的登录项中允许轻右。"
        case .notRegistered: return "已关闭。开启后，登录 Mac 时自动运行轻右。"
        case .notFound: return "系统尚无可用的登录项状态。开启后，轻右会尝试注册自动启动。"
        @unknown default: return "暂时无法确认状态，请查看系统登录项。"
        }
    }

    func refresh() { status = service.status }

    func applyDefaultIfNeeded() {
        guard !defaults.bool(forKey: defaultAppliedKey) else { refresh(); return }
        // 只申请一次；系统拒绝或用户日后关闭时，不在每次启动中反复申请。
        defaults.set(true, forKey: defaultAppliedKey)
        refresh()
        if status == .notRegistered || status == .notFound { setEnabled(true) }
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: defaultAppliedKey)
        errorMessage = nil
        refresh()
        do {
            if enabled {
                if needsApproval { openSystemSettings(); return }
                if !isEnabled { try service.register() }
            } else if status == .enabled || needsApproval {
                try service.unregister()
            }
        } catch {
            errorMessage = "未能更新自动启动：\(error.localizedDescription)"
        }
        // 即使调用失败也重新读取，避免界面错误地显示“已开启”。
        refresh()
    }

    func openSystemSettings() { openSettings() }

    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
    }
}
