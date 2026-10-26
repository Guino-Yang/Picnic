import Foundation
import ServiceManagement

final class LoginItems: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        error = nil
        do {
            if value {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = L10n.format(.loginError, error.localizedDescription)
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    static var diagnostics: [String: Any] {
        let status: String
        switch SMAppService.mainApp.status {
        case .enabled: status = "enabled"
        case .notRegistered: status = "notRegistered"
        case .requiresApproval: status = "requiresApproval"
        case .notFound: status = "notFound"
        @unknown default: status = "unknown"
        }
        return ["loginItemStatus": status, "appPath": Bundle.main.bundlePath]
    }
}
