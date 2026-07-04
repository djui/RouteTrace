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

    public static func nearestPointOnPolyline(
        to location: GeoCoordinate,
        route: [RoutePoint],
        searchStartIndex: Int = 0,
        searchWindow: Int = 80
    ) -> NearestSegmentResult? {
        guard route.count >= 2 else { return nil }

        let start = max(0, searchStartIndex)
        let end = min(route.count - 2, start + searchWindow)
        var best: NearestSegmentResult?

        for index in start...end {
            let a = route[index].coordinate
            let b = route[index + 1].coordinate
            let projection = project(point: location, ontoSegmentFrom: a, to: b)
            let distance = haversineMeters(from: location, to: projection.coordinate)
            let along = route[index].distanceFromStartMeters + projection.fraction * segmentLengthMeters(from: a, to: b)

            if best == nil || distance < best!.distanceMeters {
                best = NearestSegmentResult(
                    segmentIndex: index,
                    projectedCoordinate: projection.coordinate,
                    distanceMeters: distance,
                    distanceAlongRouteMeters: along
                )
            }
        }

        return best
    }

    private static func segmentLengthMeters(from start: GeoCoordinate, to end: GeoCoordinate) -> Double {
        haversineMeters(from: start, to: end)
    }

    private struct ProjectionResult {
        let coordinate: GeoCoordinate
        let fraction: Double
    }

    private static func project(
        point: GeoCoordinate,
        ontoSegmentFrom start: GeoCoordinate,
        to end: GeoCoordinate
    ) -> ProjectionResult {
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude

        if dx == 0 && dy == 0 {
            return ProjectionResult(coordinate: start, fraction: 0)
        }

        let t = max(
            0,
            min(
                1,
                ((point.longitude - start.longitude) * dx + (point.latitude - start.latitude) * dy)
                    / (dx * dx + dy * dy)
            )
        )

        return ProjectionResult(
            coordinate: GeoCoordinate(
                latitude: start.latitude + t * dy,
                longitude: start.longitude + t * dx
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
}
