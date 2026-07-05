import XCTest
@testable import RouteTraceShared

private enum RouteTraceTestSupport {
    static var fixturesBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle(for: RouteTraceSharedTests.self)
        #endif
    }
}

final class RouteTraceSharedTests: XCTestCase {
    func testParsesSimpleTrack() throws {
        let url = RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx")
            ?? RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx", subdirectory: "Fixtures")
        let resolvedURL = try XCTUnwrap(url)
        let data = try Data(contentsOf: resolvedURL)
        let parsed = try GPXParser().parse(data: data)
        XCTAssertEqual(parsed.usablePointCount, 5)
        XCTAssertEqual(parsed.metadataName, "Test Loop")
    }

    func testRouteProcessorComputesDistance() throws {
        let url = RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx")
            ?? RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx", subdirectory: "Fixtures")
        let resolvedURL = try XCTUnwrap(url)
        let parsed = try GPXParser().parse(data: try Data(contentsOf: resolvedURL))
        let package = RouteProcessor().makeRoutePackage(
            from: parsed,
            sourceFileName: "simple_track.gpx",
            activityHint: .running
        )
        XCTAssertGreaterThanOrEqual(package.route.count, 2)
        XCTAssertGreaterThan(package.distanceMeters, 0)
        XCTAssertNotNil(package.elevationGainMeters)
        XCTAssertFalse(package.cues.isEmpty)
    }

    func testCueGeneratorDetectsTurn() {
        let route = [
            RoutePoint(id: 0, latitude: 48.8566, longitude: 2.3522, elevationMeters: nil, distanceFromStartMeters: 0, bearingDegrees: 0),
            RoutePoint(id: 1, latitude: 48.8570, longitude: 2.3530, elevationMeters: nil, distanceFromStartMeters: 80, bearingDegrees: 45),
            RoutePoint(id: 2, latitude: 48.8575, longitude: 2.3540, elevationMeters: nil, distanceFromStartMeters: 160, bearingDegrees: 90),
            RoutePoint(id: 3, latitude: 48.8580, longitude: 2.3555, elevationMeters: nil, distanceFromStartMeters: 260, bearingDegrees: 90)
        ]
        let cues = RouteCueGenerator(minimumCueSpacingMeters: 10).generate(route: route)
        XCTAssertTrue(cues.contains { $0.kind == .turnRight || $0.kind == .slightRight })
    }

    func testNavigationEngineProgressesForward() throws {
        let url = RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx")
            ?? RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx", subdirectory: "Fixtures")
        let resolvedURL = try XCTUnwrap(url)
        let parsed = try GPXParser().parse(data: try Data(contentsOf: resolvedURL))
        let package = RouteProcessor().makeRoutePackage(
            from: parsed,
            sourceFileName: "simple_track.gpx",
            activityHint: .running
        )
        let engine = RouteNavigationEngine(routePackage: package)
        let first = package.route[0]
        let update = engine.update(
            latitude: first.latitude,
            longitude: first.longitude,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 2
        )
        XCTAssertNotNil(update)
        XCTAssertGreaterThanOrEqual(update!.progressDistanceMeters, 0)
        XCTAssertFalse(update!.isOffRoute)
    }

    func testMapMathBearingDelta() {
        let delta = MapMath.bearingDelta(from: 350, to: 10)
        XCTAssertEqual(delta, 20, accuracy: 0.1)
    }

    func testRoutePackArchiveRoundTripsTileFiles() throws {
        let fileManager = FileManager.default
        let sourceRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: sourceRoot)
            try? fileManager.removeItem(at: installRoot)
        }

        let fixtureURL = RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx")
            ?? RouteTraceTestSupport.fixturesBundle.url(forResource: "simple_track", withExtension: "gpx", subdirectory: "Fixtures")
        let resolvedURL = try XCTUnwrap(fixtureURL)
        let parsed = try GPXParser().parse(data: try Data(contentsOf: resolvedURL))
        let package = RouteProcessor().makeRoutePackage(
            from: parsed,
            sourceFileName: "simple_track.gpx",
            activityHint: .running
        )

        let routeDirectory = try RoutePackaging.writeRoutePackage(package, to: sourceRoot)

        let manifest = OfflineMapManifest(
            minZoom: 13,
            maxZoom: 13,
            tileCount: 1,
            packSizeBytes: 4
        )
        let manifestURL = routeDirectory.appendingPathComponent("manifest.json")
        try RouteTracePayloadCoding.encode(manifest).write(to: manifestURL, options: .atomic)

        let tilesDirectory = routeDirectory.appendingPathComponent("tiles", isDirectory: true)
        try fileManager.createDirectory(at: tilesDirectory, withIntermediateDirectories: true)
        let tileFilename = "z13_x4192_y2938.png"
        let tileData = Data([0x89, 0x50, 0x4E, 0x47])
        try tileData.write(to: tilesDirectory.appendingPathComponent(tileFilename), options: .atomic)

        let archiveURL = RoutePackaging.makeArchiveURL(for: package, in: sourceRoot)
        try RoutePackaging.zipRouteDirectory(routeDirectory, to: archiveURL)

        let installedDirectory = try RoutePackaging.installArchive(at: archiveURL, to: installRoot)
        let installedTileURL = installedDirectory
            .appendingPathComponent("tiles", isDirectory: true)
            .appendingPathComponent(tileFilename)

        XCTAssertTrue(fileManager.fileExists(atPath: installedTileURL.path))
        XCTAssertEqual(try Data(contentsOf: installedTileURL), tileData)
    }

    func testActivityTrackStatisticsGPSDistance() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            TrackPoint(timestamp: base, latitude: 48.8566, longitude: 2.3522, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(10), latitude: 48.8570, longitude: 2.3530, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(20), latitude: 48.8575, longitude: 2.3540, horizontalAccuracyMeters: 5)
        ]
        let distance = ActivityTrackStatistics.gpsDistanceMeters(from: points)
        XCTAssertGreaterThan(distance, 100)
        XCTAssertLessThan(distance, 500)
    }

    func testActivityTrackStatisticsElevationGain() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            TrackPoint(timestamp: base, latitude: 48.8566, longitude: 2.3522, altitudeMeters: 100, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(10), latitude: 48.8570, longitude: 2.3530, altitudeMeters: 110, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(20), latitude: 48.8575, longitude: 2.3540, altitudeMeters: 105, horizontalAccuracyMeters: 5)
        ]
        let gain = ActivityTrackStatistics.elevationGainMeters(from: points, fallback: nil)
        XCTAssertEqual(gain ?? 0, 10, accuracy: 0.01)
    }

    func testTrackSegmentSplitterDetectsTimeGap() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            TrackPoint(timestamp: base, latitude: 48.8566, longitude: 2.3522, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(10), latitude: 48.8570, longitude: 2.3530, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(130), latitude: 48.8600, longitude: 2.3600, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(140), latitude: 48.8605, longitude: 2.3610, horizontalAccuracyMeters: 5)
        ]
        let segments = TrackSegmentSplitter.continuousSegments(from: points)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 2)
        XCTAssertEqual(segments[1].count, 2)

        let renderSegments = TrackSegmentSplitter.segments(from: points)
        XCTAssertEqual(renderSegments.filter { !$0.isGapConnector }.count, 2)
        XCTAssertEqual(renderSegments.filter(\.isGapConnector).count, 1)
    }

    func testTrackSegmentSplitterDetectsSpatialJump() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            TrackPoint(timestamp: base, latitude: 48.8566, longitude: 2.3522, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(5), latitude: 48.8570, longitude: 2.3530, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: base.addingTimeInterval(10), latitude: 48.8700, longitude: 2.3700, horizontalAccuracyMeters: 5)
        ]
        let segments = TrackSegmentSplitter.continuousSegments(from: points)
        XCTAssertEqual(segments.count, 2)
    }

    func testActivityNamingTitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let morning = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 8))!
        XCTAssertEqual(
            ActivityNaming.title(startedAt: morning, activityKind: .running, routeName: "Forest Loop", calendar: calendar),
            "Morning run (Forest Loop)"
        )

        let lateAfternoon = calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 18))!
        XCTAssertEqual(
            ActivityNaming.title(startedAt: lateAfternoon, activityKind: .gravelCycling, routeName: "Gravel 40", calendar: calendar),
            "Late afternoon gravel biking (Gravel 40)"
        )
    }

    func testActivityRecordingDisplayTitleFallsBackToRouteName() {
        let recording = ActivityRecording(
            routeId: UUID(),
            routeName: "Loop",
            activityKind: .running
        )
        XCTAssertEqual(recording.displayTitle, "Loop")
    }

    func testGPXExportActivityEmitsSeparateTrackSegments() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let activity = ActivityRecording(
            routeId: UUID(),
            routeName: "Gap Test",
            startedAt: base,
            endedAt: base.addingTimeInterval(200),
            activityKind: .running,
            trackPoints: [
                TrackPoint(timestamp: base, latitude: 48.8566, longitude: 2.3522, horizontalAccuracyMeters: 5),
                TrackPoint(timestamp: base.addingTimeInterval(10), latitude: 48.8570, longitude: 2.3530, horizontalAccuracyMeters: 5),
                TrackPoint(timestamp: base.addingTimeInterval(130), latitude: 48.8600, longitude: 2.3600, horizontalAccuracyMeters: 5),
                TrackPoint(timestamp: base.addingTimeInterval(140), latitude: 48.8605, longitude: 2.3610, horizontalAccuracyMeters: 5)
            ]
        )
        let gpx = GPXExporter.exportActivity(activity, route: nil)
        let trksegCount = gpx.components(separatedBy: "<trkseg>").count - 1
        XCTAssertEqual(trksegCount, 2)
    }

    func testGPXExportActivityContinuousTrackHasSingleSegment() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let activity = ActivityRecording(
            routeId: UUID(),
            routeName: "Continuous",
            startedAt: base,
            activityKind: .running,
            trackPoints: [
                TrackPoint(timestamp: base, latitude: 48.8566, longitude: 2.3522, horizontalAccuracyMeters: 5),
                TrackPoint(timestamp: base.addingTimeInterval(10), latitude: 48.8570, longitude: 2.3530, horizontalAccuracyMeters: 5)
            ]
        )
        let gpx = GPXExporter.exportActivity(activity, route: nil)
        let trksegCount = gpx.components(separatedBy: "<trkseg>").count - 1
        XCTAssertEqual(trksegCount, 1)
    }

    func testActivityTrackStatisticsAverageSpeed() {
        let speed = ActivityTrackStatistics.averageSpeedMetersPerSecond(
            gpsDistanceMeters: 5000,
            elapsedSeconds: 1000
        )
        XCTAssertEqual(speed ?? 0, 5, accuracy: 0.01)
    }

    func testLocationQualityFilterRejectsStaleFix() {
        var filter = LocationQualityFilter()
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let input = LocationQualityInput(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracyMeters: 5,
            timestamp: reference.addingTimeInterval(-10)
        )

        let outcome = filter.evaluate(
            input: input,
            activityKind: .running,
            batteryMode: .normal,
            mode: .recording,
            referenceDate: reference
        )

        guard case .rejected(.staleFix) = outcome else {
            return XCTFail("Expected stale fix rejection, got \(outcome)")
        }
    }

    func testLocationQualityFilterRejectsPoorAccuracyDuringStabilization() {
        var filter = LocationQualityFilter()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let input = LocationQualityInput(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracyMeters: 80,
            timestamp: timestamp
        )

        let outcome = filter.evaluate(
            input: input,
            activityKind: .running,
            batteryMode: .normal,
            mode: .recording,
            referenceDate: timestamp
        )

        guard case .rejected(.poorAccuracy) = outcome else {
            return XCTFail("Expected poor accuracy rejection, got \(outcome)")
        }
    }

    func testLocationQualityFilterRequiresConsecutiveGoodFixes() {
        var filter = LocationQualityFilter()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let first = LocationQualityInput(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracyMeters: 5,
            timestamp: base
        )
        let second = LocationQualityInput(
            latitude: 48.8567,
            longitude: 2.3523,
            horizontalAccuracyMeters: 5,
            timestamp: base.addingTimeInterval(2)
        )

        XCTAssertEqual(
            filter.evaluate(input: first, activityKind: .running, batteryMode: .normal, mode: .recording, referenceDate: base.addingTimeInterval(2)),
            .previewOnly
        )
        XCTAssertEqual(
            filter.evaluate(input: second, activityKind: .running, batteryMode: .normal, mode: .recording, referenceDate: base.addingTimeInterval(2)),
            .accepted
        )
        XCTAssertTrue(filter.hasStabilized)
    }

    func testLocationQualityFilterRejectsSpatialJumpOutlier() {
        var filter = LocationQualityFilter()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        _ = filter.evaluate(
            input: LocationQualityInput(
                latitude: 48.8566,
                longitude: 2.3522,
                horizontalAccuracyMeters: 5,
                timestamp: base
            ),
            activityKind: .running,
            batteryMode: .normal,
            mode: .recording,
            referenceDate: base
        )
        _ = filter.evaluate(
            input: LocationQualityInput(
                latitude: 48.8567,
                longitude: 2.3523,
                horizontalAccuracyMeters: 5,
                timestamp: base.addingTimeInterval(2)
            ),
            activityKind: .running,
            batteryMode: .normal,
            mode: .recording,
            referenceDate: base.addingTimeInterval(2)
        )

        let outlier = LocationQualityInput(
            latitude: 48.8700,
            longitude: 2.3700,
            horizontalAccuracyMeters: 5,
            timestamp: base.addingTimeInterval(7)
        )
        let outcome = filter.evaluate(
            input: outlier,
            activityKind: .running,
            batteryMode: .normal,
            mode: .recording,
            referenceDate: base.addingTimeInterval(7)
        )

        guard case .rejected(.excessiveSpeed) = outcome else {
            return XCTFail("Expected excessive speed rejection, got \(outcome)")
        }
    }

    func testLocationQualityFilterWarmupReadyUsesStabilizationAccuracy() {
        let filter = LocationQualityFilter()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let ready = LocationQualityInput(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracyMeters: 20,
            timestamp: timestamp
        )
        let weak = LocationQualityInput(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracyMeters: 40,
            timestamp: timestamp
        )

        XCTAssertTrue(filter.isWarmupReady(input: ready, activityKind: .running, referenceDate: timestamp))
        XCTAssertFalse(filter.isWarmupReady(input: weak, activityKind: .running, referenceDate: timestamp))
    }

    func testLocationQualityFilterRestoreStartsStabilized() {
        var filter = LocationQualityFilter()
        let seed = LocationQualityInput(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracyMeters: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        filter.reset(startingStabilized: true, seed: seed)

        XCTAssertTrue(filter.hasStabilized)

        let next = LocationQualityInput(
            latitude: 48.8568,
            longitude: 2.3524,
            horizontalAccuracyMeters: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_010)
        )
        XCTAssertEqual(
            filter.evaluate(input: next, activityKind: .running, batteryMode: .normal, mode: .recording),
            .accepted
        )
    }

    func testRouteProcessorDensifiesLongSegments() {
        let sparseRoute = [
            RoutePoint(id: 0, latitude: 48.8566, longitude: 2.3522, elevationMeters: nil, distanceFromStartMeters: 0, bearingDegrees: 0),
            RoutePoint(id: 1, latitude: 48.8600, longitude: 2.3600, elevationMeters: nil, distanceFromStartMeters: 900, bearingDegrees: 45)
        ]

        let densified = RouteProcessor().densify(route: sparseRoute, maxSegmentMeters: 50)
        XCTAssertGreaterThan(densified.count, sparseRoute.count)

        for index in 0 ..< (densified.count - 1) {
            let length = MapMath.haversineMeters(
                from: densified[index].coordinate,
                to: densified[index + 1].coordinate
            )
            XCTAssertLessThanOrEqual(length, 50.5)
        }
    }

    func testRouteNavigationQualityWarnsForSparseLongRoute() {
        let warning = RouteNavigationQuality.warning(
            distanceMeters: 6_000,
            originalPointCount: 8,
            simplifiedPointCount: 6
        )
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("6 navigation points") == true)
    }

    func testRouteNavigationQualityDoesNotWarnForDenseRoute() {
        let warning = RouteNavigationQuality.warning(
            distanceMeters: 6_000,
            originalPointCount: 500,
            simplifiedPointCount: 120
        )
        XCTAssertNil(warning)
    }

    func testDisplayCoordinateSmootherBlendsOnRoute() {
        var smoother = DisplayCoordinateSmoother()
        let raw = GeoCoordinate(latitude: 48.8566, longitude: 2.3522)
        let projected = GeoCoordinate(latitude: 48.8567, longitude: 2.3524)

        let smoothed = smoother.coordinate(
            raw: raw,
            projected: projected,
            horizontalAccuracyMeters: 10,
            isOffRoute: false,
            recordingAccuracyThresholdMeters: 50
        )

        XCTAssertNotEqual(smoothed.latitude, raw.latitude)
        XCTAssertNotEqual(smoothed.longitude, raw.longitude)
        XCTAssertNotEqual(smoothed.latitude, projected.latitude)
    }

    func testDisplayCoordinateSmootherReturnsRawWhenOffRoute() {
        var smoother = DisplayCoordinateSmoother()
        let raw = GeoCoordinate(latitude: 48.8566, longitude: 2.3522)
        let projected = GeoCoordinate(latitude: 48.8600, longitude: 2.3600)

        let smoothed = smoother.coordinate(
            raw: raw,
            projected: projected,
            horizontalAccuracyMeters: 10,
            isOffRoute: true,
            recordingAccuracyThresholdMeters: 50
        )

        XCTAssertEqual(smoothed.latitude, raw.latitude, accuracy: 0.000001)
        XCTAssertEqual(smoothed.longitude, raw.longitude, accuracy: 0.000001)
    }

    func testNavigationEngineWidensSearchAfterPersistentOffRoute() {
        let route = (0 ... 40).map { index in
            RoutePoint(
                id: index,
                latitude: 48.8566 + Double(index) * 0.0004,
                longitude: 2.3522 + Double(index) * 0.0004,
                elevationMeters: nil,
                distanceFromStartMeters: Double(index) * 60,
                bearingDegrees: 45
            )
        }
        let package = RoutePackage(
            id: UUID(),
            name: "Wide Search",
            sourceFileName: "wide.gpx",
            importedAt: Date(),
            activityHint: .running,
            distanceMeters: route.last?.distanceFromStartMeters ?? 0,
            elevationGainMeters: nil,
            elevationLossMeters: nil,
            boundingBox: GeoBoundingBox(minLatitude: 48.8566, maxLatitude: 48.8726, minLongitude: 2.3522, maxLongitude: 2.3682),
            originalPointCount: route.count,
            simplifiedPointCount: route.count,
            route: route,
            cues: [],
            offlineMapManifest: nil
        )

        let engine = RouteNavigationEngine(routePackage: package)

        _ = engine.update(latitude: 48.8566, longitude: 2.3522, horizontalAccuracyMeters: 5, speedMetersPerSecond: 2)
        for _ in 0 ..< 3 {
            _ = engine.update(
                latitude: 48.8700,
                longitude: 2.3700,
                horizontalAccuracyMeters: 5,
                speedMetersPerSecond: 2
            )
        }

        let rejoinUpdate = engine.update(
            latitude: route[30].latitude,
            longitude: route[30].longitude,
            horizontalAccuracyMeters: 5,
            speedMetersPerSecond: 2
        )

        XCTAssertNotNil(rejoinUpdate)
        XCTAssertGreaterThanOrEqual(rejoinUpdate?.segmentIndex ?? 0, 20)
    }
}
