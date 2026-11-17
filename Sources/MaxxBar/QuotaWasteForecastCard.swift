import SwiftUI

let wasteForecastHelp = """
How much of each Claude window is likely to expire unused, if you keep your usual habits.

Weekly: the week is split into 28 slots (each weekday in four 6 hour parts). Each slot's usual burn is the median of past weeks, from the quota history. Slots with no history use this week's own average pace. Older plans are rescaled (Max 5x counts as 5 Pro allowances), which is an estimate.

5 hour: this window's pace so far, carried to its reset. An idle 5 hour window only costs something when the weekly allowance also expires with credit left.

The target is to finish each week near 90% used, keeping 10% in reserve.
"""

/// "Waste forecast": predicted unused share at the next weekly, per-model weekly and 5 hour resets.
struct QuotaWasteForecastCard: View {
    let snapshot: LLMUsageSnapshot
    let quotaHistory: [LLMQuotaHistorySample]
    let records: [QuotaWindowRecord]

    var body: some View {
        let now = Date()
        let weekly = weeklyForecast(now: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                InstantHelpTitle("WASTE FORECAST", help: wasteForecastHelp, color: .claudeCoral)
                Spacer()
                if let weekly {
                    Text("resets \(weekly.resetAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.52))
                        .monospacedDigit()
                }
            }

            if let weekly {
                headline(weekly)
                WasteForecastBar(forecast: weekly)
                advice(weekly)
            } else {
                Text("Not enough readings this week to forecast yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.58))
            }

            ForEach(modelForecasts(now: now)) { item in
                forecastRow("\(item.model) weekly", item.forecast, suffix: "will expire")
            }
            if let fiveHour = fiveHourForecast(now: now) {
                let weeklyUsedUp = (weekly?.predictedLeft ?? 100) <= QuotaWasteForecast.targetLeftPercent
                forecastRow("This 5h window", fiveHour, suffix: "left in window")
                    .opacity(weeklyUsedUp ? 0.6 : 1)
                    .help(weeklyUsedUp
                        ? "The weekly allowance is on track to be used, so 5 hour leftovers are not lost credit."
                        : "At this window's pace so far.")
            }

            if let weekly {
                footer(weekly)
            }
        }
        .sectionStyle()
    }

    // MARK: Pieces

    private func headline(_ forecast: QuotaWasteForecast.Forecast) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(forecast.predictedLeft)%")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(forecast.predictedLeft > QuotaWasteForecast.targetLeftPercent ? Color.claudeCoral : .white.opacity(0.9))
            Text("of this week likely to expire")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            if let days = forecast.leftoverInTypicalDays, forecast.predictedLeft > 0 {
                Text("≈ \(daysText(days)) of usual use")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .monospacedDigit()
    }

    private func advice(_ forecast: QuotaWasteForecast.Forecast) -> some View {
        let text: String
        if forecast.predictedLeft <= 0 {
            text = "At your usual pace you run out before the reset."
        } else if forecast.spendToTarget == 0 {
            text = "On track to finish near 90% used."
        } else {
            text = "Spend about \(forecast.spendToTarget)% more before the reset to finish near 90% used."
        }
        return Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func forecastRow(_ label: String, _ forecast: QuotaWasteForecast.Forecast, suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text("~\(forecast.predictedLeft)% \(suffix)").foregroundStyle(.white.opacity(0.9))
            Text(forecast.resetAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .foregroundStyle(.white.opacity(0.4))
        }
        .font(.system(size: 12, weight: .medium))
        .monospacedDigit()
    }

    private func footer(_ forecast: QuotaWasteForecast.Forecast) -> some View {
        var parts: [String] = []
        switch forecast.method {
        case .habits:
            let weeks = forecast.weeksOfHistory
            parts.append("From \(weeks) week\(weeks == 1 ? "" : "s") of habits, \(Int((forecast.profileCoverage * 100).rounded()))% of the time left")
        case .thisWindow:
            parts.append("From this week's pace only")
        }
        if let recent = QuotaWasteForecast.recentWeeklyLeftAverage(records) {
            parts.append("last \(recent.count) reset\(recent.count == 1 ? "" : "s") left \(recent.average)% on average")
        }
        return Text(parts.joined(separator: "; "))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.42))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func daysText(_ days: Double) -> String {
        if days < 1 { return "\(max(Int((days * 24).rounded()), 1))h" }
        return days < 10 ? String(format: "%.1f days", days) : "\(Int(days.rounded())) days"
    }

    // MARK: Forecasts

    private var claude: LLMUsageLimit? { snapshot.limits.first { $0.name == "Claude" } }
    private var readingAt: Date { snapshot.lastUpdated ?? Date() }
    private var plan: String? {
        ClaudePlanTimeline.normalized(snapshot.claudePlanType) ?? ClaudePlanTimeline.entry(at: readingAt).plan
    }

    private func weeklyForecast(now: Date) -> QuotaWasteForecast.Forecast? {
        guard let window = claude?.weeklyWindow else { return nil }
        let current = QuotaWasteForecast.Point(at: readingAt, remaining: window.remainingPercent, resetAt: window.resetAt, plan: plan)
        return QuotaWasteForecast.weekly(history: QuotaWasteForecast.weeklyPoints(quotaHistory), current: current, now: now)
    }

    private func fiveHourForecast(now: Date) -> QuotaWasteForecast.Forecast? {
        guard let window = claude?.shortWindow else { return nil }
        let current = QuotaWasteForecast.Point(at: readingAt, remaining: window.remainingPercent, resetAt: window.resetAt, plan: plan)
        return QuotaWasteForecast.fiveHour(history: QuotaWasteForecast.fiveHourPoints(quotaHistory), current: current, now: now)
    }

    private struct ModelForecast: Identifiable {
        let model: String
        let forecast: QuotaWasteForecast.Forecast
        var id: String { model }
    }

    private func modelForecasts(now: Date) -> [ModelForecast] {
        snapshot.limits.compactMap { limit in
            guard limit.name.hasPrefix("Claude "), let window = limit.weeklyWindow else { return nil }
            let model = String(limit.name.dropFirst("Claude ".count))
            let current = QuotaWasteForecast.Point(at: readingAt, remaining: window.remainingPercent, resetAt: window.resetAt, plan: plan)
            let history = QuotaWasteForecast.modelWeeklyPoints(quotaHistory, model: model)
            return QuotaWasteForecast.weekly(history: history, current: current, now: now).map { ModelForecast(model: model, forecast: $0) }
        }
    }
}

/// One bar for the weekly window: used so far, expected use before the reset, and the share expected to expire.
struct WasteForecastBar: View {
    let forecast: QuotaWasteForecast.Forecast

    var body: some View {
        let used = Double(100 - forecast.remainingNow)
        let expected = Double(forecast.expectedUse)
        let left = Double(forecast.predictedLeft)
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 1.5) {
                    segment(used, of: width, color: .white.opacity(0.32))
                    segment(expected, of: width, color: .claudeCoral)
                    segment(left, of: width, color: .claudeCoral.opacity(0.28))
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            HStack(spacing: 10) {
                legend("Used \(Int(used))%", color: .white.opacity(0.32))
                legend("Usual use \(forecast.expectedUse)%", color: .claudeCoral)
                legend("Expires \(forecast.predictedLeft)%", color: .claudeCoral.opacity(0.28))
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func segment(_ percent: Double, of width: CGFloat, color: Color) -> some View {
        if percent > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(width * percent / 100 - 1.5, 2))
        }
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}
