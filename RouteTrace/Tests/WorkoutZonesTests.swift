import XCTest
@testable import RouteTraceShared

final class WorkoutZonesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func heartRateZones(seconds: [Double] = []) throws -> WorkoutZones {
        try XCTUnwrap(WorkoutZones(
            metric: .heartRate,
            boundaries: [120, 140, 160, 175],
            secondsInZone: seconds,
            source: .system
        ))
    }

    /// One point every `spacingSeconds`, about 11 m apart, with the given heart rates.
    private func track(_ heartRates: [Double?], from startOffset: TimeInterval = 0, spacingSeconds: TimeInterval = 5) -> [TrackPoint] {
        heartRates.enumerated().map { index, bpm in
            TrackPoint(
                timestamp: start.addingTimeInterval(startOffset + Double(index) * spacingSeconds),
                latitude: 48 + Double(index) * 0.0001,
                longitude: 11,
                horizontalAccuracyMeters: 5,
                heartRateBPM: bpm
            )
        }
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: - Zones

    func testZoneIndexCountsBoundaryReadingsInTheZoneAbove() throws {
        let zones = try heartRateZones()
        XCTAssertEqual(zones.zoneCount, 5)
        XCTAssertEqual(zones.zoneIndex(for: 90), 0)
        XCTAssertEqual(zones.zoneIndex(for: 119.9), 0)
        XCTAssertEqual(zones.zoneIndex(for: 120), 1)
        XCTAssertEqual(zones.zoneIndex(for: 159), 2)
        XCTAssertEqual(zones.zoneIndex(for: 175), 4)
        XCTAssertEqual(zones.zoneIndex(for: 210), 4)
    }

    func testRejectsEmptyUnorderedOrNonFiniteBoundaries() {
        XCTAssertNil(WorkoutZones(metric: .heartRate, boundaries: []))
        XCTAssertNil(WorkoutZones(metric: .heartRate, boundaries: [140, 120]))
        XCTAssertNil(WorkoutZones(metric: .heartRate, boundaries: [120, 120]))
        XCTAssertNil(WorkoutZones(metric: .heartRate, boundaries: [.nan]))
    }

    func testDurationsMatchZoneCount() throws {
        XCTAssertEqual(try heartRateZones(seconds: [60, 30]).secondsInZone, [60, 30, 0, 0, 0])
        XCTAssertEqual(try heartRateZones(seconds: [1, 2, 3, 4, 5, 6]).secondsInZone, [1, 2, 3, 4, 5])
        XCTAssertEqual(try heartRateZones(seconds: [-5, .infinity]).secondsInZone, [0, 0, 0, 0, 0])
    }

    func testFractionsAndDominantZone() throws {
        let zones = try heartRateZones(seconds: [60, 180, 120, 0, 0])
        XCTAssertEqual(zones.totalSeconds, 360)
        XCTAssertEqual(zones.fraction(ofZone: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(zones.fraction(ofZone: 9), 0)
        XCTAssertEqual(zones.dominantZoneIndex, 1)
        XCTAssertNil(try heartRateZones().dominantZoneIndex)
    }

    func testRangeLabelsDoNotOverlap() throws {
        let zones = try heartRateZones()
        XCTAssertEqual(zones.rangeLabel(ofZone: 0), "< 120")
        XCTAssertEqual(zones.rangeLabel(ofZone: 1), "120–139")
        XCTAssertEqual(zones.rangeLabel(ofZone: 3), "160–174")
        XCTAssertEqual(zones.rangeLabel(ofZone: 4), "≥ 175")
        XCTAssertEqual(WorkoutZones.name(ofZone: 0), "Zone 1")
    }

    func testMetricsFollowActivityKind() {
        XCTAssertEqual(WorkoutZoneMetric.metrics(for: .trailRunning), [.heartRate])
        XCTAssertEqual(WorkoutZoneMetric.metrics(for: .gravelCycling), [.heartRate, .cyclingPower])
    }

    func testPaletteRunsFromBlueToRedForAnyZoneCount() {
        let first = WorkoutZonePalette.rgb(forZone: 0, of: 5)
        let last = WorkoutZonePalette.rgb(forZone: 4, of: 5)
        XCTAssertGreaterThan(first.blue, first.red)
        XCTAssertGreaterThan(last.red, last.blue)

        let seven = (0..<7).map { WorkoutZonePalette.rgb(forZone: $0, of: 7) }
        XCTAssertEqual(seven[0].blue, first.blue, accuracy: 0.0001)
        XCTAssertEqual(seven[6].red, last.red, accuracy: 0.0001)
        XCTAssertEqual(Set(seven.map { "\($0.red)|\($0.green)|\($0.blue)" }).count, 7)
    }

    // MARK: - Persistence

    func testZonesRoundTripThroughActivityRecording() throws {
        let zones = try heartRateZones(seconds: [60, 180, 120, 30, 0])
        let recording = ActivityRecording(routeId: UUID(), routeName: "Loop", activityKind: .running, workoutZones: [zones])

        let decoded = try RouteTracePayloadCoding.decode(ActivityRecording.self, from: RouteTracePayloadCoding.encode(recording))

        XCTAssertEqual(decoded.workoutZones(for: .heartRate), zones)
        XCTAssertNil(decoded.workoutZones(for: .cyclingPower))
    }

    func testRecordingWithoutZonesStillDecodes() throws {
        let legacyJSON = """
        {"activityKind":"running","elapsedSeconds":0,"id":"\(UUID().uuidString)","offRouteEvents":[],"routeId":"\(UUID().uuidString)","routeName":"Loop","startedAt":"2026-07-05T12:00:00Z","totalDistanceMeters":0,"trackPoints":[]}
        """
        let decoded = try RouteTracePayloadCoding.decode(ActivityRecording.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.workoutZones)
    }

    func testDecodingRejectsUnorderedBoundaries() {
        let json = #"{"boundaries":[140,120],"metric":"heartRate","secondsInZone":[1,2,3]}"#
        XCTAssertThrowsError(try RouteTracePayloadCoding.decode(WorkoutZones.self, from: Data(json.utf8)))
    }

    func testActivityEntityKeepsZonesFromRecording() throws {
        let zones = try heartRateZones(seconds: [60, 180, 120, 30, 0])
        let recording = ActivityRecording(routeId: UUID(), routeName: "Loop", activityKind: .running, workoutZones: [zones])

        let entity = ActivityEntity.from(recording)

        XCTAssertEqual(try entity.decodedRecording()?.workoutZones, [zones])
    }

    // MARK: - Zoned track

    func testTrackSplitsWhereZoneChanges() throws {
        let points = track(Array(repeating: 110, count: 12) + Array(repeating: 130, count: 12) + Array(repeating: 150, count: 12))

        let segments = ZonedTrackSegmenter.segments(from: points, zones: try heartRateZones())

        XCTAssertEqual(segments.map(\.zoneIndex), [0, 1, 2])
        XCTAssertFalse(segments.contains(where: \.isGapConnector))
        XCTAssertEqual(segments[1].coordinates.first, segments[0].coordinates.last)
        XCTAssertEqual(segments[2].coordinates.first, segments[1].coordinates.last)
        XCTAssertEqual(segments[2].coordinates.last, points.last?.coordinate)
    }

    func testBriefExcursionKeepsSurroundingZone() throws {
        let points = track(Array(repeating: 130, count: 12) + [141, 141] + Array(repeating: 130, count: 12))

        let segments = ZonedTrackSegmenter.segments(from: points, zones: try heartRateZones())

        XCTAssertEqual(segments.map(\.zoneIndex), [1])
        XCTAssertEqual(segments[0].coordinates.count, points.count)
    }

    func testMissingReadingsKeepThePreviousZone() throws {
        let points = track(Array(repeating: 130, count: 12) + Array(repeating: nil, count: 6) + Array(repeating: 130, count: 12))

        let segments = ZonedTrackSegmenter.segments(from: points, zones: try heartRateZones())

        XCTAssertEqual(segments.map(\.zoneIndex), [1])
    }

    func testTrackBeforeFirstReadingHasNoZoneUnlessBrief() throws {
        let zones = try heartRateZones()

        let brief = ZonedTrackSegmenter.segments(from: track([nil, nil, nil] + Array(repeating: 130, count: 12)), zones: zones)
        XCTAssertEqual(brief.map(\.zoneIndex), [1])

        let long = ZonedTrackSegmenter.segments(from: track(Array(repeating: nil, count: 10) + Array(repeating: 130, count: 12)), zones: zones)
        XCTAssertEqual(long.map(\.zoneIndex), [nil, 1])
    }

    func testRecordingGapGetsAConnector() throws {
        let points = track(Array(repeating: 130, count: 12)) + track(Array(repeating: 150, count: 12), from: 200)

        let segments = ZonedTrackSegmenter.segments(from: points, zones: try heartRateZones())

        XCTAssertEqual(segments.map(\.isGapConnector), [false, true, false])
        XCTAssertEqual(segments.map(\.zoneIndex), [1, nil, 2])
    }

    // MARK: - Zone alerts

    func testFirstSettledZoneIsNotAnnounced() {
        var policy = ZoneChangeAlertPolicy(dwellSeconds: 20, cooldownSeconds: 60)

        XCTAssertNil(policy.update(zoneIndex: 1, at: at(0)))
        XCTAssertNil(policy.update(zoneIndex: 1, at: at(25)))
        XCTAssertNil(policy.update(zoneIndex: 2, at: at(30)))
        XCTAssertNil(policy.update(zoneIndex: 2, at: at(45)))
        XCTAssertEqual(policy.update(zoneIndex: 2, at: at(50)), .up(toZone: 2))
        XCTAssertNil(policy.update(zoneIndex: 2, at: at(55)))
    }

    func testBriefExcursionIsNotAnnounced() {
        var policy = ZoneChangeAlertPolicy(dwellSeconds: 20, cooldownSeconds: 60)
        _ = policy.update(zoneIndex: 1, at: at(0))
        _ = policy.update(zoneIndex: 1, at: at(20))

        for second in stride(from: 30.0, through: 40, by: 5) {
            XCTAssertNil(policy.update(zoneIndex: 2, at: at(second)))
        }
        for second in stride(from: 41.0, through: 90, by: 7) {
            XCTAssertNil(policy.update(zoneIndex: 1, at: at(second)))
        }
    }

    func testChangeDuringCooldownIsAnnouncedAfterIt() {
        var policy = ZoneChangeAlertPolicy(dwellSeconds: 20, cooldownSeconds: 60)
        _ = policy.update(zoneIndex: 1, at: at(0))
        _ = policy.update(zoneIndex: 1, at: at(20))
        _ = policy.update(zoneIndex: 2, at: at(21))
        XCTAssertEqual(policy.update(zoneIndex: 2, at: at(41)), .up(toZone: 2))

        _ = policy.update(zoneIndex: 3, at: at(45))
        XCTAssertNil(policy.update(zoneIndex: 3, at: at(65)))
        XCTAssertNil(policy.update(zoneIndex: 3, at: at(90)))
        XCTAssertEqual(policy.update(zoneIndex: 3, at: at(101)), .up(toZone: 3))
    }

    func testChangeWaitsWhileAnotherHapticPlays() {
        var policy = ZoneChangeAlertPolicy(dwellSeconds: 20, cooldownSeconds: 60)
        _ = policy.update(zoneIndex: 1, at: at(0))
        _ = policy.update(zoneIndex: 1, at: at(20))
        _ = policy.update(zoneIndex: 0, at: at(30))

        XCTAssertNil(policy.update(zoneIndex: 0, at: at(50), canAlert: false))
        XCTAssertEqual(policy.update(zoneIndex: 0, at: at(52)), .down(toZone: 0))
    }

    func testLostReadingRestartsTheDwell() {
        var policy = ZoneChangeAlertPolicy(dwellSeconds: 20, cooldownSeconds: 60)
        _ = policy.update(zoneIndex: 1, at: at(0))
        _ = policy.update(zoneIndex: 1, at: at(20))
        _ = policy.update(zoneIndex: 2, at: at(30))
        _ = policy.update(zoneIndex: nil, at: at(40))
        _ = policy.update(zoneIndex: 2, at: at(45))

        XCTAssertNil(policy.update(zoneIndex: 2, at: at(60)))
        XCTAssertEqual(policy.update(zoneIndex: 2, at: at(65)), .up(toZone: 2))
    }
}
