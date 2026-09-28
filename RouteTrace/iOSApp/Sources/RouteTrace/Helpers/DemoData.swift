#if DEBUG
import Foundation
import RouteTraceShared

/// Seeds routes and recorded activities for UI work and screenshots, since activities
/// otherwise only arrive from a real Apple Watch.
///
/// Launch with `-RouteTraceDemoData` (Scheme ▸ Run ▸ Arguments). Seeds only into an empty library.
@MainActor
enum DemoData {
    static let launchArgument = "-RouteTraceDemoData"

    static func seedIfRequested(into store: RouteStore) {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument),
              (try? store.fetchRoutes().isEmpty) == true else { return }

        var random = SeededRandom(seed: 42)
        let now = Date()

        let loop = makeRoute(
            name: "Djurgården Loop",
            fileName: "djurgarden-loop.gpx",
            activity: .running,
            importedAt: now.addingTimeInterval(-86_400 * 12),
            points: loopPoints(center: (59.3265, 18.1120), radiusMeters: 1_550, count: 420, random: &random) { fraction in
                12 + 18 * pow(sin(2 * .pi * fraction), 2) + 6 * sin(11 * .pi * fraction)
            },
            store: store
        )

        let trail = makeRoute(
            name: "Lac Blanc Trail",
            fileName: "komoot-lac-blanc.gpx",
            activity: .trailRunning,
            importedAt: now.addingTimeInterval(-86_400 * 5),
            points: pathPoints(start: (45.9237, 6.8694), bearing: 20, lengthMeters: 16_000, count: 520, wander: 0.22, random: &random) { fraction in
                1_040 + 980 * pow(sin(.pi * min(1, fraction * 1.15)), 1.6) + 35 * sin(23 * fraction)
            },
            store: store
        )

        _ = makeRoute(
            name: "Sörmland Gravel",
            fileName: "sormland-gravel.gpx",
            activity: .gravelCycling,
            importedAt: now.addingTimeInterval(-86_400 * 2),
            points: pathPoints(start: (59.2050, 17.6300), bearing: 215, lengthMeters: 62_000, count: 900, wander: 0.12, random: &random) { fraction in
                40 + 35 * sin(7 * .pi * fraction) + 20 * sin(19 * .pi * fraction)
            },
            store: store
        )

        if let loop {
            for (daysAgo, pace, hour) in [(1.0, 5.4, 7), (9.0, 5.7, 18), (33.0, 5.9, 12)] {
                let start = Calendar.current.date(
                    bySettingHour: hour, minute: 12, second: 0,
                    of: now.addingTimeInterval(-86_400 * daysAgo)
                ) ?? now
                recordActivity(on: loop, start: start, minutesPerKm: pace, detour: daysAgo == 9, random: &random, store: store)
            }
        }
        if let trail {
            let start = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: now.addingTimeInterval(-86_400 * 4)) ?? now
            recordActivity(on: trail, start: start, minutesPerKm: 9.5, detour: false, random: &random, store: store)
        }
    }

    // MARK: - Routes

    private static func makeRoute(
        name: String,
        fileName: String,
        activity: ActivityKind,
        importedAt: Date,
        points: [ParsedGPXPoint],
        store: RouteStore
    ) -> RoutePackage? {
        let parsed = ParsedGPX(
            metadataName: name,
            tracks: [ParsedGPXTrack(name: name, segments: [points])],
            routes: [],
            waypoints: [],
            warnings: [],
            invalidPointCount: 0
        )
        let processed = RouteProcessor().makeRoutePackage(from: parsed, sourceFileName: fileName, activityHint: activity)
        let package = RoutePackage(
            id: processed.id,
            name: processed.name,
            sourceFileName: fileName,
            importedAt: importedAt,
            activityHint: activity,
            distanceMeters: processed.distanceMeters,
            elevationGainMeters: processed.elevationGainMeters,
            elevationLossMeters: processed.elevationLossMeters,
            boundingBox: processed.boundingBox,
            originalPointCount: processed.originalPointCount,
            simplifiedPointCount: processed.simplifiedPointCount,
            route: processed.route,
            cues: processed.cues,
            offlineMapManifest: nil
        )
        guard (try? store.saveRoutePackage(package)) != nil else { return nil }
        try? GPXExporter.writeTrack(name: name, points: points, to: RouteTracePaths.sourceGPXURL(for: package.id))
        return package
    }

    private static func loopPoints(
        center: (Double, Double),
        radiusMeters: Double,
        count: Int,
        random: inout SeededRandom,
        elevation: (Double) -> Double
    ) -> [ParsedGPXPoint] {
        let phases = (0..<3).map { _ in random.next(in: 0...(2 * .pi)) }
        return (0...count).map { index in
            let t = 2 * .pi * Double(index) / Double(count)
            let radius = radiusMeters * (1 + 0.22 * (0.35 * sin(3 * t + phases[0]) + 0.25 * sin(5 * t + phases[1]) + 0.15 * sin(9 * t + phases[2])))
            let coordinate = offset(center, east: radius * cos(t), north: radius * sin(t))
            return ParsedGPXPoint(latitude: coordinate.0, longitude: coordinate.1, elevationMeters: elevation(Double(index) / Double(count)), timestamp: nil)
        }
    }

    private static func pathPoints(
        start: (Double, Double),
        bearing: Double,
        lengthMeters: Double,
        count: Int,
        wander: Double,
        random: inout SeededRandom,
        elevation: (Double) -> Double
    ) -> [ParsedGPXPoint] {
        var position = start
        var heading = bearing * .pi / 180
        let step = lengthMeters / Double(count)
        return (0...count).map { index in
            let point = ParsedGPXPoint(latitude: position.0, longitude: position.1, elevationMeters: elevation(Double(index) / Double(count)), timestamp: nil)
            heading += random.next(in: -wander...wander) + 0.02 * sin(Double(index) / 17)
            position = offset(position, east: step * sin(heading), north: step * cos(heading))
            return point
        }
    }

    // MARK: - Activities

    private static func recordActivity(
        on route: RoutePackage,
        start: Date,
        minutesPerKm: Double,
        detour: Bool,
        random: inout SeededRandom,
        store: RouteStore
    ) {
        let speed = 1000 / (minutesPerKm * 60)
        var trackPoints: [TrackPoint] = []
        var offRouteEvents: [OffRouteEvent] = []
        var elapsed: TimeInterval = 0
        var lastDistance = 0.0
        let detourRange = (route.navigationDistanceMeters * 0.55)...(route.navigationDistanceMeters * 0.6)

        for point in route.route where point.distanceFromStartMeters - lastDistance >= 12 || point.id == route.route.last?.id {
            let climb = max(0, (point.elevationMeters ?? 0) - (trackPoints.last?.altitudeMeters ?? point.elevationMeters ?? 0))
            elapsed += (point.distanceFromStartMeters - lastDistance) / speed + climb * 1.2
            lastDistance = point.distanceFromStartMeters

            var coordinate = offset((point.latitude, point.longitude), east: random.next(in: -3...3), north: random.next(in: -3...3))
            var offRoute: Double = 0
            if detour, detourRange.contains(point.distanceFromStartMeters) {
                offRoute = 60 * sin(.pi * (point.distanceFromStartMeters - detourRange.lowerBound) / (detourRange.upperBound - detourRange.lowerBound))
                coordinate = offset(coordinate, east: offRoute, north: 0)
            }

            let fatigue = elapsed / 3_600
            let heartRate = 128 + 22 * min(1, elapsed / 600) + 9 * fatigue + climb * 3 + random.next(in: -3...3)
            trackPoints.append(TrackPoint(
                timestamp: start.addingTimeInterval(elapsed),
                latitude: coordinate.0,
                longitude: coordinate.1,
                altitudeMeters: point.elevationMeters.map { $0 + random.next(in: -1.2...1.2) },
                horizontalAccuracyMeters: random.next(in: 4...9),
                speedMetersPerSecond: speed * random.next(in: 0.9...1.1),
                heartRateBPM: heartRate,
                snappedDistanceFromStartMeters: point.distanceFromStartMeters,
                offRouteDistanceMeters: offRoute
            ))
        }

        if detour, let middle = trackPoints.first(where: { ($0.offRouteDistanceMeters ?? 0) > 40 }) {
            offRouteEvents.append(OffRouteEvent(
                startedAt: middle.timestamp.addingTimeInterval(-40),
                endedAt: middle.timestamp.addingTimeInterval(55),
                maxDistanceMeters: 60,
                coordinate: middle.coordinate
            ))
        }

        let heartRates = trackPoints.compactMap(\.heartRateBPM)
        let recording = ActivityRecording(
            routeId: route.id,
            routeName: route.name,
            title: ActivityNaming.title(startedAt: start, activityKind: route.activityHint, routeName: route.name),
            startedAt: start,
            endedAt: start.addingTimeInterval(elapsed),
            activityKind: route.activityHint,
            trackPoints: trackPoints,
            totalDistanceMeters: route.navigationDistanceMeters,
            elapsedSeconds: elapsed,
            offRouteEvents: offRouteEvents,
            elevationGainMeters: route.elevationGainMeters,
            averageHeartRateBPM: heartRates.reduce(0, +) / Double(max(heartRates.count, 1)),
            plannedRoutePoints: route.route
        )
        _ = try? store.saveActivity(recording)
    }

    private static func offset(_ coordinate: (Double, Double), east: Double, north: Double) -> (Double, Double) {
        (
            coordinate.0 + north / 111_320,
            coordinate.1 + east / (111_320 * cos(coordinate.0 * .pi / 180))
        )
    }
}

/// SplitMix64, so demo data is identical on every launch.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
#endif
