import AppKit
import SwiftUI

struct MemoryPanelView: View {
    @ObservedObject var model: MemoryModel
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            MemoryRunwayHeroView(snapshot: model.snapshot)

            BreakdownView(snapshot: model.snapshot)

            ProcessesView(groupedProcesses: model.snapshot.processes, processRows: model.snapshot.processRows)

            SwapView(snapshot: model.snapshot)

            CompactSensorsCard(snapshot: model.sensors)

        }
    }
}

struct CompactSensorsCard: View {
    let snapshot: SensorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SENSORS").sectionTitle()
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium").foregroundStyle(Color.accentBlue)
                    Text(snapshot.cpuTemperature == nil ? "Battery" : "CPU")
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer(minLength: 0)
                    Text(temperature(snapshot.cpuTemperature ?? snapshot.batteryTemperature))
                        .monospacedDigit()
                }
                if let gpu = snapshot.gpuTemperature {
                    HStack(spacing: 5) {
                        Text("GPU").foregroundStyle(.white.opacity(0.58))
                        Text(temperature(gpu)).monospacedDigit()
                    }
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "fanblades").foregroundStyle(Color.accentBlue)
                Text("Fans").foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 4)
                Text(fanSpeeds)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .font(.system(size: 12, weight: .regular))
        .sectionStyle()
        .help("Live local temperatures and fan speeds in RPM. Separate fan readings follow fan order. A dash means the reading is unavailable.")
    }

    private var fanSpeeds: String {
        guard !snapshot.fanReadings.isEmpty else { return rpm(snapshot.fanRPM) }
        return snapshot.fanReadings.map { $0.rpm.formatted() }.joined(separator: " / ") + " rpm"
    }
}

struct SensorsPanelView: View {
    let snapshot: SensorSnapshot
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 16) {
                ValueRingView(title: "CPU", value: temperature(snapshot.cpuTemperature), percent: temperaturePercent(snapshot.cpuTemperature))
                ValueRingView(title: "GPU", value: temperature(snapshot.gpuTemperature), percent: temperaturePercent(snapshot.gpuTemperature))
                ValueRingView(title: "FANS", value: fanStatus(snapshot), percent: fanPercent(snapshot))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            MetricCard(title: "TEMPERATURE", rows: temperatureRows)

        }
    }

    private var temperatureRows: [MetricRow] {
        let readings = snapshot.temperatureReadings
        guard !readings.isEmpty else {
            return [MetricRow(label: "CPU / GPU / Fans", value: "Requires helper")]
        }

        return readings.map { MetricRow(label: $0.label, value: temperature($0.celsius)) }
    }
}

struct CPUGPUPanelView: View {
    let snapshot: CPUGPUSnapshot
    let sensors: SensorSnapshot
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    @State private var processScale = CPUProcessScale.systemShare

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 7) {
                ThermalStateCard(sensors: sensors)
                SensorSummaryRingsView(snapshot: sensors)
                CPUHistoryCard(snapshot: snapshot)
                CoreRingsView(snapshot: snapshot)
                GPUCard(snapshot: snapshot)
                CPUProcessesView(processes: snapshot.processes, scale: $processScale)
                MetricCard(title: "TEMPERATURE", rows: temperatureRows + fanRows)
                MetricCard(title: "UPTIME", rows: [MetricRow(label: "", value: snapshot.uptime)])
            }
        }
    }

    private var fanRows: [MetricRow] {
        sensors.fanReadings.map { MetricRow(label: $0.label, value: "\($0.rpm.formatted()) rpm") }
    }

    private var temperatureRows: [MetricRow] {
        guard !sensors.temperatureReadings.isEmpty else {
            return [MetricRow(label: "CPU / GPU / Fans", value: "Requires helper")]
        }

        return sensors.temperatureReadings.map { reading in
            MetricRow(label: reading.label, value: temperature(reading.celsius))
        }
    }
}

/// macOS's own throttling signal, plus power draw: the first thing to check when a local model slows down.
struct ThermalStateCard: View {
    let sensors: SensorSnapshot

    var body: some View {
        let state = ProcessInfo.processInfo.thermalState
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("THERMAL")
                    .sectionTitle()
                Spacer()
                Text(label(state))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(color(state))
            }
            Text(detail(state))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
            if sensors.power != nil || sensors.batteryTemperature != nil {
                HStack {
                    Text("Power draw")
                    Spacer()
                    Text(watts(sensors.power)).monospacedDigit()
                }
                .font(.system(size: 12, weight: .regular))
            }
        }
        .sectionStyle()
        .help("Thermal state comes from macOS. Fair means fans are working; Serious and Critical mean the Mac is slowing itself down to cool off.")
    }

    private func label(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Throttling"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func detail(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Running at full speed."
        case .fair: return "Fans are working; no slowdown yet."
        case .serious: return "macOS is slowing the CPU and GPU to cool down."
        case .critical: return "Heavy throttling. Expect much slower local models."
        @unknown default: return ""
        }
    }

    private func color(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .white
        case .fair: return .compressedYellow
        default: return .wiredPink
        }
    }
}

struct SensorSummaryRingsView: View {
    let snapshot: SensorSnapshot

    var body: some View {
        HStack(spacing: 16) {
            ValueRingView(title: "CPU", value: temperature(snapshot.cpuTemperature), percent: temperaturePercent(snapshot.cpuTemperature))
            ValueRingView(title: "GPU", value: temperature(snapshot.gpuTemperature), percent: temperaturePercent(snapshot.gpuTemperature))
            ValueRingView(title: "FANS", value: fanStatus(snapshot), percent: fanPercent(snapshot))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MemoryRunwayHeroView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(spacing: 10) {
            MemoryRunwayLane(
                title: "PRESSURE",
                value: "\(snapshot.pressurePercent)%",
                detail: pressureDetail,
                percent: snapshot.pressurePercent,
                color: .accentBlue,
                markers: [50, 80]
            )

            MemoryRunwayLane(
                title: "MEMORY",
                value: "\(snapshot.usedPercent)%",
                detail: "\(ByteFormat.memory(snapshot.breakdown.app + snapshot.breakdown.wired + snapshot.breakdown.compressed)) used",
                percent: snapshot.usedPercent,
                color: .accentBlue,
                segments: memorySegments
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var pressureDetail: String {
        switch snapshot.pressurePercent {
        case 0..<35:
            return "Low load"
        case 35..<70:
            return "Active load"
        default:
            return "High load"
        }
    }

    private var memorySegments: [MemoryRunwaySegment] {
        let breakdown = snapshot.breakdown
        let total = max(Double(breakdown.total), 1)
        return [
            MemoryRunwaySegment(label: "App", value: Double(breakdown.app) / total, color: .accentBlue),
            MemoryRunwaySegment(label: "Wired", value: Double(breakdown.wired) / total, color: .wiredPink),
            MemoryRunwaySegment(label: "Compressed", value: Double(breakdown.compressed) / total, color: .compressedYellow),
            MemoryRunwaySegment(label: "Free", value: Double(breakdown.free) / total, color: .freeGray)
        ]
    }
}

struct MemoryRunwaySegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct MemoryRunwayLane: View {
    let title: String
    let value: String
    let detail: String
    let percent: Int
    let color: Color
    var markers: [Int] = []
    var segments: [MemoryRunwaySegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(value)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .frame(width: 74, alignment: .leading)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 6)
                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(color.opacity(0.9))
                    .lineLimit(1)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    if segments.isEmpty {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.freeGray.opacity(0.22))
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(color.opacity(0.9))
                            .frame(width: proxy.size.width * clampedRatio)
                    } else {
                        segmentedTrack(width: proxy.size.width)
                    }

                    ForEach(markers, id: \.self) { marker in
                        let x = proxy.size.width * CGFloat(marker) / 100
                        Rectangle()
                            .fill(Color.background.opacity(0.58))
                            .frame(width: 1, height: 12)
                            .position(x: x, y: 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 12)

            if !segments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(segments.prefix(3)) { segment in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(segment.color)
                                .frame(width: 5, height: 5)
                            Text(segment.label)
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                    }
                }
            }
        }
    }

    private var clampedRatio: CGFloat {
        CGFloat(min(max(Double(percent) / 100, 0), 1))
    }

    private func segmentedTrack(width: CGFloat) -> some View {
        // A small background-colored gap between segments keeps bright colors from
        // visually swallowing darker neighbors at their shared edge.
        let gap: CGFloat = 2
        let visible = segments.filter { $0.value > 0 }
        let fillWidth = max(width - gap * CGFloat(max(visible.count - 1, 0)), 0)
        return HStack(spacing: gap) {
            ForEach(visible) { segment in
                Rectangle()
                    .fill(segment.color.opacity(segment.label == "Free" ? 0.48 : 0.88))
                    .frame(width: fillWidth * CGFloat(segment.value))
            }
        }
        .frame(width: width, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct ValueRingView: View {
    let title: String
    let value: String
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.freeGray.opacity(0.72), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
                .stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(value)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 78, height: 78)
    }
}

struct MetricRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct MetricCard: View {
    let title: String
    let rows: [MetricRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .sectionTitle()

            ForEach(rows) { row in
                HStack {
                    if !row.label.isEmpty {
                        Text(row.label)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer()
                    Text(row.value)
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .sectionStyle()
    }
}

struct CPUHistoryCard: View {
    let snapshot: CPUGPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("CPU")
                    .sectionTitle()
                Spacer()
                Text(cpuHeader)
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<48, id: \.self) { index in
                    VStack(spacing: 0) {
                        Color.wiredPink.frame(height: CGFloat(8 + (index % 5)))
                        Color.accentBlue.frame(height: CGFloat(14 + (index % 4)))
                    }
                    .frame(width: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 9) {
                LegendInline(color: .accentBlue, label: "User", value: "\(snapshot.cpuUserPercent)%")
                LegendInline(color: .wiredPink, label: "System", value: "\(snapshot.cpuSystemPercent)%")
            }
        }
        .sectionStyle()
    }

    private var cpuHeader: String {
        if let cpuGHz = snapshot.cpuGHz, let cpuTemperature = snapshot.cpuTemperature {
            return String(format: "%.2f GHz, %@", cpuGHz, temperature(cpuTemperature))
        }
        if let cpuGHz = snapshot.cpuGHz {
            return String(format: "%.2f GHz", cpuGHz)
        }
        if let cpuTemperature = snapshot.cpuTemperature {
            return temperature(cpuTemperature)
        }
        return "Public CPU"
    }
}

struct CoreRingsView: View {
    let snapshot: CPUGPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(coreRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { core in
                            MiniRing(percent: Double(core.percent), color: core.color)
                                .help("\(core.label) \(core.displayIndex): \(core.percent)%")
                        }
                    }
                }
            }
            LegendRow(
                color: .wiredPink,
                label: "Efficiency Cores",
                value: "\(snapshot.efficiencyPercent)%",
                help: "Average active load across efficiency cores, from per-core host CPU ticks."
            )
            LegendRow(
                color: .accentBlue,
                label: "Performance Cores",
                value: "\(snapshot.performancePercent)%",
                help: "Average active load across performance cores, from per-core host CPU ticks."
            )
        }
        .sectionStyle()
    }

    private var coreRows: [[CPUCoreLoad]] {
        let loads = snapshot.coreLoads
        guard !loads.isEmpty else { return [] }
        return stride(from: 0, to: loads.count, by: 7).map { start in
            Array(loads[start..<min(start + 7, loads.count)])
        }
    }
}

struct MiniRing: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.freeGray.opacity(0.72), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
                .stroke(color, lineWidth: 4)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 19, height: 19)
    }
}

private extension CPUCoreLoad {
    var color: Color {
        switch kind {
        case .efficiency:
            return .wiredPink
        case .performance:
            return .accentBlue
        }
    }

    var label: String {
        switch kind {
        case .efficiency:
            return "Efficiency core"
        case .performance:
            return "Performance core"
        }
    }

    var displayIndex: Int { index + 1 }
}

enum CPUProcessScale: String, CaseIterable, Identifiable {
    case systemShare = "System"
    case activityMonitor = "Raw"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .systemShare:
            return "Share of the whole machine. Raw per-process CPU is divided by logical CPU count."
        case .activityMonitor:
            return "Activity Monitor style. A process can exceed 100% because macOS reports CPU per core before grouping helper processes."
        }
    }
}

struct CPUProcessesView: View {
    let processes: [CPUProcess]
    @Binding var scale: CPUProcessScale

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("PROCESSES")
                    .sectionTitle()
                Spacer()
                CPUScaleSwitch(scale: $scale)
                    .help(scale.help)
            }
            ForEach(processes.prefix(3)) { process in
                HStack(spacing: 8) {
                    CPUProcessIcon(process: process)
                    Text(process.name)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", displayPercent(for: process)))
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .sectionStyle()
    }

    private func displayPercent(for process: CPUProcess) -> Double {
        switch scale {
        case .systemShare:
            return process.cpuPercent
        case .activityMonitor:
            return process.rawCPUPercent
        }
    }
}

struct CPUScaleSwitch: View {
    @Binding var scale: CPUProcessScale

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CPUProcessScale.allCases) { option in
                Button {
                    scale = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(scale == option ? .white : .white.opacity(0.62))
                        .background(scale == option ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.background.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct GPUCard: View {
    let snapshot: CPUGPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GPU")
                    .sectionTitle()
                Spacer()
                Text(snapshot.fps.map { "\($0) FPS" } ?? (snapshot.gpuPercent.map { "\($0)% busy" } ?? "Unavailable"))
                    .font(.system(size: 13.5, weight: .semibold))
            }
            HStack {
                ValueRingView(title: "GPU", value: percent(snapshot.gpuPercent), percent: Double(snapshot.gpuPercent ?? 0))
                ValueRingView(title: "MEM", value: percent(snapshot.gpuMemoryPercent), percent: Double(snapshot.gpuMemoryPercent ?? 0))
                ValueRingView(title: "TMP", value: temperature(snapshot.gpuTemperature), percent: temperaturePercent(snapshot.gpuTemperature))
            }
        }
        .sectionStyle()
    }
}

struct LegendInline: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .regular))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct BreakdownView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(spacing: 7) {
            LegendRow(
                color: .accentBlue,
                label: "App",
                value: ByteFormat.memory(snapshot.breakdown.app),
                help: "App memory: memory used by apps and anonymous process pages. Calculated as physical memory minus available cache/free, wired memory, and compressed memory."
            )
            LegendRow(
                color: .wiredPink,
                label: "Wired",
                value: ByteFormat.memory(snapshot.breakdown.wired),
                help: "Wired memory: kernel and driver memory that must stay in RAM and cannot be compressed or paged out."
            )
            LegendRow(
                color: .compressedYellow,
                label: "Compressed",
                value: ByteFormat.memory(snapshot.breakdown.compressed),
                help: "Compressed memory: app memory macOS compressed in RAM instead of writing it to swap."
            )
            LegendRow(
                color: .freeGray,
                label: "Free",
                value: ByteFormat.memory(snapshot.breakdown.free),
                help: "Free/available memory: free, speculative, and file-backed cache pages that macOS can quickly reuse for apps."
            )
        }
        .sectionStyle()
    }
}

struct ProcessesView: View {
    let groupedProcesses: [ProcessMemory]
    let processRows: [ProcessMemory]
    @State private var mode = ProcessListMode.apps

    private var processes: [ProcessMemory] {
        switch mode {
        case .apps:
            return groupedProcesses
        case .rows:
            return processRows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("PROCESSES")
                    .sectionTitle()
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(ProcessListMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 94)
                .controlSize(.mini)
                .help(mode.help)
            }

            ForEach(processes) { process in
                HStack(spacing: 8) {
                    ProcessIcon(process: process)
                    Text(process.name)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(ByteFormat.memory(process.bytes))
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.86))
                        .monospacedDigit()
                }
            }
        }
        .sectionStyle()
    }
}

enum ProcessListMode: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case rows = "Rows"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .apps:
            return "Group helper processes by their owning app bundle."
        case .rows:
            return "Show individual process rows using the Activity Monitor-like MEM value."
        }
    }
}

struct SwapView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("SWAP")
                    .sectionTitle()
                Spacer()
                Text("\(ByteFormat.memory(snapshot.swapUsed)) of \(ByteFormat.memory(snapshot.swapTotal))")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.86))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.freeGray.opacity(0.55), lineWidth: 1)
                        .background(Color.clear)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentBlue)
                        .frame(width: proxy.size.width * swapRatio)
                }
            }
            .frame(height: 10)
        }
        .sectionStyle()
    }

    private var swapRatio: CGFloat {
        guard snapshot.swapTotal > 0 else { return 0 }
        return min(CGFloat(Double(snapshot.swapUsed) / Double(snapshot.swapTotal)), 1)
    }
}

struct ActionBarView: View {
    var onOpenHub: (() -> Void)?
    var onStartDeepTrace: (() -> Void)?
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            VersionIndicatorView()

            Spacer()

            ProviderVisibilityMenu()

            if let onOpenHub {
                IconActionButton(systemName: "rectangle.3.group", help: "Open MaxxBar Hub", action: onOpenHub)
            }

            if let onStartDeepTrace {
                IconActionButton(systemName: "record.circle", help: "Start Deep Trace", action: onStartDeepTrace)
            }

            if let onPopOut {
                IconActionButton(systemName: "rectangle.on.rectangle", help: "Open as window", action: onPopOut)
            }

            IconActionButton(systemName: "arrow.clockwise", help: "Relaunch app", action: relaunchCurrentApp)

            if let onQuit {
                IconActionButton(systemName: "power", help: "Quit app", action: onQuit)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct VersionIndicatorView: View {
    private var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let components = version.split(separator: ".")
        let compact = components.prefix(2).joined(separator: ".")
        return "v\(compact.isEmpty ? version : compact)"
    }

    private var fullLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.flatMap { $0.isEmpty ? nil : "MaxxBar v\(version) · \($0)" } ?? "MaxxBar v\(version)"
    }

    var body: some View {
        ImmediateHelpPopover(help: fullLabel) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.44))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

@MainActor
private func relaunchCurrentApp() {
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else {
        NSApp.terminate(nil)
        return
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-n", bundleURL.path]
    try? task.run()
    NSApp.terminate(nil)
}

struct IconActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        ImmediateHelpPopover(help: help) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 23, height: 20)
                    .background(Color.panelLift.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String
    let help: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 11, height: 11)
            Text(label)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            Text(value)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.white.opacity(0.86))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .help(help)
    }
}

struct ProcessIcon: View {
    let process: ProcessMemory

    var body: some View {
        if let image = icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.panelLift)
                .overlay {
                    Text(String(process.name.prefix(1)))
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 17, height: 17)
        }
    }

    private var icon: NSImage? {
        if let appPath = process.appPath {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        if let appIcon = NSRunningApplication(processIdentifier: process.pid)?.icon {
            return appIcon
        }

        guard process.path.hasPrefix("/") else { return nil }
        return NSWorkspace.shared.icon(forFile: process.path)
    }
}

struct CPUProcessIcon: View {
    let process: CPUProcess

    var body: some View {
        if let image = icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.panelLift)
                .overlay {
                    Text(String(process.name.prefix(1)))
                        .font(.system(size: 9, weight: .semibold))
                }
                .frame(width: 17, height: 17)
        }
    }

    private var icon: NSImage? {
        if let appPath = process.appPath {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        guard process.path.hasPrefix("/") else { return nil }
        return NSWorkspace.shared.icon(forFile: process.path)
    }
}
