import MapKit
import RouteTraceShared
import SwiftUI

enum ActiveRouteMapOverlay {
    static func routeCoordinates(_ route: RoutePackage) -> [CLLocationCoordinate2D] {
        route.route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    static func clLocation(_ coordinate: GeoCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    @MainActor
    static func actualTrackCoordinates(from viewModel: ActiveRouteViewModel) -> [CLLocationCoordinate2D] {
        if let snapshot = viewModel.navigationSnapshot, !snapshot.actualTrack.isEmpty {
            return snapshot.actualTrack.map(clLocation)
        }
        return viewModel.recording.trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    static func directionAnnotations(for route: RoutePackage, everyMeters: Double = 400) -> [DirectionAnnotation] {
        var results: [DirectionAnnotation] = []
        guard route.route.count >= 2 else { return results }

        var accumulated = 0.0
        var nextMark = everyMeters

        for index in 0 ..< (route.route.count - 1) {
            let start = route.route[index]
            let end = route.route[index + 1]
            let segmentLength = MapMath.haversineMeters(
                from: start.coordinate,
                to: end.coordinate
            )

            while accumulated + segmentLength >= nextMark {
                let ratio = (nextMark - accumulated) / max(segmentLength, 0.001)
                let lat = start.latitude + (end.latitude - start.latitude) * ratio
                let lon = start.longitude + (end.longitude - start.longitude) * ratio
                let bearing = MapMath.bearingDegrees(
                    from: GeoCoordinate(latitude: start.latitude, longitude: start.longitude),
                    to: GeoCoordinate(latitude: end.latitude, longitude: end.longitude)
                )
                results.append(DirectionAnnotation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), bearing: bearing))
                nextMark += everyMeters
            }
            accumulated += segmentLength
        }

        return results
    }
}

struct DirectionAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let bearing: Double
}
