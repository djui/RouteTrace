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
}
