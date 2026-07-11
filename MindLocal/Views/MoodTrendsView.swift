import SwiftUI
import SwiftData
import Charts

/// Mood over time, derived from each entry's tone (pleasant +1, mixed 0,
/// unpleasant −1). Averages per day and summarizes the recent balance.
struct MoodTrendsView: View {
    @Query(sort: \Experience.createdAt, order: .reverse) private var experiences: [Experience]
    @Environment(\.dismiss) private var dismiss

    private struct DayMood: Identifiable {
        let date: Date
        let score: Double
        var id: Date { date }
    }

    /// Average mood per calendar day, oldest → newest.
    private var dailyMoods: [DayMood] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: experiences) { cal.startOfDay(for: $0.timelineDate) }
        return groups
            .map { date, items in
                DayMood(date: date, score: items.map(\.tone.score).reduce(0, +) / Double(items.count))
            }
            .sorted { $0.date < $1.date }
    }

    private var counts: (pleasant: Int, mixed: Int, unpleasant: Int) {
        experiences.reduce(into: (0, 0, 0)) { acc, e in
            switch e.tone {
            case .pleasant: acc.0 += 1
            case .mixed: acc.1 += 1
            case .unpleasant: acc.2 += 1
            }
        }
    }

    private var averageScore: Double {
        guard !experiences.isEmpty else { return 0 }
        return experiences.map(\.tone.score).reduce(0, +) / Double(experiences.count)
    }

    private var headline: String {
        switch averageScore {
        case 0.4...:    "Mostly pleasant lately"
        case 0.05..<0.4: "Leaning positive"
        case -0.05..<0.05: "A balanced stretch"
        case -0.4..<(-0.05): "A rough patch"
        default:        "A hard stretch — be kind to yourself"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if experiences.count < 2 {
                    ContentUnavailableView(
                        "Not Enough Yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Add a few journal entries and your mood trend will appear here.")
                    )
                } else {
                    List {
                        Section {
                            Text(headline)
                                .font(.headline)
                            Chart(dailyMoods) { day in
                                LineMark(x: .value("Day", day.date), y: .value("Mood", day.score))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(.tint)
                                PointMark(x: .value("Day", day.date), y: .value("Mood", day.score))
                                    .foregroundStyle(moodColor(day.score))
                            }
                            .chartYScale(domain: -1...1)
                            .chartYAxis {
                                AxisMarks(values: [-1, 0, 1]) { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        switch value.as(Double.self) {
                                        case 1: Text("😊")
                                        case 0: Text("😐")
                                        case -1: Text("☔️")
                                        default: Text("")
                                        }
                                    }
                                }
                            }
                            .frame(height: 200)
                        } header: {
                            Text("Mood over time")
                        }

                        Section("Balance") {
                            balanceRow("Pleasant", counts.pleasant, tone: .pleasant)
                            balanceRow("Mixed", counts.mixed, tone: .mixed)
                            balanceRow("Unpleasant", counts.unpleasant, tone: .unpleasant)
                        }

                        if hasHealthData {
                            Section {
                                healthRow("Pleasant days",
                                          sleep: avgSleep(.pleasant), steps: avgSteps(.pleasant),
                                          tone: .pleasant)
                                healthRow("Unpleasant days",
                                          sleep: avgSleep(.unpleasant), steps: avgSteps(.unpleasant),
                                          tone: .unpleasant)
                                if let insight = sleepInsight {
                                    Label(insight, systemImage: "sparkles")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            } header: {
                                Text("Body & mood")
                            } footer: {
                                Text("From Apple Health. A pattern, not a cause — notice it, don't judge it.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mood Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Health correlation

    private var hasHealthData: Bool {
        HealthService.isConnected && experiences.contains { $0.sleepHours != nil || $0.steps != nil }
    }

    private func avgSleep(_ tone: ExperienceTone) -> Double? {
        average(experiences.filter { $0.tone == tone }.compactMap(\.sleepHours))
    }

    private func avgSteps(_ tone: ExperienceTone) -> Int? {
        average(experiences.filter { $0.tone == tone }.compactMap { $0.steps.map(Double.init) }).map { Int($0) }
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// A gentle one-liner when pleasant days differ from unpleasant days on sleep.
    private var sleepInsight: String? {
        guard let good = avgSleep(.pleasant), let rough = avgSleep(.unpleasant) else { return nil }
        let diff = good - rough
        guard abs(diff) >= 0.5 else { return nil }
        let hrs = String(format: "%.1f", abs(diff))
        return diff > 0
            ? "You tend to sleep about \(hrs)h more on your pleasant days."
            : "Your rougher days tend to follow about \(hrs)h more sleep — worth a look."
    }

    private func healthRow(_ label: String, sleep: Double?, steps: Int?, tone: ExperienceTone) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: tone.symbol).foregroundStyle(tone.tint).font(.subheadline)
            HStack(spacing: 14) {
                if let sleep { metric("bed.double.fill", String(format: "%.1f h sleep", sleep)) }
                if let steps { metric("figure.walk", "\(steps.formatted()) steps") }
                if sleep == nil && steps == nil { Text("No data yet").foregroundStyle(.tertiary) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func metric(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol); Text(text) }
    }

    private func balanceRow(_ label: String, _ count: Int, tone: ExperienceTone) -> some View {
        HStack {
            Label(label, systemImage: tone.symbol).foregroundStyle(tone.tint)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary)
        }
    }

    private func moodColor(_ score: Double) -> Color {
        if score > 0.3 { return .green }
        if score < -0.3 { return .orange }
        return .yellow
    }
}
