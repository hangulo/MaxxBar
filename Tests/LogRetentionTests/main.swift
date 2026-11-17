import Foundation

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let iso = ISO8601DateFormatter()
let now = Date()
func line(_ daysAgo: Double, _ id: Int) -> String {
    "{\"id\":\(id),\"ts\":\"\(iso.string(from: now.addingTimeInterval(-daysAgo * 86_400)))\"}\n"
}

// 40 old lines, then 5 recent ones; enough lines to cross a 1 MB chunk.
let padding = String(repeating: "x", count: 30_000)
var text = ""
for id in 0..<40 { text += line(45 - Double(id) * 0.1, id).replacingOccurrences(of: "}\n", with: ",\"p\":\"\(padding)\"}\n") }
for id in 40..<45 { text += line(2, id) }
let url = directory.appendingPathComponent("ai-activity.jsonl")
try text.write(to: url, atomically: true, encoding: .utf8)

let archive = directory.appendingPathComponent("archive")
LogRetention.trim(url, timeKey: "ts", cutoff: now.addingTimeInterval(-30 * 86_400), archiveDirectory: archive)
let kept = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
let moved = try String(contentsOf: archive.appendingPathComponent("ai-activity.jsonl"), encoding: .utf8).split(separator: "\n")
assert(kept.count == 5 && kept.first!.contains("\"id\":40"), "kept \(kept.count)")
assert(moved.count == 40 && moved.last!.contains("\"id\":39"), "moved \(moved.count)")

// Nothing old: the file is left alone and no archive line is added.
LogRetention.trim(url, timeKey: "ts", cutoff: now.addingTimeInterval(-30 * 86_400), archiveDirectory: archive)
assert((try! String(contentsOf: url, encoding: .utf8)).split(separator: "\n").count == 5)
assert((try! String(contentsOf: archive.appendingPathComponent("ai-activity.jsonl"), encoding: .utf8)).split(separator: "\n").count == 40)

// A second key name (the 5h log uses recordedAt), with fractional seconds.
let fractional = ISO8601DateFormatter()
fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let fiveHour = directory.appendingPathComponent("llm-5h-usage-windows.jsonl")
try ("{\"recordedAt\":\"\(fractional.string(from: now.addingTimeInterval(-40 * 86_400)))\"}\n"
    + "{\"recordedAt\":\"\(fractional.string(from: now))\"}\n").write(to: fiveHour, atomically: true, encoding: .utf8)
LogRetention.trim(fiveHour, timeKey: "recordedAt", cutoff: now.addingTimeInterval(-30 * 86_400), archiveDirectory: archive)
assert((try! String(contentsOf: fiveHour, encoding: .utf8)).split(separator: "\n").count == 1)
print("Log retention checks passed")
