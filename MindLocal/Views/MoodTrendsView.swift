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
