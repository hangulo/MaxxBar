import AppKit
import SwiftUI

@MainActor
enum PopoverRenderer {
    static func renderDemo(to url: URL, panel: StatsPanel = .memory) throws {
        let model = MemoryModel(snapshot: .demo, history: MemoryBreakdown.demoHistory())
        model.applyDemoSnapshots()
        let view = MemoryPopoverView(
            model: model,
            onPopOut: {},
            onQuit: {},
            selectedPanel: panel,
            fixedSize: false,
            resizableSize: CGSize(width: 306, height: 662),
            onResize: { $0 }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 306, height: 662)

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
