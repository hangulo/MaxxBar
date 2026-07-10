import AppKit
import CoreGraphics

@MainActor
final class ClipboardFlowMonitor {
    private var monitor: Any?
    private var requestedAccess = false

    func start(onShortcut: @escaping (String) -> Void) {
        guard monitor == nil else { return }
        guard CGPreflightListenEventAccess() else {
            if !requestedAccess {
                requestedAccess = true
                _ = CGRequestListenEventAccess()
            }
            return
        }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else { return }
            switch event.keyCode {
            case 8: onShortcut("copy")
            case 9: onShortcut("paste")
            default: break
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
