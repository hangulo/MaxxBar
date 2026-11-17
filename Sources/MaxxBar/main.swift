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

        if let index = CommandLine.arguments.firstIndex(of: "--render-share-card"),
           CommandLine.arguments.indices.contains(index + 1) {
            // --render-share-card <path> [demo] [so-far] [dollars]: writes the weekly share card PNG and exits.
            let arguments = CommandLine.arguments
            let path = arguments[index + 1]
            let summary: WeeklyShareSummary?
            if arguments.contains("demo") {
                summary = WeeklyShareCard.demo()
            } else {
                let historyURL = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Application Support/MaxxBar/llm-quota-history.json")
                let history = (try? Data(contentsOf: historyURL))
                    .flatMap { try? JSONDecoder().decode([LLMQuotaHistorySample].self, from: $0) } ?? []
                let latest = history.filter { $0.claudeWeeklyRemainingPercent != nil }.max { $0.sampledAt < $1.sampledAt }
                let live = latest.flatMap { sample in
                    sample.claudeWeeklyResetAt.flatMap { reset in
                        reset > Date() ? WeeklyShareCard.LiveWeek(
                            usedPercent: 100 - (sample.claudeWeeklyRemainingPercent ?? 100), resetAt: reset
                        ) : nil
                    }
                }
                summary = WeeklyShareCard.summary(
                    records: QuotaWindowLedgerStore.load(), live: live, plan: latest?.claudePlanType,
                    period: arguments.contains("so-far") ? .thisWeekSoFar : .lastFullWeek
                ) { APICostLedger.days(provider: "Claude", from: $0, through: $1) }
            }
            guard let summary else {
                fputs("no closed weekly window or live weekly reading yet\n", stderr)
                exit(1)
            }
            do {
                try WeeklyShareCardExporter.write(summary, showDollars: arguments.contains("dollars"), to: URL(fileURLWithPath: path))
                print("rendered=\(path)")
            } catch {
                fputs("render failed: \(error)\n", stderr)
                exit(1)
            }
            return
        }

        if let index = CommandLine.arguments.firstIndex(of: "--write-usage-report") {
            // Writes the usage report without opening it: --write-usage-report [path]
            let arguments = CommandLine.arguments
            let target = index + 1 < arguments.count ? URL(fileURLWithPath: arguments[index + 1]) : UsageReport.url
            let historyURL = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/MaxxBar/llm-quota-history.json")
            let history = (try? Data(contentsOf: historyURL))
                .flatMap { try? JSONDecoder().decode([LLMQuotaHistorySample].self, from: $0) } ?? []
            let started = Date()
            let written = UsageReport.write(ledger: QuotaWindowLedgerStore.load(), history: history, to: target)
            print(written.map { "wrote \($0.path) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s" } ?? "failed")
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
    private var lastVisibleProviders = ProviderVisibility.visibleProviders
    private var pauseReasons = Set<String>()
    private let clipboardFlowMonitor = ClipboardFlowMonitor()
    private var currentPopoverPanel: StatsPanel = .runway
    private var currentPopoverSize = PopoverSizePreference.load()

    init(shouldVerifyPopoverAction: Bool = false, shouldVerifyPopOutAction: Bool = false) {
        self.shouldVerifyPopoverAction = shouldVerifyPopoverAction
        self.shouldVerifyPopOutAction = shouldVerifyPopOutAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LaunchAtLogin.applyDefaultIfNeeded()
        LogRetention.runIfDue()
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
        updateStatusTitle()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = currentPopoverSize
        popover.contentViewController = makePopoverContent(selectedPanel: .runway)
        self.popover = popover

        // The Claude/Codex toggles in the popover write UserDefaults; redraw the menu bar when they change.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusTitle()
                // A provider that was just shown has not been read, and a hidden one is no longer polled: refresh now.
                let visible = ProviderVisibility.visibleProviders
                if visible != self.lastVisibleProviders {
                    self.lastVisibleProviders = visible
                    self.refreshLLMUsageInBackground(force: true)
                }
            }
        }

        refreshStatusInBackground()
        refreshLLMUsageInBackground(force: true)
        startRefreshTimer()
        observeLockAndSleep()

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

    /// 15 seconds while the popover or window is showing live stats; otherwise once a minute, which is all
    /// the menu bar countdown and the 60 second activity sample need.
    private var desiredRefreshInterval: TimeInterval { isDetailedUIVisible ? 15 : 60 }

    private func startRefreshTimer() {
        timer?.invalidate()
        let interval = desiredRefreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.desiredRefreshInterval != interval {
                    self.startRefreshTimer()
                }
                self.updateStatusTitle()
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
    }

    /// Nothing is sampled or polled while the screen is locked, the display sleeps, or the Mac sleeps.
    /// One refresh runs on return so the menu bar is current right away.
    private func observeLockAndSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let pauses: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked"))
        ]
        let resumes: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"))
        ]
        for (center, name) in pauses {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pauseRefreshing(name) }
            }
        }
        for (center, name) in resumes {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resumeRefreshing(name) }
            }
        }
    }

    private func pauseRefreshing(_ reason: Notification.Name) {
        pauseReasons.insert(reason.rawValue)
        timer?.invalidate()
        timer = nil
    }

    private func resumeRefreshing(_ reason: Notification.Name) {
        switch reason {
        case NSWorkspace.didWakeNotification: pauseReasons.remove(NSWorkspace.willSleepNotification.rawValue)
        case NSWorkspace.screensDidWakeNotification: pauseReasons.remove(NSWorkspace.screensDidSleepNotification.rawValue)
        default: pauseReasons.remove("com.apple.screenIsLocked")
        }
        // Waking the display at the lock screen is not a return: wait for the unlock.
        guard pauseReasons.isEmpty, timer == nil else { return }
        startRefreshTimer()
        refreshStatusInBackground()
        refreshLLMUsageInBackground(force: true, refreshLocal: false)
    }

    private func startClipboardFlowMonitor() {
        clipboardFlowMonitor.start { [weak self] eventType in
            self?.model.recordClipboardEvent(eventType)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardFlowMonitor.stop()
    }

    private func refreshInBackground() {
        model.refreshInBackground { [weak self] in
            guard let self else { return }
            self.updateStatusTitle()
            self.statusItem?.button?.toolTip = self.statusToolTip()
        }
    }

    private func refreshStatusInBackground() {
        model.refreshStatusInBackground { [weak self] in
            guard let self else { return }
            self.updateStatusTitle()
            self.statusItem?.button?.toolTip = self.statusToolTip()
        }
    }

    private func refreshLLMUsageInBackground(force: Bool = false, refreshLocal: Bool = true) {
        model.refreshLLMUsageInBackground(force: force, refreshLocal: refreshLocal) { [weak self] in
            guard let self else { return }
            self.updateStatusTitle()
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
            if timer != nil, pauseReasons.isEmpty { startRefreshTimer() }
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

    /// Two providers: one column each (percent left 5h/week). One provider: a 5h column and a weekly column,
    /// each with percent left on top and time until reset underneath.
    private func updateStatusTitle() {
        let names = ProviderVisibility.visibleProviders
        guard names.count == 1 else {
            statusTitleView?.setLines(statusTextLines())
            return
        }
        let provider = names[0]
        let limit = model.llmUsage.limits.first { $0.name == provider }
        let stale = limit?.cachedAt == nil ? "" : "~"
        let plan = provider == "Claude" ? model.llmUsage.claudePlanType : model.llmUsage.planType
        // The bottom line switches from time until reset to time until empty only when, at the current
        // burn rate, the window runs out before it resets.
        func column(
            _ label: String, _ window: LLMUsageWindow?, weekly: Bool
        ) -> (top: String, bottom: String, percent: Int?, runningOut: Bool) {
            let percent = window?.remainingPercent
            let top = "\(label) \(percent.map { "\($0)%" } ?? "--")\(stale)"
            guard let window, let emptyAt = forecastEmpty(provider: provider, window: window, plan: plan, weekly: weekly) else {
                return (top, timeLeftLabel(window?.resetAt), percent, false)
            }
            return (top, weekly ? emptyDayLabel(emptyAt) : "out \(shortDuration(until: emptyAt))", percent, true)
        }
        let columns = [
            column("5H", limit?.shortWindow, weekly: false),
            column("WK", limit?.weeklyWindow, weekly: true)
        ]
        statusTitleView?.setColumns(
            top: columns.map(\.top),
            bottom: columns.map(\.bottom),
            percents: columns.map(\.percent),
            runningOut: columns.map(\.runningOut)
        )
    }

    private func forecastEmpty(provider: String, window: LLMUsageWindow, plan: String?, weekly: Bool) -> Date? {
        let history = model.llmQuotaHistory.suffix(weekly ? 1_000 : 120).compactMap { sample -> RunwayForecast.Reading? in
            let percent = weekly ? sample.weeklyRemainingPercent(for: provider) : sample.fiveHourRemainingPercent(for: provider)
            guard let percent else { return nil }
            return RunwayForecast.Reading(
                at: sample.sampledAt,
                remainingPercent: percent,
                resetAt: weekly ? sample.weeklyResetAt(for: provider) : sample.fiveHourResetAt(for: provider),
                plan: sample.plan(for: provider)
            )
        }
        let current = RunwayForecast.Reading(
            at: model.llmUsage.lastUpdated ?? Date(), remainingPercent: window.remainingPercent,
            resetAt: window.resetAt, plan: plan
        )
        let readings = history.filter { $0.at < current.at } + [current]
        return RunwayForecast.emptyAt(readings, minimumSpan: weekly ? 6 * 3_600 : 15 * 60)
    }

    private func shortDuration(until date: Date) -> String {
        let minutes = max(Int(date.timeIntervalSinceNow / 60), 0)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h\(minutes % 60 == 0 ? "" : String(minutes % 60))"
    }

    /// "Thu 2p": the day and hour the week runs out at this pace.
    private func emptyDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let hour = Calendar.current.component(.hour, from: date)
        let suffix = hour < 12 ? "a" : "p"
        return "\(formatter.string(from: date)) \(hour % 12 == 0 ? 12 : hour % 12)\(suffix)"
    }

    private func timeLeftLabel(_ resetAt: Date?) -> String {
        guard let resetAt else { return "--" }
        let minutes = max(Int(ceil(resetAt.timeIntervalSinceNow / 60)), 0)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h\(minutes % 60)m" }
        return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d\(hours % 24)h"
    }

    private func statusTextLines() -> (top: String, bottom: String) {
        func quota(_ name: String) -> String {
            guard let limit = model.llmUsage.limits.first(where: { $0.name == name }) else { return "--/--" }
            let short = limit.shortWindow.map { String($0.remainingPercent) } ?? "--"
            let weekly = limit.weeklyWindow.map { String($0.remainingPercent) } ?? "--"
            return "\(short)/\(weekly)\(limit.cachedAt == nil ? "" : "~")"
        }
        let names = ProviderVisibility.visibleProviders
        return (names.joined(separator: " "), names.map(quota).joined(separator: " "))
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
        window.title = "MaxxBar"
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

    private var columnPercents: [Int?] = []
    private var columnsRunningOut: [Bool] = []

    func setLines(_ lines: (top: String, bottom: String)) {
        topItems = lines.top.split(separator: " ").map(String.init)
        bottomItems = lines.bottom.split(separator: " ").map(String.init)
        columnPercents = bottomItems.map {
            $0.replacingOccurrences(of: "~", with: "").split(separator: "/").compactMap { Int($0) }.min()
        }
        needsDisplay = true
    }

    func setColumns(top: [String], bottom: [String], percents: [Int?], runningOut: [Bool] = []) {
        topItems = top
        bottomItems = bottom
        columnPercents = percents
        columnsRunningOut = runningOut
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
        let runningOut = columnsRunningOut.indices.contains(index) && columnsRunningOut[index]
        guard columnPercents.indices.contains(index), let percent = columnPercents[index] else {
            return runningOut ? amberUsageColor : nil
        }

        if percent < 15 {
            return lowUsageColor
        } else if percent < 25 || runningOut {
            return amberUsageColor
        }

        return nil
    }

    private func shouldUnderlineColumn(at index: Int) -> Bool {
        guard columnPercents.indices.contains(index), let percent = columnPercents[index] else {
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
