import Darwin
import AppKit
import Foundation
import MachO
import CryptoKit

struct AIUsageCounter: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let count: Int
}

struct AIWorkflowPath: Identifiable, Equatable {
    var id: String { "\(before)|\(surface)|\(after)|\(useCase)" }
    let before: String
    let surface: String
    let after: String
    let useCase: String
    let count: Int
}

struct AITransferFlow: Identifiable, Equatable {
    var id: String { "\(source)|\(destination)|\(useCase)" }
    let source: String
    let destination: String
    let useCase: String
    let count: Int
    let confidence: String
}

struct AIProviderUsageSummary: Identifiable, Equatable {
    var id: String { provider }
    let provider: String
    let sessionsToday: Int
    let sessionsSevenDays: Int
    let timeTodaySeconds: TimeInterval
    let timeSevenDaysSeconds: TimeInterval
    let averageSessionSeconds: TimeInterval
    let contextConfidence: String
    let topTools: [AIUsageCounter]
    let topBeforeApps: [AIUsageCounter]
    let topAfterApps: [AIUsageCounter]
    let workflowPaths: [AIWorkflowPath]
    let copyEventsToday: Int
    let pasteEventsToday: Int
    let topCopiedFrom: [AIUsageCounter]
    let topPastedInto: [AIUsageCounter]
    let transferFlows: [AITransferFlow]
}

struct MaxxMomentSummary: Identifiable, Equatable {
    var id: String { "\(ts.timeIntervalSince1970)-\(app)-\(note)" }
    let ts: Date
    let sentiment: String
    let app: String
    let surface: String?
    let note: String
    let screenshotPath: String?
}

struct AIUsageSnapshot: Equatable {
    var sampledAt: Date?
    var activeApp: String
    var activeSite: String?
    var activeTool: String?
    var activeSurface: String?
    var activeUseCase: String
    var sessionsToday: Int
    var sessionsSevenDays: Int
    var timeTodaySeconds: TimeInterval
    var timeSevenDaysSeconds: TimeInterval
    var averageSessionSeconds: TimeInterval
    var contextConfidence: String
    var topTools: [AIUsageCounter]
    var topBeforeApps: [AIUsageCounter]
    var topAfterApps: [AIUsageCounter]
    var workflowPaths: [AIWorkflowPath]
    var copyEventsToday: Int
    var pasteEventsToday: Int
    var topCopiedFrom: [AIUsageCounter]
    var topPastedInto: [AIUsageCounter]
    var transferFlows: [AITransferFlow]
    var momentsToday: Int
    var lastMomentAt: Date?
    var recentMoments: [MaxxMomentSummary]
    var lastError: String?
    var providerSummaries: [AIProviderUsageSummary] = []

    var insightEventsToday: Int {
        sessionsToday + copyEventsToday + pasteEventsToday
    }
}
