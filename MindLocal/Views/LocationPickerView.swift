import SwiftUI
import MapKit

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
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String, Double, Double) -> Void

    var body: some View {
        NavigationStack {
            List {
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
