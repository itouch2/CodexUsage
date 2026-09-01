import CodexUsageCore
import Foundation
import XCTest

final class CodexLocationTrailTests: XCTestCase {
    func testLocationSampleRoundTripsWithPlaceAndAccuracy() throws {
        let sample = CodexLocationSample(
            id: UUID(uuidString: "B52FA5B2-4EE8-4FC2-AAB9-9DC51D4D2924")!,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000),
            latitude: 31.2304,
            longitude: 121.4737,
            horizontalAccuracy: 420,
            placeName: "Shanghai"
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(CodexLocationSample.self, from: data)

        XCTAssertEqual(decoded, sample)
        XCTAssertEqual(decoded.displayPlace, "Shanghai")
        XCTAssertEqual(decoded.coordinateDescription, "31.2304, 121.4737")
        XCTAssertEqual(decoded.accuracyDescription, "Approx. ±420 m")
    }

    func testTrailKeepsNewestSamplesWithinRetentionAndCountLimits() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var trail = CodexLocationTrail(
            maximumSampleCount: 2,
            retentionInterval: 60 * 60
        )

        trail.record(sample(at: now.addingTimeInterval(-7_200), latitude: 30))
        trail.record(sample(at: now.addingTimeInterval(-600), latitude: 31))
        trail.record(sample(at: now, latitude: 32))

        XCTAssertEqual(trail.samples.map(\.latitude), [32, 31])
    }

    func testTrailRecordsMovementAtFiveMinutesAndStationaryPointsAtFifteenMinutes() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var trail = CodexLocationTrail()
        trail.record(sample(at: start, latitude: 31.2304, longitude: 121.4737))

        XCTAssertFalse(trail.shouldRecord(
            sample(at: start.addingTimeInterval(120), latitude: 31.5, longitude: 121.8)
        ))
        XCTAssertTrue(trail.shouldRecord(
            sample(at: start.addingTimeInterval(360), latitude: 31.25, longitude: 121.49)
        ))
        XCTAssertFalse(trail.shouldRecord(
            sample(at: start.addingTimeInterval(600), latitude: 31.2305, longitude: 121.4738)
        ))
        XCTAssertTrue(trail.shouldRecord(
            sample(at: start.addingTimeInterval(960), latitude: 31.2305, longitude: 121.4738)
        ))
    }

    func testTrailReturnsChronologicalSamplesForWorkWindow() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var trail = CodexLocationTrail()
        trail.record(sample(at: start.addingTimeInterval(1_200), latitude: 33))
        trail.record(sample(at: start.addingTimeInterval(600), latitude: 32))
        trail.record(sample(at: start, latitude: 31))

        let window = trail.samples(
            from: start.addingTimeInterval(300),
            through: start.addingTimeInterval(1_500)
        )

        XCTAssertEqual(window.map(\.latitude), [32, 33])
    }

    func testTrailUpdatesResolvedPlaceNameWithoutChangingRouteOrder() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let first = sample(at: start, latitude: 31)
        let second = sample(at: start.addingTimeInterval(600), latitude: 32)
        var trail = CodexLocationTrail(samples: [first, second])

        trail.updatePlaceName("Nanjing", for: second.id)

        XCTAssertEqual(trail.samples.map(\.id), [second.id, first.id])
        XCTAssertEqual(trail.samples.first?.placeName, "Nanjing")
    }

    private func sample(
        at date: Date,
        latitude: Double,
        longitude: Double = 121,
        accuracy: Double = 500
    ) -> CodexLocationSample {
        CodexLocationSample(
            capturedAt: date,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: accuracy
        )
    }
}

final class CodexLocationRecordingContractTests: XCTestCase {
    func testRecorderUsesCoreLocationAndPersistsLocalSamples() throws {
        let source = sourceTextIfPresent(
            at: "Sources/CodexUsageApp/CodexLocationRecorder.swift"
        )
        XCTAssertNotNil(source, "CodexLocationRecorder.swift must exist")
        guard let source else { return }

        XCTAssertTrue(source.contains("import CoreLocation"))
        XCTAssertTrue(source.contains("CLLocationManagerDelegate"))
        XCTAssertTrue(source.contains("requestWhenInUseAuthorization"))
        XCTAssertTrue(source.contains("startUpdatingLocation"))
        XCTAssertTrue(source.contains("codexUsage.locationSamples"))
        XCTAssertTrue(source.contains("codexUsage.locationRecordingEnabled"))
        XCTAssertTrue(source.contains("reverseGeocodeLocation"))
    }

    func testCodexUsageShowsExplicitLocalLocationControls() throws {
        let root = try sourceText(
            at: "Sources/CodexUsageApp/AgentUsageView.swift"
        )
        let inspector = try sourceText(
            at: "Sources/CodexUsageApp/WidgetInspectorView.swift"
        )

        XCTAssertTrue(root.contains("CodexLocationRecorder.shared"))
        XCTAssertTrue(inspector.contains("Toggle(\"Work Trail\""))
        XCTAssertTrue(inspector.contains("recorder.setRecordingEnabled"))
        XCTAssertTrue(inspector.contains("Location stays on this Mac"))
        XCTAssertTrue(inspector.contains("Clear Location History"))
    }

    func testAppDeclaresLocationPurposeAndSandboxCapability() throws {
        let plist = try sourceText(at: "Packaging/Info.plist.in")
        let entitlements = try sourceText(
            at: "Packaging/CodexUsage.entitlements"
        )

        XCTAssertTrue(plist.contains("NSLocationUsageDescription"))
        XCTAssertTrue(plist.contains("match Codex work with where it happened"))
        XCTAssertTrue(entitlements.contains(
            "com.apple.security.personal-information.location"
        ))
    }

    func testLocalBundleSigningPreservesLocationEntitlement() throws {
        let packageScript = try sourceText(at: "scripts/package_app.sh")

        XCTAssertTrue(packageScript.contains(
            #"ENTITLEMENTS="$ROOT_DIR/Packaging/CodexUsage.entitlements""#
        ))
        XCTAssertTrue(packageScript.contains(#"--entitlements "$ENTITLEMENTS""#))
        XCTAssertTrue(packageScript.contains("--options runtime"))
        XCTAssertTrue(packageScript.contains("TIMESTAMP_ARGS=(--timestamp)"))
        XCTAssertTrue(packageScript.contains(#"--product "$EXECUTABLE_NAME""#))
        XCTAssertTrue(packageScript.contains("codesign --verify --deep --strict"))
    }

    private func sourceTextIfPresent(at relativePath: String) -> String? {
        try? String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceText(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
