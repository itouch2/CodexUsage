import Foundation

public struct CodexLocationSample: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var capturedAt: Date
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var placeName: String?

    public init(
        id: UUID = UUID(),
        capturedAt: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        placeName: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.placeName = placeName
    }

    public var displayPlace: String {
        if let placeName = placeName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !placeName.isEmpty {
            return placeName
        }
        return coordinateDescription
    }

    public var coordinateDescription: String {
        String(
            format: "%.4f, %.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            latitude,
            longitude
        )
    }

    public var accuracyDescription: String {
        guard horizontalAccuracy >= 0 else { return "Unknown accuracy" }
        if horizontalAccuracy < 1_000 {
            return "Approx. ±\(Int(horizontalAccuracy.rounded())) m"
        }
        return String(
            format: "Approx. ±%.1f km",
            locale: Locale(identifier: "en_US_POSIX"),
            horizontalAccuracy / 1_000
        )
    }
}

public struct CodexLocationTrail: Equatable, Sendable {
    public static let defaultMaximumSampleCount = 5_000
    public static let defaultRetentionInterval: TimeInterval = 30 * 24 * 60 * 60
    public static let minimumMovingSampleInterval: TimeInterval = 5 * 60
    public static let stationarySampleInterval: TimeInterval = 15 * 60
    public static let minimumMovementDistance: Double = 1_000

    public private(set) var samples: [CodexLocationSample]
    public var maximumSampleCount: Int
    public var retentionInterval: TimeInterval

    public init(
        samples: [CodexLocationSample] = [],
        maximumSampleCount: Int = Self.defaultMaximumSampleCount,
        retentionInterval: TimeInterval = Self.defaultRetentionInterval
    ) {
        self.samples = samples
        self.maximumSampleCount = max(1, maximumSampleCount)
        self.retentionInterval = max(0, retentionInterval)
        normalize()
    }

    public mutating func record(_ sample: CodexLocationSample) {
        samples.removeAll { $0.id == sample.id }
        samples.append(sample)
        normalize()
    }

    public func shouldRecord(_ sample: CodexLocationSample) -> Bool {
        guard let latest = samples.first else { return true }
        let elapsed = sample.capturedAt.timeIntervalSince(latest.capturedAt)
        guard elapsed >= Self.minimumMovingSampleInterval else { return false }
        if elapsed >= Self.stationarySampleInterval { return true }
        return distanceMeters(from: latest, to: sample) >= Self.minimumMovementDistance
    }

    public func samples(from start: Date, through end: Date) -> [CodexLocationSample] {
        guard start <= end else { return [] }
        return samples
            .filter { $0.capturedAt >= start && $0.capturedAt <= end }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    public mutating func updatePlaceName(_ placeName: String, for sampleID: UUID) {
        guard let index = samples.firstIndex(where: { $0.id == sampleID }) else { return }
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        samples[index].placeName = trimmed
    }

    private mutating func normalize() {
        samples.sort { $0.capturedAt > $1.capturedAt }
        if let newestDate = samples.first?.capturedAt {
            let cutoff = newestDate.addingTimeInterval(-retentionInterval)
            samples.removeAll { $0.capturedAt < cutoff }
        }
        if samples.count > maximumSampleCount {
            samples.removeLast(samples.count - maximumSampleCount)
        }
    }

    private func distanceMeters(
        from start: CodexLocationSample,
        to end: CodexLocationSample
    ) -> Double {
        let earthRadius = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let centralAngle = 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
        return earthRadius * centralAngle
    }
}
