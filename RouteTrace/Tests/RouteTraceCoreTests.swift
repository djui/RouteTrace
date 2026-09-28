import XCTest
@testable import RouteTraceShared

private func makeRoute(_ coordinates: [GeoCoordinate]) -> [RoutePoint] {
    var distance = 0.0
    return coordinates.enumerated().map { index, coordinate in
        if index > 0 {
            distance += MapMath.haversineMeters(from: coordinates[index - 1], to: coordinate)
        }
        return RoutePoint(
            id: index,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            elevationMeters: nil,
            distanceFromStartMeters: distance,
            bearingDegrees: nil
        )
    }
}

private func offset(_ coordinate: GeoCoordinate, meters: Double, bearingDegrees: Double) -> GeoCoordinate {
    let bearing = bearingDegrees * .pi / 180
    let dLat = meters * cos(bearing) / 111_320
    let dLon = meters * sin(bearing) / (111_320 * cos(coordinate.latitude * .pi / 180))
    return GeoCoordinate(latitude: coordinate.latitude + dLat, longitude: coordinate.longitude + dLon)
}

final class GPXParsingTests: XCTestCase {
    private func parse(_ xml: String) throws -> ParsedGPX {
        try GPXParser().parse(data: Data(xml.utf8))
    }

    func testAuthorNameDoesNotReplaceMetadataName() throws {
        let parsed = try parse("""
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>Alps Loop</name>
            <author><name>Uwe</name></author>
          </metadata>
          <trk><trkseg>
            <trkpt lat="45.9" lon="6.8"/><trkpt lat="45.91" lon="6.81"/>
          </trkseg></trk>
        </gpx>
        """)
        XCTAssertEqual(parsed.importName, "Alps Loop")
    }

    func testRoutePointNamesDoNotReplaceRouteName() throws {
        let parsed = try parse("""
        <gpx version="1.1">
          <rte>
            <name>Coast Ride</name>
            <rtept lat="59.30" lon="18.00"><name>Turn left</name></rtept>
            <rtept lat="59.31" lon="18.02"><name>Cafe stop</name></rtept>
          </rte>
        </gpx>
        """)
        XCTAssertEqual(parsed.routes.first?.name, "Coast Ride")
        XCTAssertEqual(parsed.importName, "Coast Ride")
        XCTAssertEqual(parsed.usablePointCount, 2)
    }

    func testParsesFractionalSecondTimestampsAndNamespacedElements() throws {
        let parsed = try parse("""
        <gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1">
          <gpx:trk><gpx:trkseg>
            <gpx:trkpt lat="48.1" lon="11.5"><gpx:ele>520.5</gpx:ele><gpx:time>2026-05-01T07:30:00.250Z</gpx:time></gpx:trkpt>
            <gpx:trkpt lat="48.2" lon="11.6"><gpx:ele>530</gpx:ele><gpx:time>2026-05-01T07:31:00Z</gpx:time></gpx:trkpt>
          </gpx:trkseg></gpx:trk>
        </gpx:gpx>
        """)
        let points = parsed.primaryTrackPoints
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].elevationMeters, 520.5)
        XCTAssertNotNil(points[0].timestamp)
        XCTAssertNotNil(points[1].timestamp)
    }

    func testSkipsNullIslandFixes() throws {
        let parsed = try parse("""
        <gpx version="1.1"><trk><trkseg>
          <trkpt lat="48.1" lon="11.5"/>
          <trkpt lat="0" lon="0"/>
          <trkpt lat="48.2" lon="11.6"/>
        </trkseg></trk></gpx>
        """)
        XCTAssertEqual(parsed.usablePointCount, 2)
        XCTAssertEqual(parsed.invalidPointCount, 1)
    }

    func testActivityExportIncludesNamespaceAndHeartRate() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let recording = ActivityRecording(
            routeId: UUID(),
            routeName: "Loop",
            startedAt: start,
            activityKind: .running,
            trackPoints: [
                TrackPoint(timestamp: start, latitude: 59.3, longitude: 18.0, altitudeMeters: 12, horizontalAccuracyMeters: 5, heartRateBPM: 141.6),
                TrackPoint(timestamp: start.addingTimeInterval(5), latitude: 59.3001, longitude: 18.0002, altitudeMeters: 13, horizontalAccuracyMeters: 5, heartRateBPM: 143)
            ]
        )
        let gpx = GPXExporter.exportActivity(recording, route: nil)
        XCTAssertTrue(gpx.contains(#"xmlns="http://www.topografix.com/GPX/1/1""#))
        XCTAssertTrue(gpx.contains("<gpxtpx:hr>142</gpxtpx:hr>"))

        let reparsed = try parse(gpx)
        XCTAssertEqual(reparsed.usablePointCount, 2)
        XCTAssertEqual(reparsed.primaryTrackPoints.first?.elevationMeters, 12)
    }
}

final class MapMathTests: XCTestCase {
    /// At 60°N a longitude degree is half a latitude degree. Projecting in raw degrees used to
    /// put the foot point in the wrong place and overstate how far off-route the runner was.
    func testOffRouteDistanceIsCorrectAtHighLatitude() {
        let start = GeoCoordinate(latitude: 60.0, longitude: 18.0)
        let end = GeoCoordinate(latitude: 60.002, longitude: 18.006) // ~ 390 m to the east-north-east
        let route = makeRoute([start, end])

        // Walk 30 m perpendicular off the segment's midpoint.
        let mid = GeoCoordinate(latitude: 60.001, longitude: 18.003)
        let bearing = MapMath.bearingDegrees(from: start, to: end)
        let offRoutePoint = offset(mid, meters: 30, bearingDegrees: bearing - 90)

        let result = MapMath.nearestPointOnPolyline(to: offRoutePoint, route: route)
        XCTAssertEqual(result?.distanceMeters ?? 0, 30, accuracy: 1.0)
        XCTAssertEqual(
            result?.distanceAlongRouteMeters ?? 0,
            MapMath.haversineMeters(from: start, to: mid),
            accuracy: 2.0
        )
    }

    func testNearestPointPrefersEarliestSegmentOnLoops() {
        // A square loop that returns to its start.
        let corners = [
            GeoCoordinate(latitude: 59.30, longitude: 18.00),
            GeoCoordinate(latitude: 59.30, longitude: 18.01),
            GeoCoordinate(latitude: 59.31, longitude: 18.01),
            GeoCoordinate(latitude: 59.31, longitude: 18.00),
            GeoCoordinate(latitude: 59.30, longitude: 18.00)
        ]
        let route = makeRoute(corners)
        let atStart = GeoCoordinate(latitude: 59.30, longitude: 18.00001)

        let earliest = MapMath.nearestPointOnPolyline(
            to: atStart,
            route: route,
            searchWindow: route.count,
            preferEarliestWithinMeters: 20
        )
        XCTAssertEqual(earliest?.segmentIndex, 0)
    }

    func testNearestPointClampsOutOfRangeSearchStart() {
        let route = makeRoute([
            GeoCoordinate(latitude: 59.30, longitude: 18.00),
            GeoCoordinate(latitude: 59.30, longitude: 18.01)
        ])
        XCTAssertNotNil(MapMath.nearestPointOnPolyline(
            to: GeoCoordinate(latitude: 59.30, longitude: 18.005),
            route: route,
            searchStartIndex: 500
        ))
    }

    func testTileUnitsRoundTrip() {
        let coordinate = GeoCoordinate(latitude: 45.9237, longitude: 6.8694)
        let units = MapMath.tileUnits(for: coordinate, zoom: 15)
        XCTAssertEqual(Int(units.x), MapMath.tileX(longitude: coordinate.longitude, zoom: 15))
        XCTAssertEqual(Int(units.y), MapMath.tileY(latitude: coordinate.latitude, zoom: 15))

        let back = MapMath.coordinate(fromTileUnits: units.x, units.y, zoom: 15)
        XCTAssertEqual(back.latitude, coordinate.latitude, accuracy: 1e-9)
        XCTAssertEqual(back.longitude, coordinate.longitude, accuracy: 1e-9)
    }
}

final class NavigationEngineTests: XCTestCase {
    private func straightRoute(points: Int = 60, stepDegrees: Double = 0.0004) -> RoutePackage {
        let coordinates = (0..<points).map {
            GeoCoordinate(latitude: 59.30 + Double($0) * stepDegrees, longitude: 18.00)
        }
        let parsed = ParsedGPX(
            metadataName: "Straight",
            tracks: [ParsedGPXTrack(name: nil, segments: [coordinates.map {
                ParsedGPXPoint(latitude: $0.latitude, longitude: $0.longitude, elevationMeters: nil, timestamp: nil)
            }])],
            routes: [],
            waypoints: [],
            warnings: [],
            invalidPointCount: 0
        )
        return RouteProcessor().makeRoutePackage(from: parsed, sourceFileName: "straight.gpx", activityHint: .running)
    }

    func testRemainingDistanceReachesZeroAtFinish() throws {
        let package = straightRoute()
        let engine = RouteNavigationEngine(routePackage: package)
        for point in package.route {
            _ = engine.update(latitude: point.latitude, longitude: point.longitude, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3)
        }
        let last = try XCTUnwrap(package.route.last)
        let update = try XCTUnwrap(engine.update(latitude: last.latitude, longitude: last.longitude, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3))
        XCTAssertEqual(update.distanceRemainingMeters, 0, accuracy: 0.5)
        XCTAssertEqual(update.progressDistanceMeters, package.navigationDistanceMeters, accuracy: 0.5)
    }

    func testStartingMidRouteMatchesWhereTheRunnerIs() throws {
        let package = straightRoute(points: 200)
        let engine = RouteNavigationEngine(routePackage: package)
        let midPoint = package.route[package.route.count * 3 / 4]
        let update = try XCTUnwrap(engine.update(latitude: midPoint.latitude, longitude: midPoint.longitude, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3))
        XCTAssertFalse(update.isOffRoute)
        XCTAssertEqual(update.progressDistanceMeters, midPoint.distanceFromStartMeters, accuracy: 5)
    }

    func testFarOffRouteFixesDoNotAdvanceProgress() throws {
        let package = straightRoute()
        let engine = RouteNavigationEngine(routePackage: package)
        let start = package.route[0]
        _ = engine.update(latitude: start.latitude, longitude: start.longitude, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3)

        // 500 m east of a point far ahead on the route.
        let ahead = package.route[package.route.count - 5]
        let farAway = try XCTUnwrap(engine.update(latitude: ahead.latitude, longitude: ahead.longitude + 0.009, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3))
        XCTAssertTrue(farAway.isCriticallyOffRoute)
        XCTAssertLessThan(farAway.progressDistanceMeters, 10)

        // Rejoining ahead (a shortcut) does advance.
        let rejoin = try XCTUnwrap(engine.update(latitude: ahead.latitude, longitude: ahead.longitude, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3))
        XCTAssertEqual(rejoin.progressDistanceMeters, ahead.distanceFromStartMeters, accuracy: 5)
    }

    func testRestoreClampsStaleSegmentIndex() {
        let package = straightRoute(points: 10)
        let engine = RouteNavigationEngine(routePackage: package)
        engine.restoreState(PersistedNavigationEngineState(
            lastSegmentIndex: 10_000,
            lastProgressMeters: 1_000_000,
            completedTrack: [],
            actualTrack: []
        ))
        let last = package.route[package.route.count - 1]
        XCTAssertNotNil(engine.update(latitude: last.latitude, longitude: last.longitude, horizontalAccuracyMeters: 5, speedMetersPerSecond: 3))
    }
}

final class ElevationStatisticsTests: XCTestCase {
    func testQuantizationNoiseOnFlatRouteIsIgnored() {
        let noisy = (0..<500).map { $0.isMultiple(of: 2) ? 35.0 : 36.0 }
        let totals = ElevationStatistics.gainAndLoss(of: noisy, thresholdMeters: ElevationStatistics.routeThresholdMeters)
        XCTAssertEqual(totals.gain, 1, accuracy: 0.001) // only the net pending rise at the end
        XCTAssertLessThan(totals.loss, 1)
    }

    func testSteadyClimbIsFullyCounted() {
        let climb = stride(from: 100.0, through: 400.0, by: 0.5).map { $0 }
        let totals = ElevationStatistics.gainAndLoss(of: climb, thresholdMeters: 3)
        XCTAssertEqual(totals.gain, 300, accuracy: 0.001)
        XCTAssertEqual(totals.loss, 0, accuracy: 0.001)
    }

    func testNetChangeIsPreserved() {
        let profile: [Double] = [0, 2, 4, 2, 5, 1, 9, 8, 12]
        let totals = ElevationStatistics.gainAndLoss(of: profile, thresholdMeters: 3)
        XCTAssertEqual(totals.gain - totals.loss, 12, accuracy: 0.001)
    }

    func testAccumulatorIncludesPendingMovement() {
        var accumulator = ElevationAccumulator(thresholdMeters: 3)
        accumulator.add(100)
        accumulator.add(102)
        XCTAssertEqual(accumulator.committedGainMeters, 0)
        XCTAssertEqual(accumulator.totalGainMeters, 2)
        accumulator.add(104)
        XCTAssertEqual(accumulator.committedGainMeters, 4)
    }

    func testProfileDownsamplerKeepsEndpoints() {
        let values = Array(0..<10_000)
        let thinned = ProfileDownsampler.downsample(values, maxCount: 300)
        XCTAssertEqual(thinned.count, 300)
        XCTAssertEqual(thinned.first, 0)
        XCTAssertEqual(thinned.last, 9_999)
    }

    func testGPSDistanceIgnoresPauseGaps() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            TrackPoint(timestamp: start, latitude: 59.3000, longitude: 18.0, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: start.addingTimeInterval(10), latitude: 59.3005, longitude: 18.0, horizontalAccuracyMeters: 5),
            // Paused for ten minutes and moved 1 km by car.
            TrackPoint(timestamp: start.addingTimeInterval(610), latitude: 59.3095, longitude: 18.0, horizontalAccuracyMeters: 5),
            TrackPoint(timestamp: start.addingTimeInterval(620), latitude: 59.3100, longitude: 18.0, horizontalAccuracyMeters: 5)
        ]
        let distance = ActivityTrackStatistics.gpsDistanceMeters(from: points)
        XCTAssertEqual(distance, 111, accuracy: 3) // two 55 m legs, not the 1 km transfer
    }
}

final class OfflinePackPlanningTests: XCTestCase {
    func testCorridorIsMuchSmallerThanBoundingBoxForDiagonalRoutes() {
        // ~30 km diagonal line.
        let coordinates = (0...300).map {
            GeoCoordinate(latitude: 59.0 + Double($0) * 0.0007, longitude: 17.5 + Double($0) * 0.0013)
        }
        let route = makeRoute(coordinates)
        let corridor = OfflineTilePlanner.tiles(for: route, bufferMeters: 1500, minZoom: 13, maxZoom: 15)

        var boundingBoxCount = 0
        let box = MapMath.boundingBox(for: coordinates)!
        for zoom in 13...15 {
            let width = MapMath.tileX(longitude: box.maxLongitude, zoom: zoom) - MapMath.tileX(longitude: box.minLongitude, zoom: zoom) + 1
            let height = MapMath.tileY(latitude: box.minLatitude, zoom: zoom) - MapMath.tileY(latitude: box.maxLatitude, zoom: zoom) + 1
            boundingBoxCount += width * height
        }

        XCTAssertLessThan(corridor.count, boundingBoxCount / 2)

        // Every route point is covered at the most detailed zoom.
        let detailed = Set(corridor.filter { $0.zoom == 15 })
        for coordinate in coordinates {
            let tile = TileCoordinate(
                zoom: 15,
                x: MapMath.tileX(longitude: coordinate.longitude, zoom: 15),
                y: MapMath.tileY(latitude: coordinate.latitude, zoom: 15)
            )
            XCTAssertTrue(detailed.contains(tile))
        }
    }

    func testArchiveRejectsPathTraversal() {
        XCTAssertTrue(RoutePackaging.isSafeRelativePath("tiles/z13_x1_y2.png"))
        XCTAssertTrue(RoutePackaging.isSafeRelativePath("route.json"))
        XCTAssertFalse(RoutePackaging.isSafeRelativePath("../evil.json"))
        XCTAssertFalse(RoutePackaging.isSafeRelativePath("tiles/../../evil"))
        XCTAssertFalse(RoutePackaging.isSafeRelativePath("/etc/passwd"))
    }

    func testReinstallingRouteRemovesTilesOfOldPack() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let installRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: installRoot)
        }

        let route = makeRoute([
            GeoCoordinate(latitude: 59.30, longitude: 18.00),
            GeoCoordinate(latitude: 59.31, longitude: 18.01)
        ])
        let package = RoutePackage(
            id: UUID(), name: "R", sourceFileName: "r.gpx", importedAt: Date(), activityHint: .running,
            distanceMeters: 1_300, elevationGainMeters: nil, elevationLossMeters: nil,
            boundingBox: MapMath.boundingBox(for: route.map(\.coordinate))!,
            originalPointCount: 2, simplifiedPointCount: 2, route: route, cues: [], offlineMapManifest: nil
        )

        // Existing install with an old offline pack.
        let installed = try RoutePackaging.writeRoutePackage(package, to: installRoot)
        let oldTiles = installed.appendingPathComponent("tiles", isDirectory: true)
        try fileManager.createDirectory(at: oldTiles, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: oldTiles.appendingPathComponent("z15_x1_y1.png"))

        // The phone deletes the pack and re-sends the route.
        let source = try RoutePackaging.writeRoutePackage(package, to: root)
        let archive = RoutePackaging.makeArchiveURL(for: package, in: root)
        try RoutePackaging.zipRouteDirectory(source, to: archive)
        let reinstalled = try RoutePackaging.installArchive(at: archive, to: installRoot)

        XCTAssertFalse(fileManager.fileExists(atPath: reinstalled.appendingPathComponent("tiles").path))
    }
}

final class ActivityRouteSnapshotTests: XCTestCase {
    func testRecordedSnapshotWinsOverLaterEditedRoute() {
        let snapshot = makeRoute([
            GeoCoordinate(latitude: 59.30, longitude: 18.00),
            GeoCoordinate(latitude: 59.31, longitude: 18.00)
        ])
        let reversedLater = Array(snapshot.reversed())
        let recording = ActivityRecording(routeId: UUID(), routeName: "Loop", activityKind: .running, plannedRoutePoints: snapshot)
        let live = RoutePackage(
            id: recording.routeId, name: "Loop", sourceFileName: "loop.gpx", importedAt: Date(), activityHint: .running,
            distanceMeters: 1_100, elevationGainMeters: nil, elevationLossMeters: nil,
            boundingBox: MapMath.boundingBox(for: snapshot.map(\.coordinate))!,
            originalPointCount: 2, simplifiedPointCount: 2, route: reversedLater, cues: [], offlineMapManifest: nil
        )
        XCTAssertEqual(recording.resolvedPlannedRoutePoints(liveRoute: live), snapshot)
    }
}

final class LiveActivityTrackingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testClockCountsWallTimeAndExcludesPauses() {
        var clock = ActivityClock()
        clock.start(at: t0)
        clock.pause(at: t0.addingTimeInterval(600))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(900)), 600, accuracy: 0.001)
        clock.start(at: t0.addingTimeInterval(900))
        XCTAssertEqual(clock.elapsed(at: t0.addingTimeInterval(1_000)), 700, accuracy: 0.001)
    }

    func testLegacyPersistedStateKeepsRunningSinceSave() {
        let saved = PersistedActiveActivity(
            phase: "active",
            routeId: UUID(),
            activityKind: .running,
            recording: ActivityRecording(routeId: UUID(), routeName: "R", activityKind: .running),
            elapsedSeconds: 1_200,
            engineState: PersistedNavigationEngineState(lastSegmentIndex: 0, lastProgressMeters: 0, completedTrack: [], actualTrack: []),
            savedAt: t0
        )
        XCTAssertEqual(saved.resolvedClock.elapsed(at: t0.addingTimeInterval(30)), 1_230, accuracy: 0.001)
    }

    func testSpeedEstimatorSmoothsAndGoesStale() {
        var estimator = SpeedEstimator(timeConstantSeconds: 8, staleAfterSeconds: 15)
        estimator.add(speedMetersPerSecond: 3, at: t0)
        estimator.add(speedMetersPerSecond: 6, at: t0.addingTimeInterval(1)) // one noisy fix
        let smoothed = try! XCTUnwrap(estimator.current(at: t0.addingTimeInterval(1)))
        XCTAssertLessThan(smoothed, 3.5)
        XCTAssertNil(estimator.current(at: t0.addingTimeInterval(30)))
    }

    func testLiveStatisticsMatchSavedTrackStatistics() {
        let points = (0..<200).map { index in
            TrackPoint(
                timestamp: t0.addingTimeInterval(Double(index) * 5 + (index >= 100 ? 400 : 0)),
                latitude: 59.30 + Double(index) * 0.0001,
                longitude: 18.0,
                altitudeMeters: 20 + sin(Double(index) / 10) * 12,
                horizontalAccuracyMeters: 5
            )
        }
        var live = LiveTrackStatistics()
        points.forEach { live.add($0) }

        XCTAssertEqual(live.distanceMeters, ActivityTrackStatistics.gpsDistanceMeters(from: points), accuracy: 0.001)
        XCTAssertEqual(LiveTrackStatistics(rebuildingFrom: points).distanceMeters, live.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(
            live.elevationGainMeters ?? 0,
            ActivityTrackStatistics.elevationGainMeters(from: points, fallback: nil) ?? 0,
            accuracy: 0.001
        )
    }

    func testAlertsFireOncePerTurnAndOnRouteChanges() {
        let cue = RouteCue(
            id: UUID(), distanceFromStartMeters: 500, coordinate: GeoCoordinate(latitude: 59.3, longitude: 18),
            kind: .turnLeft, instruction: "Turn left", bearingBefore: 0, bearingAfter: 270
        )
        var tracker = NavigationAlertTracker()

        func snapshot(progress: Double, offRoute: Double = 0) -> NavigationSnapshot {
            NavigationSnapshot(
                routeId: UUID(), progressDistanceMeters: progress, distanceRemainingMeters: 2_000 - progress,
                offRouteDistanceMeters: offRoute, isOffRoute: offRoute > 25, isCriticallyOffRoute: offRoute > 50,
                nextCue: progress < 500 ? cue : nil, distanceToNextCueMeters: progress < 500 ? 500 - progress : nil,
                currentSpeedMetersPerSecond: 3, currentCoordinate: nil, completedTrack: [], updatedAt: t0
            )
        }

        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 300), activity: .running, speedMetersPerSecond: 3), [])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 470), activity: .running, speedMetersPerSecond: 3), [.approachingTurn(cue, distanceMeters: 30)])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 480), activity: .running, speedMetersPerSecond: 3), [])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 600, offRoute: 30), activity: .running, speedMetersPerSecond: 3), [.offRoute(distanceMeters: 30)])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 600, offRoute: 70), activity: .running, speedMetersPerSecond: 3), [.farOffRoute(distanceMeters: 70)])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 610), activity: .running, speedMetersPerSecond: 3), [.backOnRoute])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 1_990), activity: .running, speedMetersPerSecond: 3), [.arrived])
        XCTAssertEqual(tracker.alerts(for: snapshot(progress: 2_000), activity: .running, speedMetersPerSecond: 3), [])
    }
}

final class UnitFormattingTests: XCTestCase {
    private let space = "\u{00A0}"

    /// Numbers are formatted for the current locale, so build expectations the same way.
    private func number(_ value: Double, _ fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    func testMetricDistances() {
        XCTAssertEqual(RouteFormatting.distance(450, units: .metric), "\(number(450, 0))\(space)m")
        XCTAssertEqual(RouteFormatting.distance(12_345, units: .metric), "\(number(12.345, 1))\(space)km")
        XCTAssertEqual(RouteFormatting.distance(123_456, units: .metric), "\(number(123.456, 0))\(space)km")
    }

    func testImperialDistancesSwitchFromFeetToMilesAtATenthOfAMile() {
        XCTAssertEqual(RouteFormatting.distance(DisplayUnits.metersPerMile * 3.1, units: .imperial), "\(number(3.1, 1))\(space)mi")
        XCTAssertEqual(RouteFormatting.distance(100, units: .imperial), "\(number(328.084, 0))\(space)ft")
        XCTAssertTrue(RouteFormatting.distance(160, units: .imperial).hasSuffix("ft"))
        XCTAssertTrue(RouteFormatting.distance(161, units: .imperial).hasSuffix("mi"))
    }

    func testElevation() {
        XCTAssertEqual(RouteFormatting.elevation(1000, units: .metric), "\(number(1000, 0))\(space)m")
        XCTAssertEqual(RouteFormatting.elevation(1000, units: .imperial), "\(number(3280.84, 0))\(space)ft")
        XCTAssertEqual(RouteFormatting.elevation(nil, units: .imperial), "—")
    }

    func testPaceAndSpeed() {
        // 5:00 per kilometer is 8:03 per mile; 10 m/s is 36 km/h or 22.4 mph.
        XCTAssertEqual(RouteFormatting.pace(secondsPerKm: 300, units: .metric), "5:00\(space)/km")
        XCTAssertEqual(RouteFormatting.pace(secondsPerKm: 300, units: .imperial), "8:03\(space)/mi")
        XCTAssertEqual(RouteFormatting.speed(10, units: .metric), "\(number(36, 1))\(space)km/h")
        XCTAssertEqual(RouteFormatting.speed(10, units: .imperial), "\(number(22.369, 1))\(space)mph")
        XCTAssertEqual(RouteFormatting.speedOrPace(1000.0 / 300, mode: .pace, units: .imperial), "8:03\(space)/mi")
    }

    func testChartValuesUseDisplayUnits() {
        XCTAssertEqual(RouteFormatting.distanceValue(DisplayUnits.metersPerMile, units: .imperial), 1, accuracy: 1e-9)
        XCTAssertEqual(RouteFormatting.distanceValue(2500, units: .metric), 2.5, accuracy: 1e-9)
        XCTAssertEqual(RouteFormatting.elevationValue(304.8, units: .imperial), 1000, accuracy: 1e-9)
    }

    func testAutomaticFollowsTheRegion() {
        XCTAssertEqual(DisplayUnits(system: .automatic, locale: Locale(identifier: "en_US")), .imperial)
        XCTAssertEqual(DisplayUnits(system: .automatic, locale: Locale(identifier: "de_DE")), .metric)
        XCTAssertEqual(
            DisplayUnits(system: .automatic, locale: Locale(identifier: "en_GB")),
            DisplayUnits(distance: .miles, elevation: .meters)
        )
        XCTAssertEqual(DisplayUnits(system: .metric, locale: Locale(identifier: "en_US")), .metric)
        XCTAssertEqual(DisplayUnits(system: .imperial, locale: Locale(identifier: "sv_SE")), .imperial)
    }

    func testPreferenceIsStoredAndReloaded() throws {
        let suiteName = "UnitPreferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preference = UnitPreference(defaults: defaults)
        XCTAssertEqual(preference.system, .automatic)
        preference.system = .imperial
        XCTAssertEqual(UnitPreference(defaults: defaults).system, .imperial)

        // Another process (the app, for a widget) changes the stored value.
        defaults.set(UnitSystem.metric.rawValue, forKey: UnitPreference.storageKey)
        preference.reload()
        XCTAssertEqual(preference.system, .metric)
    }
}
