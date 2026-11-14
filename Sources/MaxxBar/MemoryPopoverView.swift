import AppKit
import SwiftUI

struct MemoryPopoverView: View {
    @ObservedObject var model: MemoryModel
    var onPopOut: (() -> Void)?
    var onQuit: (() -> Void)?
    var onStartDeepTrace: (() -> Void)?
    var fixedSize: Bool
    var resizableSize: CGSize?
    var onResize: ((CGSize) -> CGSize)?
    @State private var selectedPanel = StatsPanel.runway

    init(
        model: MemoryModel,
        onPopOut: (() -> Void)? = nil,
        onQuit: (() -> Void)? = nil,
        onStartDeepTrace: (() -> Void)? = nil,
        selectedPanel: StatsPanel = .runway,
        fixedSize: Bool = true,
        resizableSize: CGSize? = nil,
        onResize: ((CGSize) -> CGSize)? = nil
    ) {
        self.model = model
        self.onPopOut = onPopOut
        self.onQuit = onQuit
        self.onStartDeepTrace = onStartDeepTrace
        self.fixedSize = fixedSize
        self.resizableSize = resizableSize
        self.onResize = onResize
        _selectedPanel = State(initialValue: selectedPanel)
    }

    var body: some View {
        VStack(spacing: 5) {
            PanelSwitch(selectedPanel: $selectedPanel)

            switch selectedPanel {
            case .memory:
                MemoryPanelView(model: model, onPopOut: onPopOut, onQuit: onQuit)
            case .cpuGPU:
                CPUGPUPanelView(snapshot: model.cpuGPU, sensors: model.sensors, onPopOut: onPopOut, onQuit: onQuit)
            case .llmUsage:
                AIUsagePanelView(
                    aiUsage: model.aiUsage,
                    snapshot: model.llmUsage,
                    quotaHistory: model.llmQuotaHistory,
                    onOpenAIReport: { model.openAIUsageReport() },
                    onStartDeepTrace: onStartDeepTrace,
                    onPopOut: onPopOut,
                    onQuit: onQuit
                )
            case .runway:
                LLMRunwayPanelView(
                    snapshot: model.llmUsage,
                    quotaHistory: model.llmQuotaHistory,
                    onSampleQuota: { model.captureLLMQuotaSample() },
                    onCheckClaudeNow: { model.checkClaudeUsageNow() },
                    isCheckingClaude: model.isCheckingClaude,
                    claudeCheckNote: model.claudeCheckNote,
                    onPopOut: onPopOut,
                    onQuit: onQuit
                )
            case .clipboard:
                ClipboardPanelView(snapshot: model.clipboardDebug)
            }

            ActionBarView(
                onOpenHub: { model.openAIUsageReport() },
                onStartDeepTrace: onStartDeepTrace,
                onPopOut: onPopOut,
                onQuit: onQuit
            )
        }
        .padding(8)
        .frame(
            minWidth: fixedSize ? 306 : 280,
            idealWidth: 306,
            maxWidth: fixedSize ? 306 : .infinity,
            minHeight: fixedSize ? 662 : 480,
            idealHeight: 662,
            maxHeight: fixedSize ? 662 : .infinity,
            alignment: .top
        )
        .background(Color.background)
        .foregroundStyle(.white)
        .overlay(alignment: .bottomTrailing) {
            if let resizableSize, let onResize {
                PopoverResizeHandle(initialSize: resizableSize, onResize: onResize)
                    .padding(3)
            }
        }
    }
}

private struct PopoverResizeHandle: View {
    let initialSize: CGSize
    let onResize: (CGSize) -> CGSize
    @State private var committedSize: CGSize
    @State private var dragStartSize: CGSize?

    init(initialSize: CGSize, onResize: @escaping (CGSize) -> CGSize) {
        self.initialSize = initialSize
        self.onResize = onResize
        _committedSize = State(initialValue: initialSize)
    }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Path { path in
                    let inset = CGFloat(index * 4)
                    path.move(to: CGPoint(x: 5 + inset, y: 17))
                    path.addLine(to: CGPoint(x: 17, y: 5 + inset))
                }
                .stroke(
                    Color.white.opacity(0.34),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartSize ?? committedSize
                    if dragStartSize == nil {
                        dragStartSize = start
                    }
                    _ = onResize(
                        CGSize(
                            width: start.width + value.translation.width,
                            height: start.height + value.translation.height
                        )
                    )
                }
                .onEnded { value in
                    let start = dragStartSize ?? committedSize
                    let resized = CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    )
                    committedSize = onResize(resized)
                    dragStartSize = nil
                }
        )
        .help("Drag to resize. MaxxBar remembers this size.")
        .accessibilityLabel("Resize MaxxBar menu")
    }
}

/// Which providers MaxxBar shows in the menu bar and on the Runway tab. Stored in UserDefaults; both default to on.
enum ProviderVisibility {
    static let showClaudeKey = "showClaudeProvider"
    static let showCodexKey = "showCodexProvider"

    static var showClaude: Bool { UserDefaults.standard.object(forKey: showClaudeKey) as? Bool ?? true }
    static var showCodex: Bool { UserDefaults.standard.object(forKey: showCodexKey) as? Bool ?? true }

    static var visibleProviders: [String] {
        let names = [showClaude ? "Claude" : nil, showCodex ? "Codex" : nil].compactMap { $0 }
        return names.isEmpty ? ["Claude", "Codex"] : names
    }

    /// The provider tracked first-class (drawdown insight and pace): Claude when shown, otherwise Codex.
    static var primaryProvider: String { visibleProviders[0] }
}

struct ProviderVisibilityMenu: View {
    @AppStorage(ProviderVisibility.showClaudeKey) private var showClaude = true
    @AppStorage(ProviderVisibility.showCodexKey) private var showCodex = true

    var body: some View {
        Menu {
            Toggle("Show Claude", isOn: $showClaude)
                .disabled(showClaude && !showCodex)
            Toggle("Show Codex", isOn: $showCodex)
                .disabled(showCodex && !showClaude)
        } label: {
            Image(systemName: "eye")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 23, height: 20)
                .background(Color.panelLift.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show or hide Claude and Codex")
    }
}

enum StatsPanel: String, CaseIterable, Identifiable {
    case runway = "Runway"
    case llmUsage = "Insights"
    case clipboard = "Clipboard"
    case memory = "Memory"
    case cpuGPU = "CPU/GPU"

    var id: String { rawValue }

    static var visibleCases: [StatsPanel] {
        [.runway, .llmUsage, .memory]
    }
}

struct PanelSwitch: View {
    @Binding var selectedPanel: StatsPanel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsPanel.visibleCases) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    Text(panel.rawValue)
                        .font(.system(size: 10.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(selectedPanel == panel ? .white : .white.opacity(0.68))
                        .background(selectedPanel == panel ? Color.panelLift : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
        }
        .padding(3)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
