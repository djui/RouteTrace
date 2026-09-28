import Foundation

public enum MapMath {
    private static let earthRadiusMeters = 6_371_000.0

    public static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    public static func haversineMeters(
        from start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLat = (end.latitude - start.latitude) * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    public static func bearingDegrees(from start: GeoCoordinate, to end: GeoCoordinate) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return normalizeBearing(degrees)
    }

    public static func normalizeBearing(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    public static func bearingDelta(from start: Double, to end: Double) -> Double {
        var delta = end - start
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    public static func boundingBox(for coordinates: [GeoCoordinate]) -> GeoBoundingBox? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        return GeoBoundingBox(
            minLatitude: minLat,
            maxLatitude: maxLat,
            minLongitude: minLon,
            maxLongitude: maxLon
        )
    }

    public struct NearestSegmentResult: Sendable {
        public let segmentIndex: Int
        public let projectedCoordinate: GeoCoordinate
        public let distanceMeters: Double
        public let distanceAlongRouteMeters: Double
    }

    /// Finds the closest point on the route within a window of segments.
    ///
    /// When `preferEarliestWithinMeters` is positive, the earliest segment whose distance is within
    /// that tolerance of the best match wins. This keeps matching continuous where a route passes the
    /// same place twice (loops, out-and-backs, figure eights) instead of jumping ahead.
    public static func nearestPointOnPolyline(
        to location: GeoCoordinate,
        route: [RoutePoint],
        searchStartIndex: Int = 0,
        searchWindow: Int = 80,
        preferEarliestWithinMeters: Double = 0
    ) -> NearestSegmentResult? {
        guard route.count >= 2 else { return nil }

        let start = min(max(0, searchStartIndex), route.count - 2)
        let end = min(route.count - 2, start + max(0, searchWindow))
        guard start <= end else { return nil }

        var candidates: [NearestSegmentResult] = []
        candidates.reserveCapacity(end - start + 1)
        var bestDistance = Double.greatestFiniteMagnitude

        for index in start...end {
            let a = route[index].coordinate
            let b = route[index + 1].coordinate
            let projection = project(point: location, ontoSegmentFrom: a, to: b)
            let distance = haversineMeters(from: location, to: projection.coordinate)
            let along = route[index].distanceFromStartMeters
                + projection.fraction * (route[index + 1].distanceFromStartMeters - route[index].distanceFromStartMeters)

            candidates.append(NearestSegmentResult(
                segmentIndex: index,
                projectedCoordinate: projection.coordinate,
                distanceMeters: distance,
                distanceAlongRouteMeters: along
            ))
            bestDistance = min(bestDistance, distance)
        }

        let tolerance = max(0, preferEarliestWithinMeters)
        if tolerance > 0 {
            return candidates.first { $0.distanceMeters <= bestDistance + tolerance }
        }
        return candidates.min { $0.distanceMeters < $1.distanceMeters }
    }

    private struct ProjectionResult {
        let coordinate: GeoCoordinate
        let fraction: Double
    }

    /// Shortest distance from `point` to the segment `start`–`end`.
    public static func distanceMeters(
        from point: GeoCoordinate,
        toSegmentFrom start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> Double {
        haversineMeters(from: point, to: project(point: point, ontoSegmentFrom: start, to: end).coordinate)
    }

    /// Projects `point` onto the segment in a local equirectangular frame.
    ///
    /// Longitude degrees shrink with `cos(latitude)`; projecting in raw degrees skews the foot
    /// point (e.g. by ~2x in longitude at 60°N), which inflates off-route distances.
    private static func project(
        point: GeoCoordinate,
        ontoSegmentFrom start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> ProjectionResult {
        let longitudeScale = cos(((start.latitude + end.latitude) / 2) * .pi / 180)
        let dx = (end.longitude - start.longitude) * longitudeScale
        let dy = end.latitude - start.latitude
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return ProjectionResult(coordinate: start, fraction: 0)
        }

        let px = (point.longitude - start.longitude) * longitudeScale
        let py = point.latitude - start.latitude
        let t = max(0, min(1, (px * dx + py * dy) / lengthSquared))

        return ProjectionResult(
            coordinate: GeoCoordinate(
                latitude: start.latitude + t * (end.latitude - start.latitude),
                longitude: start.longitude + t * (end.longitude - start.longitude)
            ),
            fraction: t
        )
    }

    // MARK: - Tile math (Web Mercator)

    public static func tileX(longitude: Double, zoom: Int) -> Int {
        let n = pow(2.0, Double(zoom))
        return Int(floor((longitude + 180.0) / 360.0 * n))
    }

    public static func tileY(latitude: Double, zoom: Int) -> Int {
        let n = pow(2.0, Double(zoom))
        let latRad = latitude * .pi / 180
        return Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
    }

    public static func tileBounds(x: Int, y: Int, zoom: Int) -> GeoBoundingBox {
        let n = pow(2.0, Double(zoom))
        let lonMin = Double(x) / n * 360.0 - 180.0
        let lonMax = Double(x + 1) / n * 360.0 - 180.0
        let latMax = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n))) * 180.0 / .pi
        let latMin = atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n))) * 180.0 / .pi
        return GeoBoundingBox(minLatitude: latMin, maxLatitude: latMax, minLongitude: lonMin, maxLongitude: lonMax)
    }

    public static func coordinateToPixel(
        coordinate: GeoCoordinate,
        tileX: Int,
        tileY: Int,
        zoom: Int,
        tileSize: Int = 256
    ) -> (x: Double, y: Double) {
        let bounds = tileBounds(x: tileX, y: tileY, zoom: zoom)
        let x = (coordinate.longitude - bounds.minLongitude) / (bounds.maxLongitude - bounds.minLongitude) * Double(tileSize)
        let y = (bounds.maxLatitude - coordinate.latitude) / (bounds.maxLatitude - bounds.minLatitude) * Double(tileSize)
        return (x, y)
    }

    // MARK: - Web Mercator world coordinates

    /// Earth circumference used by Web Mercator tiles.
    public static let webMercatorEquatorMeters = 40_075_016.686

    /// Position in "tile units" at `zoom` (tile x/y as fractional numbers).
    public static func tileUnits(for coordinate: GeoCoordinate, zoom: Double) -> (x: Double, y: Double) {
        let n = pow(2.0, zoom)
        let clampedLatitude = max(-85.05112878, min(85.05112878, coordinate.latitude))
        let latRad = clampedLatitude * .pi / 180
        let x = (coordinate.longitude + 180.0) / 360.0 * n
        let y = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n
        return (x, y)
    }

    /// Inverse of `tileUnits(for:zoom:)`.
    public static func coordinate(fromTileUnits x: Double, _ y: Double, zoom: Double) -> GeoCoordinate {
        let n = pow(2.0, zoom)
        let longitude = x / n * 360.0 - 180.0
        let latitude = atan(sinh(.pi * (1.0 - 2.0 * y / n))) * 180.0 / .pi
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    /// Ground length covered by one tile edge at `zoom` near `latitude`.
    public static func tileSizeMeters(atLatitude latitude: Double, zoom: Double) -> Double {
        webMercatorEquatorMeters * cos(latitude * .pi / 180) / pow(2.0, zoom)
    }

    /// Continuous zoom at which `visibleMeters` of ground span `viewPoints`, given tiles drawn `tileSidePoints` wide.
    public static func zoomLevel(
        showingMeters visibleMeters: Double,
        acrossPoints viewPoints: Double,
        tileSidePoints: Double,
        latitude: Double
    ) -> Double {
        guard visibleMeters > 0, viewPoints > 0, tileSidePoints > 0 else { return 0 }
        let metersPerPoint = visibleMeters / viewPoints
        let tileMetersAtZoomZero = webMercatorEquatorMeters * cos(latitude * .pi / 180)
        return log2(tileMetersAtZoomZero / (metersPerPoint * tileSidePoints))
    }
}
