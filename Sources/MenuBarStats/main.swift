import AppKit
import SwiftUI

@main
@MainActor
enum MenuBarStatsLauncher {
    private static var delegate: AppDelegate?

    static func main() {
        let shouldVerifyPopoverAction = CommandLine.arguments.contains("--verify-popover-action")
        let shouldVerifyPopOutAction = CommandLine.arguments.contains("--verify-popout-action")

        if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-popover"),
           CommandLine.arguments.indices.contains(renderIndex + 1) {
            let path = CommandLine.arguments[renderIndex + 1]
            let panel = CommandLine.arguments.indices.contains(renderIndex + 2)
                ? StatsPanel(argument: CommandLine.arguments[renderIndex + 2])
                : .memory
            do {
                try PopoverRenderer.renderDemo(to: URL(fileURLWithPath: path), panel: panel)
                print("rendered=\(path)")
            } catch {
                fputs("render failed: \(error)\n", stderr)
                exit(1)
            }
            return
        }

        if CommandLine.arguments.contains("--sample") {
            let snapshot = MemoryReader.read()
            print("pressure=\(snapshot.pressurePercent)%")
            print("memory=\(snapshot.usedPercent)%")
            print("app=\(ByteFormat.memory(snapshot.breakdown.app))")
            print("wired=\(ByteFormat.memory(snapshot.breakdown.wired))")
            print("compressed=\(ByteFormat.memory(snapshot.breakdown.compressed))")
            print("free=\(ByteFormat.memory(snapshot.breakdown.free))")
            print("pageIns=\(ByteFormat.memory(snapshot.pageIns))")
            print("pageOuts=\(ByteFormat.memory(snapshot.pageOuts))")
            print("swap=\(ByteFormat.memory(snapshot.swapUsed))/\(ByteFormat.memory(snapshot.swapTotal))")
            print("processes=\(snapshot.processes.map(\.name).joined(separator: ","))")
            print("processTotals=\(snapshot.processes.map { "\($0.name)=\(ByteFormat.memory($0.bytes))" }.joined(separator: ","))")
            print("processRows=\(snapshot.processRows.map { "\($0.name)=\(ByteFormat.memory($0.bytes))" }.joined(separator: ","))")
            print("processAppPaths=\(snapshot.processes.map { $0.appPath ?? "-" }.joined(separator: "|"))")
            let firstNetwork = NetworkReader.read(previous: nil, history: [])
            Thread.sleep(forTimeInterval: 1)
            let secondNetwork = NetworkReader.read(previous: firstNetwork.counters, history: firstNetwork.snapshot.history)
            let network = secondNetwork.snapshot
            print("networkInterface=\(network.interfaceName ?? "-")")
            print("networkUpload=\(ByteFormat.rate(network.uploadBytesPerSecond))")
            print("networkDownload=\(ByteFormat.rate(network.downloadBytesPerSecond))")
            print("networkIPs=\(network.ipAddresses.joined(separator: ","))")
            let llmUsage = LLMUsageReader.read()
            print("llmPlan=\(llmUsage.planType ?? "-")")
            print("llmEmail=\(llmUsage.email ?? "-")")
            print("llmLimits=\(llmUsage.limits.map { limit in "\(limit.name):\(limit.primary?.remainingPercent ?? -1)%/\(limit.secondary?.remainingPercent ?? -1)%" }.joined(separator: ","))")
            print("llmLocalFiveHourTokens=\(llmUsage.localFiveHourTokens)")
            print("llmLocalWeeklyTokens=\(llmUsage.localWeeklyTokens)")
            print("llmError=\(llmUsage.error ?? "-")")
            let sensors = SensorReader.read()
            print("sensorCPUTemp=\(sensors.cpuTemperature.map { String(format: "%.1f C", $0) } ?? "-")")
            print("sensorGPUTemp=\(sensors.gpuTemperature.map { String(format: "%.1f C", $0) } ?? "-")")
            print("sensorBatteryTemp=\(sensors.batteryTemperature.map { String(format: "%.1f C", $0) } ?? "-")")
            print("sensorFans=\(sensors.fanReadings.map { "\($0.label)=\($0.rpm) rpm" }.joined(separator: ","))")
            print("sensorTemperatures=\(sensors.temperatureReadings.map { "\($0.label)=\(String(format: "%.1f C", $0.celsius))" }.joined(separator: ","))")
            print("sensorPower=\(sensors.power.map { String(format: "%.1f W", $0) } ?? "-")")
            print("sensorAmperage=\(sensors.amperage.map { String(format: "%.2f A", $0) } ?? "-")")
            print("sensorVoltage=\(sensors.voltage.map { String(format: "%.2f V", $0) } ?? "-")")
            let firstCPU = CPUReader.read(previous: nil)
            Thread.sleep(forTimeInterval: 1)
            let secondCPU = CPUReader.read(previous: firstCPU.current).snapshot
            print("cpuUser=\(secondCPU.cpuUserPercent)%")
            print("cpuSystem=\(secondCPU.cpuSystemPercent)%")
            print("cpuProcesses=\(secondCPU.processes.map { "\($0.name)=\(String(format: "%.1f%%", $0.cpuPercent))" }.joined(separator: ","))")
            print("cpuProcessesRaw=\(secondCPU.processes.map { "\($0.name)=\(String(format: "%.1f%%", $0.rawCPUPercent))" }.joined(separator: ","))")
            print("cpuCores=\(secondCPU.coreLoads.map { "\($0.kind == .efficiency ? "E" : "P")\($0.index + 1)=\($0.percent)%" }.joined(separator: ","))")
            return
        }

        let app = NSApplication.shared
        let appDelegate = AppDelegate(
            shouldVerifyPopoverAction: shouldVerifyPopoverAction,
            shouldVerifyPopOutAction: shouldVerifyPopOutAction
        )
        delegate = appDelegate
        app.delegate = appDelegate
        app.run()
    }
}

extension StatsPanel {
    init(argument: String) {
        switch argument.lowercased() {
        case "sensors":
            self = .sensors
        case "cpu", "cpu/gpu", "cpugpu":
            self = .cpuGPU
        case "network", "net":
            self = .network
        case "llm", "usage", "llmusage", "llm-usage":
            self = .llmUsage
        default:
            self = .memory
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MemoryModel()
    private let shouldVerifyPopoverAction: Bool
    private let shouldVerifyPopOutAction: Bool
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var detachedWindow: NSWindow?
    private var timer: Timer?

    init(shouldVerifyPopoverAction: Bool = false, shouldVerifyPopOutAction: Bool = false) {
        self.shouldVerifyPopoverAction = shouldVerifyPopoverAction
        self.shouldVerifyPopOutAction = shouldVerifyPopOutAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        item.button?.alignment = .center
        item.button?.lineBreakMode = .byWordWrapping
        item.button?.attributedTitle = statusAttributedTitle()
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 306, height: 662)
        popover.contentViewController = makePopoverContent(selectedPanel: .llmUsage)
        self.popover = popover

        refreshInBackground()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInBackground()
            }
        }

        if shouldVerifyPopoverAction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.verifyPopoverAction()
            }
        }

        if shouldVerifyPopOutAction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.verifyPopOutAction()
            }
        }
    }

    private func refreshInBackground() {
        model.refreshInBackground { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.attributedTitle = self.statusAttributedTitle()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentViewController = makePopoverContent(selectedPanel: .llmUsage)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            refreshInBackground()
        }
    }

    private func makePopoverContent(selectedPanel: StatsPanel) -> NSHostingController<MemoryPopoverView> {
        NSHostingController(
            rootView: MemoryPopoverView(
                model: model,
                onPopOut: { [weak self] in self?.showDetachedWindow() },
                onQuit: { NSApp.terminate(nil) },
                selectedPanel: selectedPanel
            )
        )
    }

    private func statusTextLines() -> (top: String, bottom: String) {
        guard let codexLimit = model.llmUsage.limits.first(where: { $0.name == "Codex" }) ?? model.llmUsage.limits.first,
              let fiveHourRemaining = codexLimit.primary?.remainingPercent,
              let weeklyRemaining = codexLimit.secondary?.remainingPercent else {
            return ("MEM", "\(model.snapshot.pressurePercent)%")
        }

        return (
            "5H       WK       MEM",
            "\(fiveHourRemaining)% left   \(weeklyRemaining)% left   \(model.snapshot.pressurePercent)%"
        )
    }

    private func statusAttributedTitle() -> NSAttributedString {
        let lines = statusTextLines()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = -1

        let text = "\(lines.top)\n\(lines.bottom)"
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
                .baselineOffset: -0.5
            ]
        )
    }

    private func statusTitleForDebug() -> String {
        let lines = statusTextLines()
        return "\(lines.top) / \(lines.bottom)"
    }

    private func verifyPopoverAction() {
        togglePopover()
        let shown = popover?.isShown == true
        let title = statusTitleForDebug()
        print("statusTitle=\(title)")
        print("popoverShown=\(shown)")

        if shown {
            popover?.performClose(nil)
            NSApp.terminate(nil)
        } else {
            fputs("popover verification failed\n", stderr)
            exit(1)
        }
    }

    private func showDetachedWindow() {
        popover?.performClose(nil)

        if let detachedWindow {
            detachedWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshInBackground()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 306, height: 662),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Memory"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 290, height: 595)
        window.contentViewController = NSHostingController(
            rootView: MemoryPopoverView(
                model: model,
                onQuit: { NSApp.terminate(nil) },
                selectedPanel: .llmUsage
            )
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        detachedWindow = window
        refreshInBackground()
    }

    private func verifyPopOutAction() {
        showDetachedWindow()
        let visible = detachedWindow?.isVisible == true
        print("detachedWindowVisible=\(visible)")

        if visible {
            detachedWindow?.close()
            NSApp.terminate(nil)
        } else {
            fputs("pop-out verification failed\n", stderr)
            exit(1)
        }
    }
}
