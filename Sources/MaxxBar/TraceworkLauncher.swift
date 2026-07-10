import AppKit

@MainActor
enum TraceworkLauncher {
    static func openHub() {
        let hubURL = URL(string: "http://127.0.0.1:8765/")!
        guard let projectURL = projectDirectory() else {
            NSWorkspace.shared.open(hubURL)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["report.py", "--serve-hub"]
        process.currentDirectoryURL = projectURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSWorkspace.shared.open(hubURL)
        }
    }

    private static func projectDirectory() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            ProcessInfo.processInfo.environment["TRACEWORK_PROJECT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) },
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Claude-Codex/Projects/Trajectories", isDirectory: true),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Claude/Projects/Trajectories", isDirectory: true)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("report.py").path) }
    }
}
