import AppKit
import CoreGraphics

@MainActor
final class ClipboardFlowMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var requestedAccess = false
    private var shortcutHandler: ((String) -> Void)?

    func start(onShortcut: @escaping (String) -> Void) {
        guard eventTap == nil, fallbackMonitor == nil else { return }
        guard CGPreflightListenEventAccess() else {
            if !requestedAccess {
                requestedAccess = true
                _ = CGRequestListenEventAccess()
            }
            return
        }
        shortcutHandler = onShortcut

        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard type == .keyDown, let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<ClipboardFlowMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            let flags = event.flags
            guard flags.contains(.maskCommand) else { return Unmanaged.passUnretained(event) }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let eventType: String?
            switch keyCode {
            case 8: eventType = "copy"
            case 9: eventType = "paste"
            default: eventType = nil
            }
            if let eventType {
                Task { @MainActor in
                    monitor.emit(eventType)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }

        // Retain the AppKit monitor as a compatibility fallback if an event tap
        // cannot be created despite a positive preflight authorization check.
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else { return }
            switch event.keyCode {
            case 8: onShortcut("copy")
            case 9: onShortcut("paste")
            default: break
            }
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let fallbackMonitor {
            NSEvent.removeMonitor(fallbackMonitor)
            self.fallbackMonitor = nil
        }
        shortcutHandler = nil
    }

    private func emit(_ eventType: String) {
        shortcutHandler?(eventType)
    }
}
