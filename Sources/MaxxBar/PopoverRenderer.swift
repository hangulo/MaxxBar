import AppKit
import SwiftUI

@MainActor
enum PopoverRenderer {
    static func renderDemo(to url: URL, panel: StatsPanel = .memory) throws {
        // MAXXBAR_RENDER_HEIGHT renders a taller popover, for screenshots of cards below the fold.
        let height = ProcessInfo.processInfo.environment["MAXXBAR_RENDER_HEIGHT"].flatMap(Double.init) ?? 662
        let model = MemoryModel(snapshot: .demo, history: MemoryBreakdown.demoHistory())
        model.applyDemoSnapshots()
        let view = MemoryPopoverView(
            model: model,
            onPopOut: {},
            onQuit: {},
            selectedPanel: panel,
            fixedSize: false,
            resizableSize: CGSize(width: 306, height: height),
            onResize: { $0 }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 306, height: height)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw RenderError.bitmapCreationFailed
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

enum RenderError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
}
