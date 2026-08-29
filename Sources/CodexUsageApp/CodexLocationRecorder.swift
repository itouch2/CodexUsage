@preconcurrency import CoreLocation
import CodexUsageCore
import Foundation

@MainActor
final class CodexLocationRecorder: NSObject, ObservableObject {
    static let shared = CodexLocationRecorder()

    @Published private(set) var samples: [CodexLocationSample]
    @Published private(set) var isRecording: Bool
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastErrorDescription: String?

    private let defaults: UserDefaults
    private let locationManager: CLLocationManager
    private let geocoder: CLGeocoder
    private var trail: CodexLocationTrail

    private static let samplesStorageKey =
        "codexUsage.locationSamples"
    private static let recordingEnabledKey =
        "codexUsage.locationRecordingEnabled"

    init(
        defaults: UserDefaults = .standard,
        locationManager: CLLocationManager = CLLocationManager(),
        geocoder: CLGeocoder = CLGeocoder()
    ) {
        self.defaults = defaults
        self.locationManager = locationManager
        self.geocoder = geocoder
        let decodedSamples = defaults.data(forKey: Self.samplesStorageKey).flatMap {
            try? JSONDecoder().decode([CodexLocationSample].self, from: $0)
        } ?? []
        let trail = CodexLocationTrail(samples: decodedSamples)
        self.trail = trail
        self.samples = trail.samples
        self.isRecording = defaults.bool(forKey: Self.recordingEnabledKey)
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    var latestSample: CodexLocationSample? {
        samples.first
    }

    var statusTitle: String {
        guard isRecording else { return "Location recording is off" }
        switch authorizationStatus {
        case .notDetermined:
            return "Waiting for location permission"
        case .restricted, .denied:
            return "Location access is unavailable"
        case .authorizedAlways:
            return latestSample?.displayPlace ?? "Estimating this Mac's location…"
        @unknown default:
            return "Location access is unavailable"
        }
    }

    func setRecordingEnabled(_ enabled: Bool) {
        isRecording = enabled
        defaults.set(enabled, forKey: Self.recordingEnabledKey)
        lastErrorDescription = nil

        if enabled {
            resumeIfEnabled(requestAuthorization: true)
        } else {
            locationManager.stopUpdatingLocation()
            geocoder.cancelGeocode()
        }
    }

    func resumeIfEnabled(requestAuthorization: Bool = false) {
        guard isRecording else { return }
        authorizationStatus = locationManager.authorizationStatus
        guard CLLocationManager.locationServicesEnabled() else {
            lastErrorDescription = "Location Services are turned off in System Settings."
            return
        }

        switch authorizationStatus {
        case .notDetermined where requestAuthorization:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .restricted, .denied:
            lastErrorDescription =
                "Allow Codex Usage in Privacy & Security › Location Services."
        default:
            break
        }
    }

    func clearHistory() {
        trail = CodexLocationTrail()
        samples = []
        defaults.removeObject(forKey: Self.samplesStorageKey)
    }

    private func accept(_ location: CLLocation) {
        guard isRecording,
              location.horizontalAccuracy >= 0,
              location.timestamp.timeIntervalSinceNow > -10 * 60
        else { return }

        let sample = CodexLocationSample(
            capturedAt: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy
        )
        guard trail.shouldRecord(sample) else { return }

        trail.record(sample)
        samples = trail.samples
        persist()
        resolvePlaceName(for: sample, at: location)
    }

    private func resolvePlaceName(
        for sample: CodexLocationSample,
        at location: CLLocation
    ) {
        guard !geocoder.isGeocoding else { return }
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let placeName = Self.placeName(from: placemark)
            Task { @MainActor [weak self] in
                guard let self, let placeName else { return }
                trail.updatePlaceName(placeName, for: sample.id)
                samples = trail.samples
                persist()
            }
        }
    }

    nonisolated private static func placeName(from placemark: CLPlacemark) -> String? {
        let candidates = [
            placemark.subLocality,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
        ]
        var unique: [String] = []
        for candidate in candidates.compactMap({ $0 }) where !unique.contains(candidate) {
            unique.append(candidate)
            if unique.count == 2 { break }
        }
        return unique.isEmpty ? placemark.name : unique.joined(separator: ", ")
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(trail.samples) else { return }
        defaults.set(data, forKey: Self.samplesStorageKey)
    }
}

extension CodexLocationRecorder: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        resumeIfEnabled()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        lastErrorDescription = nil
        accept(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let coreLocationError = error as? CLError
        guard coreLocationError?.code != .locationUnknown else { return }
        lastErrorDescription = error.localizedDescription
    }
}
