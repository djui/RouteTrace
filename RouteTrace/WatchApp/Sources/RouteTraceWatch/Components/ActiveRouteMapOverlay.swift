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

    static func splitRouteCoordinates(
        _ route: RoutePackage,
        atProgressMeters progress: Double
    ) -> (traveled: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
        let points = route.route
        guard points.count >= 2 else {
            let coords = routeCoordinates(route)
            return progress > 0 ? (coords, []) : ([], coords)
        }

        var traveled: [CLLocationCoordinate2D] = []
        var remaining: [CLLocationCoordinate2D] = []
        var foundSplit = false

        for index in 0 ..< (points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let segStart = start.distanceFromStartMeters
            let segEnd = end.distanceFromStartMeters

            if !foundSplit {
                if progress >= segEnd {
                    traveled.append(clLocation(start.coordinate))
                } else if progress > segStart {
                    let ratio = (progress - segStart) / max(0.001, segEnd - segStart)
                    let lat = start.latitude + (end.latitude - start.latitude) * ratio
                    let lon = start.longitude + (end.longitude - start.longitude) * ratio
                    let split = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    traveled.append(clLocation(start.coordinate))
                    traveled.append(split)
                    remaining.append(split)
                    foundSplit = true
                } else {
                    remaining.append(clLocation(start.coordinate))
                }
            } else {
                remaining.append(clLocation(start.coordinate))
            }
        }

        if let last = points.last {
            if foundSplit || progress >= last.distanceFromStartMeters {
                if !foundSplit { traveled.append(clLocation(last.coordinate)) }
                else { remaining.append(clLocation(last.coordinate)) }
            } else {
                remaining.append(clLocation(last.coordinate))
            }
        }

        return (traveled, remaining)
    }

    static func cueSymbol(for kind: RouteCueKind) -> String {
        switch kind {
        case .start: "flag.fill"
        case .finish: "flag.checkered"
        case .continue: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .turnLeft: "arrow.turn.up.left"
        case .turnRight: "arrow.turn.up.right"
        case .sharpLeft: "arrow.turn.left.up"
        case .sharpRight: "arrow.turn.right.up"
        case .uTurn: "arrow.uturn.up"
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

struct UserHeadingMarker: View {
    let courseDegrees: Double?
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(.blue)
                .frame(width: size, height: size)
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: size, height: size)

            if let course = courseDegrees, course >= 0 {
                Image(systemName: "location.north.fill")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(course))
                    .offset(y: -size * 0.35)
            }
        }
    }
}

struct TurnArrowMarker: View {
    let bearing: Double
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: size * 0.6, weight: .black))
            .foregroundStyle(.white)
            .padding(size * 0.2)
            .background {
                Circle()
                    .fill(.black.opacity(0.75))
            }
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 2)
            }
            .rotationEffect(.degrees(bearing))
    }
}

struct NavigationGuidanceBar: View {
    let cue: RouteCue
    let distanceMeters: Double?
    let isOffRoute: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ActiveRouteMapOverlay.cueSymbol(for: cue.kind))
                .font(.title3.weight(.semibold))
                .foregroundStyle(isOffRoute ? .orange : .primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                if let distanceMeters {
                    Text(RouteFormatting.distance(distanceMeters))
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                }
                Text(cue.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct OutlinedRoutePolylines: MapContent {
    let traveled: [CLLocationCoordinate2D]
    let remaining: [CLLocationCoordinate2D]

    var body: some MapContent {
        if traveled.count >= 2 {
            MapPolyline(coordinates: traveled)
                .stroke(.black.opacity(0.5), lineWidth: 5)
            MapPolyline(coordinates: traveled)
                .stroke(.green, lineWidth: 3)
        }
        if remaining.count >= 2 {
            MapPolyline(coordinates: remaining)
                .stroke(.black.opacity(0.5), lineWidth: 5)
            MapPolyline(coordinates: remaining)
                .stroke(.blue, lineWidth: 3)
        }
    }
}
