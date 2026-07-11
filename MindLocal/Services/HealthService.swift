import Foundation
import HealthKit

/// A day's health context, read from HealthKit. Any field may be nil if the data
/// isn't present or access wasn't granted.
struct DayHealth: Equatable {
    var sleepHours: Double?
    var steps: Int?
    var workoutMinutes: Double?
    var workoutCount: Int?
}

/// Reads sleep, steps, and workouts from HealthKit to add gentle physical
/// context to journal entries and mood trends. Read-only; data stays on device.
///
/// HealthKit deliberately hides read-authorization status, so we track whether
/// the user has connected in `UserDefaults` under `healthConnected`.
@MainActor
final class HealthService {
    static let shared = HealthService()
    static let connectedKey = "healthConnected"

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    static var isConnected: Bool { UserDefaults.standard.bool(forKey: connectedKey) }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }

    /// Prompts for read access. Returns true once the user has responded (HealthKit
    /// doesn't reveal whether they granted, only that they were asked).
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            UserDefaults.standard.set(true, forKey: Self.connectedKey)
            return true
        } catch {
            return false
        }
    }

    /// Fills in the entry's health context for its day. No-op if unavailable or
    /// not connected.
    func enrich(_ experience: Experience) async {
        guard Self.isAvailable, Self.isConnected else { return }
        let summary = await summary(for: experience.timelineDate)
        experience.sleepHours = summary.sleepHours
        experience.steps = summary.steps
        experience.workoutMinutes = summary.workoutMinutes
        experience.workoutCount = summary.workoutCount
    }

    func summary(for date: Date) async -> DayHealth {
        guard Self.isAvailable else { return DayHealth() }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date

        async let steps = stepCount(start: start, end: end)
        async let sleep = sleepHours(start: start, end: end)
        async let workout = workouts(start: start, end: end)
        let (s, sl, w) = await (steps, sleep, workout)
        return DayHealth(sleepHours: sl, steps: s, workoutMinutes: w.minutes, workoutCount: w.count)
    }

    // MARK: - Queries

    private func stepCount(start: Date, end: Date) async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: .count())
                cont.resume(returning: count.map { Int($0) })
            }
            store.execute(query)
        }
    }

    /// Sleep that ended during this calendar day (i.e. the prior night), summed
    /// over the "asleep" stages.
    private func sleepHours(start: Date, end: Date) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let samples: [HKCategorySample]? = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, results, _ in
                cont.resume(returning: results as? [HKCategorySample])
            }
            store.execute(query)
        }
        guard let samples, !samples.isEmpty else { return nil }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let seconds = samples
            .filter { asleep.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return seconds > 0 ? seconds / 3600 : nil
    }

    private func workouts(start: Date, end: Date) async -> (minutes: Double?, count: Int?) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKWorkout]? = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, results, _ in
                cont.resume(returning: results as? [HKWorkout])
            }
            store.execute(query)
        }
        guard let samples, !samples.isEmpty else { return (nil, nil) }
        let minutes = samples.reduce(0.0) { $0 + $1.duration } / 60
        return (minutes, samples.count)
    }
}
