import Foundation
import ServiceManagement

/// Opens MaxxBar at login through the system login items list (System Settings > General > Login Items).
/// A six day gap in the quota history came from the app not being started after a restart, so this is on by default.
enum LaunchAtLogin {
    static let enabledKey = "launchAtLogin"
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers once on first launch of an installed bundle. After that the user's choice, made in the
    /// popover menu or in System Settings, is left alone.
    static func applyDefaultIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              !UserDefaults.standard.bool(forKey: defaultAppliedKey) else { return }
        UserDefaults.standard.set(true, forKey: defaultAppliedKey)
        setEnabled(true)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail for an unsigned build or when the user removed it in System Settings.
        }
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
        return isEnabled
    }
}
