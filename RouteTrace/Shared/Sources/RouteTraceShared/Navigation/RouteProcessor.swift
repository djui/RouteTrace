import Foundation

public struct RouteProcessor {
    public init() {}

    public func makeRoutePackage(
        from parsed: ParsedGPX,
        sourceFileName: String,
        activityHint: ActivityKind,
        customName: String? = nil
    ) -> RoutePackage {
        let rawPoints = parsed.primaryTrackPoints
        let validPoints = rawPoints.filter {
            MapMath.isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }

        let fullRoute = buildRoutePoints(from: validPoints)
        let simplified = simplify(route: fullRoute, toleranceMeters: activityHint.simplificationToleranceMeters)
        let cues = RouteCueGenerator().generate(route: simplified)
        let (gain, loss) = elevationStats(for: fullRoute)
        let coordinates = fullRoute.map(\.coordinate)
        let boundingBox = MapMath.boundingBox(for: coordinates) ?? GeoBoundingBox(
            minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0
        )

        let name = customName
            ?? parsed.tracks.first?.name
            ?? parsed.routes.first?.name
            ?? parsed.metadataName
            ?? sourceFileName.replacingOccurrences(of: ".gpx", with: "")

        return RoutePackage(
            id: UUID(),
            name: name,
            sourceFileName: sourceFileName,
            importedAt: Date(),
            activityHint: activityHint,
            distanceMeters: fullRoute.last?.distanceFromStartMeters ?? 0,
            elevationGainMeters: gain,
            elevationLossMeters: loss,
            boundingBox: boundingBox,
            originalPointCount: validPoints.count,
            simplifiedPointCount: simplified.count,
            route: simplified,
            cues: cues,
            offlineMapManifest: nil
        )
    }

    public func reprocessPackage(
        _ existing: RoutePackage,
        parsed: ParsedGPX,
        activityHint: ActivityKind
    ) -> RoutePackage {
        let rawPoints = parsed.primaryTrackPoints
        let validPoints = rawPoints.filter {
            MapMath.isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }

        let fullRoute = buildRoutePoints(from: validPoints)
        let simplified = simplify(route: fullRoute, toleranceMeters: activityHint.simplificationToleranceMeters)
        let cues = RouteCueGenerator().generate(route: simplified)
        let (gain, loss) = elevationStats(for: fullRoute)
        let coordinates = fullRoute.map(\.coordinate)
        let boundingBox = MapMath.boundingBox(for: coordinates) ?? existing.boundingBox

        return RoutePackage(
            id: existing.id,
            name: existing.name,
            sourceFileName: existing.sourceFileName,
            importedAt: existing.importedAt,
            activityHint: activityHint,
            distanceMeters: fullRoute.last?.distanceFromStartMeters ?? 0,
            elevationGainMeters: gain,
            elevationLossMeters: loss,
            boundingBox: boundingBox,
            originalPointCount: validPoints.count,
            simplifiedPointCount: simplified.count,
            route: simplified,
            cues: cues,
            offlineMapManifest: nil
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
