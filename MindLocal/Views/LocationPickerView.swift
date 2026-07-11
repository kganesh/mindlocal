import SwiftUI
import MapKit
import CoreLocation

/// Gets a single current-location fix (asking permission if needed) and reverse
/// geocodes it to a readable place name.
@MainActor
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// One-shot location. Returns nil if denied or it can't get a fix.
    func currentLocation() async -> CLLocation? {
        await withCheckedContinuation { cont in
            continuation = cont
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .notDetermined: manager.requestWhenInUseAuthorization()
            default: finish(nil)
            }
        }
    }

    func placeName(for location: CLLocation) async -> String {
        let fallback = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return fallback }
        return item.name ?? item.address?.shortAddress ?? item.address?.fullAddress ?? fallback
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if continuation != nil { manager.requestLocation() }
            case .denied, .restricted:
                finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }
}

/// Search-as-you-type place autocomplete (MKLocalSearchCompleter). Resolving a
/// pick yields a name + coordinates.
@Observable
@MainActor
final class LocationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> (name: String, latitude: Double, longitude: Double)? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coord = item.location.coordinate
        let name = item.name ?? completion.title
        return (name, coord.latitude, coord.longitude)
    }
}

/// A place picker sheet. Calls `onSelect(name, lat, long)` on selection.
struct LocationPickerView: View {
    @State private var completer = LocationSearchCompleter()
    @State private var locationProvider = CurrentLocationProvider()
    @State private var locating = false
    @State private var locationDenied = false
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String, Double, Double) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: useCurrentLocation) {
                        HStack {
                            Label("Use current location", systemImage: "location.fill")
                            Spacer()
                            if locating { ProgressView() }
                        }
                    }
                    .disabled(locating)
                }

                if completer.query.isEmpty {
                    ContentUnavailableView("Search a Place", systemImage: "mappin.and.ellipse",
                                           description: Text("Type a place, address, or city."))
                } else {
                    ForEach(completer.results.indices, id: \.self) { index in
                        let result = completer.results[index]
                        Button {
                            Task {
                                if let place = await completer.resolve(result) {
                                    onSelect(place.name, place.latitude, place.longitude)
                                }
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $completer.query, prompt: "Search for a place")
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Location Off", isPresented: $locationDenied) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Enable location in Settings → MindLocal → Location, or search for a place instead.")
            }
        }
    }

    private func useCurrentLocation() {
        Task {
            locating = true
            defer { locating = false }
            guard let location = await locationProvider.currentLocation() else {
                locationDenied = true
                return
            }
            let name = await locationProvider.placeName(for: location)
            onSelect(name, location.coordinate.latitude, location.coordinate.longitude)
            dismiss()
        }
    }
}

/// A small non-interactive map preview centered on a coordinate.
struct LocationMapPreview: View {
    let latitude: Double
    let longitude: Double
    let name: String

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Marker(name, coordinate: coordinate)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}
