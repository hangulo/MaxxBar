import AppKit
import SwiftUI

@main
@MainActor
enum MaxxBarLauncher {
    private static var delegate: AppDelegate?

    static func main() {
        let shouldVerifyPopoverAction = CommandLine.arguments.contains("--verify-popover-action")
        let shouldVerifyPopOutAction = CommandLine.arguments.contains("--verify-popout-action")

        if CommandLine.arguments.contains("--input-monitoring-status") {
            print("inputMonitoring=\(CGPreflightListenEventAccess() ? "authorized" : "denied")")
            return
        }

        if let verifyImageIndex = CommandLine.arguments.firstIndex(of: "--verify-clipboard-image-store"),
           CommandLine.arguments.indices.contains(verifyImageIndex + 1) {
            let sourcePath = CommandLine.arguments[verifyImageIndex + 1]
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)),
                  let stored = ClipboardImageStore.save(
                    ClipboardImagePayload(data: data, typeIdentifier: "public.image"),
                    changeCount: 0
                  ) else {
                fputs("clipboard image verification failed\n", stderr)
                exit(1)
            }
            print("clipboardImage=\(stored.imagePath)")
            print("clipboardThumbnail=\(stored.thumbnailPath)")
            return
        }

        if let renderIndex = CommandLine.arguments.firstIndex(of: "--render-popover"),
           CommandLine.arguments.indices.contains(renderIndex + 1) {
            let path = CommandLine.arguments[renderIndex + 1]
            let panel = CommandLine.arguments.indices.contains(renderIndex + 2)
                ? StatsPanel(argument: CommandLine.arguments[renderIndex + 2])
                : .runway
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
            print("llmLimits=\(llmUsage.limits.map { limit in "\(limit.name):\(limit.shortWindow?.remainingPercent ?? -1)%/\(limit.weeklyWindow?.remainingPercent ?? -1)%" }.joined(separator: ","))")
            print("llmResetCredits=\(llmUsage.resetCreditCount.map(String.init) ?? "-")")
            print("llmLocalFiveHourTokens=\(llmUsage.localFiveHourTokens)")
            print("llmLocalWeeklyTokens=\(llmUsage.localWeeklyTokens)")
            print("llmLocalWeeklyThreads=\(llmUsage.localWeeklyThreads)")
            let sessionProviders = Dictionary(grouping: llmUsage.recentSessions, by: \.provider)
                .map { "\($0.key)=\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            print("llmSessionProviders=\(sessionProviders)")
            let modelUsage = llmUsage.modelUsageSummary()
            print("llmModelUsage=\(modelUsage.models.map { "\($0.provider):\($0.modelName)=\($0.sharePercent)%/\($0.tokens)t/\($0.sessionCount)s" }.joined(separator: ","))")
            let dailyModelUsage = llmUsage.modelUsageSummary(lastSeconds: 86_400)
            print("llmModelUsage24h=\(dailyModelUsage.models.map { "\($0.provider):\($0.modelName)=\($0.sharePercent)%/\($0.tokens)t/\($0.sessionCount)s" }.joined(separator: ","))")
            print("llmError=\(llmUsage.error ?? "-")")
            let aiUsage = AIUsageReader.recordAndRead(memory: snapshot, cpuGPU: .empty, llmUsage: llmUsage)
            print("aiActiveTool=\(aiUsage.activeTool ?? "-")")
            print("aiSessionsToday=\(aiUsage.sessionsToday)")
            print("aiTimeToday=\(Int(aiUsage.timeTodaySeconds))")
            print("aiTopTools=\(aiUsage.topTools.map { "\($0.label)=\($0.count)" }.joined(separator: ","))")
            print("aiProviderStats=\(aiUsage.providerSummaries.map { "\($0.provider):\($0.sessionsToday)sessions/\(Int($0.timeTodaySeconds))s/\($0.transferFlows.count)flows" }.joined(separator: ","))")
            let clipboard = ClipboardDebugReader.snapshot()
            print("clipboardWritesToday=\(clipboard.writesToday)")
            print("clipboardPastesToday=\(clipboard.pasteAttemptsToday)")
            print("clipboardImageWritesToday=\(clipboard.imageWritesToday)")
            print("clipboardKnownSourcePercent=\(clipboard.pasteSourceKnownPercent)")
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

        if CommandLine.arguments.contains("--write-ai-report") {
            if let url = AIUsageReader.writeReport() {
                print("aiReport=\(url.path)")
                return
            }
            fputs("AI report generation failed\n", stderr)
            exit(1)
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
        case "sensors", "cpu", "cpu/gpu", "cpugpu":
            self = .cpuGPU
        case "runway", "limits", "quota":
            self = .runway
        case "ai", "insights", "maxxinsights", "maxx-insights", "llm", "usage", "llmusage", "llm-usage":
            self = .llmUsage
        case "moments", "maxxmoment", "maxx-moment", "maxxmoments", "maxx-moments":
            self = .llmUsage
        case "clipboard", "clip", "pasteboard":
            self = .clipboard
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
    private var statusTitleView: StatusTitleView?
    private var popover: NSPopover?
    private var detachedWindow: NSWindow?
    private var timer: Timer?
    private let clipboardFlowMonitor = ClipboardFlowMonitor()
    private let clipboardMetadataMonitor = ClipboardMetadataMonitor()
    private var currentPopoverPanel: StatsPanel = .runway
    private var currentPopoverSize = PopoverSizePreference.load()

    init(shouldVerifyPopoverAction: Bool = false, shouldVerifyPopOutAction: Bool = false) {
        self.shouldVerifyPopoverAction = shouldVerifyPopoverAction
        self.shouldVerifyPopOutAction = shouldVerifyPopOutAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.seedInitialMemorySnapshot()
        startClipboardFlowMonitor()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.length = 108
        if let button = item.button {
            button.title = ""
            button.toolTip = statusToolTip()
            let titleView = StatusTitleView()
            titleView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(titleView)
            NSLayoutConstraint.activate([
                titleView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                titleView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
                titleView.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -0.5),
                titleView.heightAnchor.constraint(equalToConstant: NSStatusBar.system.thickness)
            ])
            titleView.setLines(statusTextLines())
            statusTitleView = titleView
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = currentPopoverSize
        popover.contentViewController = makePopoverContent(selectedPanel: .runway)
        self.popover = popover

        refreshStatusInBackground()
        refreshLLMUsageInBackground(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.startClipboardFlowMonitor()
                if self.isDetailedUIVisible {
                    self.refreshInBackground()
                } else {
                    self.refreshStatusInBackground()
                }
                // While the popover is closed, only the quotas refresh; transcript and Codex scans wait for the popover.
                self.refreshLLMUsageInBackground(refreshLocal: self.isDetailedUIVisible)
            }
        }
        timer?.tolerance = 5

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

    private func startClipboardFlowMonitor() {
        clipboardFlowMonitor.start { [weak self] eventType in
            self?.model.recordClipboardEvent(eventType)
        }
    }

    private func startClipboardMetadataMonitor() {
        clipboardMetadataMonitor.start { [weak self] changeCount, itemCount, typeIdentifiers, observedChange, imagePayload in
            if observedChange {
                self?.model.recordClipboardChange(
                    changeCount: changeCount,
                    itemCount: itemCount,
                    typeIdentifiers: typeIdentifiers,
                    imagePayload: imagePayload
                )
            } else {
                self?.model.recordCurrentClipboardState(
                    changeCount: changeCount,
                    itemCount: itemCount,
                    typeIdentifiers: typeIdentifiers
                )
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardFlowMonitor.stop()
    }

    private func refreshInBackground() {
        model.refreshInBackground { [weak self] in
            guard let self else { return }
            self.statusTitleView?.setLines(self.statusTextLines())
            self.statusItem?.button?.toolTip = self.statusToolTip()
        }
    }

    private func refreshStatusInBackground() {
        model.refreshStatusInBackground { [weak self] in
            guard let self else { return }
            self.statusTitleView?.setLines(self.statusTextLines())
            self.statusItem?.button?.toolTip = self.statusToolTip()
        }
    }

    private func refreshLLMUsageInBackground(force: Bool = false, refreshLocal: Bool = true) {
        model.refreshLLMUsageInBackground(force: force, refreshLocal: refreshLocal) { [weak self] in
            guard let self else { return }
            self.statusTitleView?.setLines(self.statusTextLines())
            self.statusItem?.button?.toolTip = self.statusToolTip()
        }
    }

    private var isDetailedUIVisible: Bool {
        popover?.isShown == true || detachedWindow?.isVisible == true
    }

    @objc private func togglePopover() {
        let selectedPanel = selectedPanelForCurrentClick()
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            if selectedPanel == currentPopoverPanel {
                popover.performClose(nil)
            } else {
                currentPopoverPanel = selectedPanel
                popover.contentViewController = makePopoverContent(selectedPanel: selectedPanel)
            }
        } else {
            currentPopoverPanel = selectedPanel
            popover.contentViewController = makePopoverContent(selectedPanel: selectedPanel)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            refreshInBackground()
            if selectedPanel == .llmUsage || selectedPanel == .runway {
                refreshLLMUsageInBackground(force: true)
            }
        }
    }

    private func selectedPanelForCurrentClick() -> StatsPanel {
        .runway
    }

    private func makePopoverContent(selectedPanel: StatsPanel) -> NSHostingController<MemoryPopoverView> {
        NSHostingController(
            rootView: MemoryPopoverView(
                model: model,
                onPopOut: { [weak self] in self?.showDetachedWindow() },
                onQuit: { NSApp.terminate(nil) },
                onStartDeepTrace: { [weak self] in self?.model.startDeepTrace() },
                selectedPanel: selectedPanel,
                fixedSize: false,
                resizableSize: currentPopoverSize,
                onResize: { [weak self] size in self?.resizePopover(to: size) ?? size }
            )
        )
    }

    @discardableResult
    private func resizePopover(to proposedSize: CGSize) -> CGSize {
        let size = PopoverSizePreference.clamped(proposedSize)
        currentPopoverSize = size
        popover?.contentSize = size
        PopoverSizePreference.save(size)
        return size
    }

    private func statusTextLines() -> (top: String, bottom: String) {
        func quota(_ name: String) -> String {
            guard let limit = model.llmUsage.limits.first(where: { $0.name == name }) else { return "--/--" }
            let short = limit.shortWindow.map { String($0.remainingPercent) } ?? "--"
            let weekly = limit.weeklyWindow.map { String($0.remainingPercent) } ?? "--"
            return "\(short)/\(weekly)\(limit.cachedAt == nil ? "" : "~")"
        }
        return ("Claude Codex", "\(quota("Claude")) \(quota("Codex"))")
    }

    private func aiTimeLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)"
        }
        return "\(minutes)m"
    }

    private func statusToolTip() -> String {
        let usage = model.aiUsage
        return """
        Claude and Codex: 5h / weekly percent remaining (~ = last checked reading)
        \(model.llmUsage.providerErrors.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
        AI today: \(usage.sessionsToday) sessions · \(aiTimeLabel(usage.timeTodaySeconds)) inferred time
        \(usage.copyEventsToday) copy · \(usage.pasteEventsToday) paste · \(usage.insightEventsToday) insight events
        """
    }

    private func hoursLeftLabel(_ resetAt: Date?) -> String {
        guard let resetAt else { return "--" }
        let seconds = max(resetAt.timeIntervalSinceNow, 0)
        if seconds < 3_600 {
            let minutes = max(Int(ceil(seconds / 60)), 0)
            return "\(minutes)m"
        }

        let hours = seconds / 3_600
        let rounded = (hours * 2).rounded() / 2
        if rounded.rounded() == rounded {
            return "\(Int(rounded))H"
        }
        return String(format: "%.1fH", rounded)
    }

    private func weekdayLabel(_ resetAt: Date?) -> String {
        guard let resetAt else { return "Day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: resetAt)
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
                selectedPanel: .runway,
                fixedSize: false
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

@MainActor
private enum PopoverSizePreference {
    static let defaultSize = NSSize(width: 306, height: 662)
    static let minimumSize = NSSize(width: 280, height: 480)
    static let maximumWidth: CGFloat = 640
    private static let widthKey = "MaxxBar.popoverWidth"
    private static let heightKey = "MaxxBar.popoverHeight"

    static func load() -> NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: widthKey)
        let height = defaults.double(forKey: heightKey)
        guard width > 0, height > 0 else { return defaultSize }
        return clamped(NSSize(width: width, height: height))
    }

    static func save(_ size: NSSize) {
        UserDefaults.standard.set(Double(size.width), forKey: widthKey)
        UserDefaults.standard.set(Double(size.height), forKey: heightKey)
    }

    static func clamped(_ size: NSSize) -> NSSize {
        let availableHeight = NSScreen.main.map {
            max($0.visibleFrame.height - 44, minimumSize.height)
        } ?? 900
        return NSSize(
            width: min(max(size.width, minimumSize.width), maximumWidth),
            height: min(max(size.height, minimumSize.height), availableHeight)
        )
    }
}

final class StatusTitleView: NSView {
    private var topItems = ["5H", "Week"]
    private var bottomItems = ["-", "-"]
    private let amberUsageColor = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.18, alpha: 1.0)
    private let lowUsageColor = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.62, alpha: 1.0)
    private let criticalUnderlineColor = NSColor(calibratedRed: 1.0, green: 0.16, blue: 0.1, alpha: 1.0)

    override var isFlipped: Bool { true }

    func setLines(_ lines: (top: String, bottom: String)) {
        topItems = lines.top.split(separator: " ").map(String.init)
        bottomItems = lines.bottom.split(separator: " ").map(String.init)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let columns = max(topItems.count, bottomItems.count, 1)
        let columnWidth = bounds.width / CGFloat(columns)
        let regularTopFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let regularBottomFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        let warningTopFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let warningBottomFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let topY = max(0, floor((bounds.height - 24) / 2) - 1)
        let bottomY = topY + 11

        for index in 0..<columns {
            let x = CGFloat(index) * columnWidth
            let warningColor = warningColorForColumn(at: index)
            let isWarning = warningColor != nil
            let itemColor = warningColor ?? NSColor.labelColor
            drawCentered(
                topItems.indices.contains(index) ? topItems[index] : "",
                x: x,
                y: topY,
                width: columnWidth,
                attributes: [
                    .font: isWarning ? warningTopFont : regularTopFont,
                    .foregroundColor: itemColor
                ]
            )
            let bottomRect = drawCentered(
                bottomItems.indices.contains(index) ? bottomItems[index] : "",
                x: x,
                y: bottomY,
                width: columnWidth,
                attributes: [
                    .font: isWarning ? warningBottomFont : regularBottomFont,
                    .foregroundColor: itemColor
                ]
            )
            if shouldUnderlineColumn(at: index) {
                drawUnderline(under: bottomRect)
            }
        }
    }

    private func warningColorForColumn(at index: Int) -> NSColor? {
        guard index < 2,
              bottomItems.indices.contains(index),
              let percent = bottomItems[index].replacingOccurrences(of: "~", with: "").split(separator: "/").compactMap { Int($0) }.min() else {
            return nil
        }

        if percent < 15 {
            return lowUsageColor
        } else if percent < 25 {
            return amberUsageColor
        }

        return nil
    }

    private func shouldUnderlineColumn(at index: Int) -> Bool {
        guard index < 2,
              bottomItems.indices.contains(index),
              let percent = bottomItems[index].replacingOccurrences(of: "~", with: "").split(separator: "/").compactMap { Int($0) }.min() else {
            return false
        }

        return percent < 15
    }

    private func drawUnderline(under rect: NSRect) {
        guard !rect.isEmpty else { return }
        criticalUnderlineColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.4
        let y = rect.maxY - 1
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.line(to: NSPoint(x: rect.maxX, y: y))
        path.stroke()
    }

    @discardableResult
    private func drawCentered(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSRect {
        guard !text.isEmpty else { return .zero }
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: x + (width - size.width) / 2, y: y, width: size.width, height: size.height)
        text.draw(in: rect, withAttributes: attributes)
        return rect
    }
}
