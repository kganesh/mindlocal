import Foundation
import CoreLocation
import MapKit
import WeatherKit

/// A compact, model-friendly weather summary for a location on a day.
struct WeatherSummary: Sendable {
    let condition: String
    let highC: Double
    let lowC: Double
    let precipitationChance: Double   // 0...1

    /// One-line, locale-formatted summary for prompts and UI.
    var line: String {
        let high = Measurement(value: highC, unit: UnitTemperature.celsius)
        let low = Measurement(value: lowC, unit: UnitTemperature.celsius)
        let temps = "\(format(low))–\(format(high))"
        let rain = "\(Int((precipitationChance * 100).rounded()))% chance of precipitation"
        return "\(condition), \(temps), \(rain)"
    }

    private func format(_ measurement: Measurement<UnitTemperature>) -> String {
        measurement.formatted(.measurement(width: .narrow, usage: .weather))
    }
}

protocol WeatherProviding: Sendable {
    /// Forecast for `location` on `date`, or nil if it can't be resolved (bad
    /// location, date outside the forecast window, or WeatherKit unavailable).
    func forecast(location: String, date: Date) async -> WeatherSummary?
}

/// Weather via Apple WeatherKit. Requires the WeatherKit capability on the App
/// ID (developer portal) — the only off-device call in the app.
final class WeatherKitService: WeatherProviding {
    func forecast(location: String, date: Date) async -> WeatherSummary? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Geocode the free-text location to coordinates (MapKit, iOS 26+).
        guard let request = MKGeocodingRequest(addressString: trimmed),
              let mapItem = try? await request.mapItems.first else { return nil }
        let location = mapItem.location

        do {
            let daily = try await WeatherService.shared.weather(for: location, including: .daily)
            guard let day = daily.forecast.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: date)
            }) else { return nil }

            return WeatherSummary(
                condition: day.condition.description,
                highC: day.highTemperature.converted(to: .celsius).value,
                lowC: day.lowTemperature.converted(to: .celsius).value,
                precipitationChance: day.precipitationChance
            )
        } catch {
            return nil
        }
    }
}

/// Deterministic mock for previews and tests (no network).
final class MockWeatherService: WeatherProviding {
    func forecast(location: String, date: Date) async -> WeatherSummary? {
        WeatherSummary(condition: "Light Rain", highC: 18, lowC: 11, precipitationChance: 0.7)
    }
}
