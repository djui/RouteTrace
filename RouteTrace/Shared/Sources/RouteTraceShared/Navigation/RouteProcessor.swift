import Foundation

public struct RouteProcessor {
    public init() {}

    public func makeRoutePackage(
        from parsed: ParsedGPX,
        sourceFileName: String,
        activityHint: ActivityKind,
        customName: String? = nil,
        reverseDirection: Bool = false
    ) -> RoutePackage {
        let rawPoints = parsed.primaryTrackPoints
        let validPoints = rawPoints.filter {
            MapMath.isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let orderedPoints = reverseDirection ? Array(validPoints.reversed()) : validPoints

        let name = customName
            ?? parsed.importName
            ?? sourceFileName.replacingOccurrences(of: ".gpx", with: "")

        return buildRoutePackage(
            id: UUID(),
            name: name,
            sourceFileName: sourceFileName,
            importedAt: Date(),
            activityHint: activityHint,
            points: orderedPoints,
            offlineMapManifest: nil
        )
    }

    public func reprocessPackage(
        _ existing: RoutePackage,
        parsed: ParsedGPX,
        activityHint: ActivityKind,
        reverseDirection: Bool = false
    ) -> RoutePackage {
        let rawPoints = parsed.primaryTrackPoints
        let validPoints = rawPoints.filter {
            MapMath.isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let orderedPoints = reverseDirection ? Array(validPoints.reversed()) : validPoints

        return buildRoutePackage(
            id: existing.id,
            name: existing.name,
            sourceFileName: existing.sourceFileName,
            importedAt: existing.importedAt,
            activityHint: activityHint,
            points: orderedPoints,
            offlineMapManifest: nil,
            fallbackBoundingBox: existing.boundingBox
        )
    }

    public func reversePackage(_ existing: RoutePackage) -> RoutePackage {
        let points = existing.route.map {
            ParsedGPXPoint(
                latitude: $0.latitude,
                longitude: $0.longitude,
                elevationMeters: $0.elevationMeters,
                timestamp: nil
            )
        }
        let orderedPoints = Array(points.reversed())

        return buildRoutePackage(
            id: existing.id,
            name: existing.name,
            sourceFileName: existing.sourceFileName,
            importedAt: existing.importedAt,
            activityHint: existing.activityHint,
            points: orderedPoints,
            offlineMapManifest: nil,
            fallbackBoundingBox: existing.boundingBox
        )
    }

    private func buildRoutePackage(
        id: UUID,
        name: String,
        sourceFileName: String,
        importedAt: Date,
        activityHint: ActivityKind,
        points: [ParsedGPXPoint],
        offlineMapManifest: OfflineMapManifest?,
        fallbackBoundingBox: GeoBoundingBox? = nil
    ) -> RoutePackage {
        let fullRoute = buildRoutePoints(from: points)
        let simplified = simplify(route: fullRoute, toleranceMeters: activityHint.simplificationToleranceMeters)
        let navigationRoute = densify(
            route: simplified,
            maxSegmentMeters: activityHint.navigationDensifyMaxSegmentMeters
        )
        let cues = RouteCueGenerator().generate(route: simplified)
        let (gain, loss) = elevationStats(for: fullRoute)
        let coordinates = fullRoute.map(\.coordinate)
        let boundingBox = MapMath.boundingBox(for: coordinates)
            ?? fallbackBoundingBox
            ?? GeoBoundingBox(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)

        let navigationWarning = RouteNavigationQuality.warning(
            distanceMeters: fullRoute.last?.distanceFromStartMeters ?? 0,
            originalPointCount: points.count,
            simplifiedPointCount: simplified.count
        )

        return RoutePackage(
            id: id,
            name: name,
            sourceFileName: sourceFileName,
            importedAt: importedAt,
            activityHint: activityHint,
            distanceMeters: fullRoute.last?.distanceFromStartMeters ?? 0,
            elevationGainMeters: gain,
            elevationLossMeters: loss,
            boundingBox: boundingBox,
            originalPointCount: points.count,
            simplifiedPointCount: simplified.count,
            route: navigationRoute,
            cues: cues,
            offlineMapManifest: offlineMapManifest,
            navigationWarning: navigationWarning
        )
    }

    private func buildRoutePoints(from points: [ParsedGPXPoint]) -> [RoutePoint] {
        var route: [RoutePoint] = []
        var cumulative = 0.0

        for (index, point) in points.enumerated() {
            let coordinate = GeoCoordinate(latitude: point.latitude, longitude: point.longitude)
            if let previous = route.last {
                cumulative += MapMath.haversineMeters(from: previous.coordinate, to: coordinate)
            }

            let bearing: Double?
            if index + 1 < points.count {
                let next = GeoCoordinate(latitude: points[index + 1].latitude, longitude: points[index + 1].longitude)
                bearing = MapMath.bearingDegrees(from: coordinate, to: next)
            } else {
                bearing = route.last?.bearingDegrees
            }

            route.append(
                RoutePoint(
                    id: index,
                    latitude: point.latitude,
                    longitude: point.longitude,
                    elevationMeters: point.elevationMeters,
                    distanceFromStartMeters: cumulative,
                    bearingDegrees: bearing
                )
            )
        }

        return route
    }

    private func elevationStats(for route: [RoutePoint]) -> (gain: Double?, loss: Double?) {
        let elevations = route.compactMap(\.elevationMeters)
        guard elevations.count >= 2 else { return (nil, nil) }

        var gain = 0.0
        var loss = 0.0
        for index in 1..<elevations.count {
            let delta = elevations[index] - elevations[index - 1]
            if delta > 0 { gain += delta } else { loss += abs(delta) }
        }
        return (gain, loss)
    }

    public func simplify(route: [RoutePoint], toleranceMeters: Double) -> [RoutePoint] {
        guard route.count > 2 else { return route }
        let indices = ramerDouglasPeucker(route: route, toleranceMeters: toleranceMeters)
        return indices.sorted().map { route[$0] }
    }

    public func densify(route: [RoutePoint], maxSegmentMeters: Double) -> [RoutePoint] {
        guard route.count >= 2, maxSegmentMeters > 0 else { return route }

        var densifiedPoints: [ParsedGPXPoint] = []

        for index in 0 ..< (route.count - 1) {
            let start = route[index]
            let end = route[index + 1]
            densifiedPoints.append(
                ParsedGPXPoint(
                    latitude: start.latitude,
                    longitude: start.longitude,
                    elevationMeters: start.elevationMeters,
                    timestamp: nil
                )
            )

            let segmentLength = MapMath.haversineMeters(from: start.coordinate, to: end.coordinate)
            guard segmentLength > maxSegmentMeters else { continue }

            let interpolationSteps = Int(ceil(segmentLength / maxSegmentMeters))
            guard interpolationSteps > 1 else { continue }

            for step in 1 ..< interpolationSteps {
                let fraction = Double(step) / Double(interpolationSteps)
                let latitude = start.latitude + (end.latitude - start.latitude) * fraction
                let longitude = start.longitude + (end.longitude - start.longitude) * fraction
                let elevationMeters: Double?
                if let startElevation = start.elevationMeters, let endElevation = end.elevationMeters {
                    elevationMeters = startElevation + (endElevation - startElevation) * fraction
                } else {
                    elevationMeters = nil
                }

                densifiedPoints.append(
                    ParsedGPXPoint(
                        latitude: latitude,
                        longitude: longitude,
                        elevationMeters: elevationMeters,
                        timestamp: nil
                    )
                )
            }
        }

        if let last = route.last {
            densifiedPoints.append(
                ParsedGPXPoint(
                    latitude: last.latitude,
                    longitude: last.longitude,
                    elevationMeters: last.elevationMeters,
                    timestamp: nil
                )
            )
        }

        return buildRoutePoints(from: densifiedPoints)
    }

    private func ramerDouglasPeucker(route: [RoutePoint], toleranceMeters: Double) -> Set<Int> {
        guard route.count > 2 else { return Set(route.indices) }

        var keep: Set<Int> = [0, route.count - 1]
        var stack: [(Int, Int)] = [(0, route.count - 1)]

        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var maxDistance = 0.0
            var index = start

            let a = route[start].coordinate
            let b = route[end].coordinate

            for i in (start + 1)..<end {
                let point = route[i].coordinate
                let projection = MapMath.nearestPointOnPolyline(
                    to: point,
                    route: [
                        RoutePoint(id: 0, latitude: a.latitude, longitude: a.longitude, elevationMeters: nil, distanceFromStartMeters: 0, bearingDegrees: nil),
                        RoutePoint(id: 1, latitude: b.latitude, longitude: b.longitude, elevationMeters: nil, distanceFromStartMeters: 1, bearingDegrees: nil)
                    ]
                )
                let distance = projection?.distanceMeters ?? 0
                if distance > maxDistance {
                    maxDistance = distance
                    index = i
                }
            }

            if maxDistance > toleranceMeters {
                keep.insert(index)
                stack.append((start, index))
                stack.append((index, end))
            }
        }

        return keep
    }
}
