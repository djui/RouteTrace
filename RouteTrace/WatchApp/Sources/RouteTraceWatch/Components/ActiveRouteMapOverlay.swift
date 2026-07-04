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

    static func shouldRotateCueSymbol(_ kind: RouteCueKind) -> Bool {
        switch kind {
        case .continue, .start, .finish:
            true
        default:
            false
        }
    }

    static func cueMarkerRotation(kind: RouteCueKind, bearing: Double) -> Double {
        if shouldRotateCueSymbol(kind) {
            return bearing
        }
        switch kind {
        case .slightLeft: return 315
        case .slightRight: return 45
        case .turnLeft: return 270
        case .turnRight: return 90
        case .sharpLeft: return 225
        case .sharpRight: return 135
        case .uTurn: return 180
        default: return bearing
        }
    }

    static func resolvedHeadingDegrees(courseDegrees: Double?, fallbackBearing: Double?) -> Double {
        if let course = courseDegrees, course >= 0 {
            return course
        }
        return fallbackBearing ?? 0
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
    let headingDegrees: Double
    var size: CGFloat = 18

    private var dotSize: CGFloat { size * 0.55 }
    private var ringSize: CGFloat { size }
    private var wedgeLength: CGFloat { size * 0.38 }
    private var totalSize: CGFloat { ringSize + wedgeLength * 2 }

    var body: some View {
        ZStack {
            HeadingWedgeShape()
                .fill(.white)
                .frame(width: wedgeLength * 1.1, height: wedgeLength)
                .offset(y: -(ringSize / 2 + wedgeLength / 2))
                .rotationEffect(.degrees(headingDegrees))

            Circle()
                .stroke(.white, lineWidth: 2.5)
                .frame(width: ringSize, height: ringSize)

            Circle()
                .fill(.blue)
                .frame(width: dotSize, height: dotSize)
        }
        .frame(width: totalSize, height: totalSize)
    }
}

private struct HeadingWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CueSymbolMarker: View {
    let kind: RouteCueKind
    var bearing: Double = 0
    var symbolSize: CGFloat = 32
    var markerSize: CGFloat = 36
    var showsBackground: Bool = true
    var foregroundColor: Color = .white

    private var rotation: Double {
        ActiveRouteMapOverlay.shouldRotateCueSymbol(kind) ? bearing : 0
    }

    var body: some View {
        Image(systemName: ActiveRouteMapOverlay.cueSymbol(for: kind))
            .font(.system(size: symbolSize, weight: .black))
            .foregroundStyle(foregroundColor)
            .padding(showsBackground ? markerSize * 0.2 : 0)
            .background {
                if showsBackground {
                    Circle()
                        .fill(.black.opacity(0.75))
                }
            }
            .overlay {
                if showsBackground {
                    Circle()
                        .stroke(.white, lineWidth: 2)
                }
            }
            .rotationEffect(.degrees(rotation))
    }
}

struct TurnArrowMarker: View {
    let kind: RouteCueKind
    let bearing: Double
    var size: CGFloat = 36

    var body: some View {
        CueSymbolMarker(
            kind: kind,
            bearing: bearing,
            symbolSize: size * 0.55,
            markerSize: size
        )
    }
}

struct NavigationGuidanceBar: View {
    let cue: RouteCue
    let distanceMeters: Double?
    let isOffRoute: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CueSymbolMarker(
                kind: cue.kind,
                symbolSize: 32,
                markerSize: 36,
                showsBackground: false,
                foregroundColor: isOffRoute ? .orange : .primary
            )
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                if let distanceMeters {
                    Text(RouteFormatting.distance(distanceMeters))
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                }

                Text(cue.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct OutlinedRoutePolyline: MapContent {
    let coordinates: [CLLocationCoordinate2D]
    let color: Color

    var body: some MapContent {
        if coordinates.count >= 2 {
            MapPolyline(coordinates: coordinates)
                .stroke(
                    RouteAppearance.routeOutlineColor,
                    style: StrokeStyle(lineWidth: RouteAppearance.routeOutlineWidth, lineCap: .round, lineJoin: .round)
                )
            MapPolyline(coordinates: coordinates)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: RouteAppearance.routeStrokeWidth, lineCap: .round, lineJoin: .round)
                )
        }
    }
}

struct OutlinedRoutePolylines: MapContent {
    let traveled: [CLLocationCoordinate2D]
    let remaining: [CLLocationCoordinate2D]

    var body: some MapContent {
        OutlinedRoutePolyline(coordinates: traveled, color: .green)
        OutlinedRoutePolyline(coordinates: remaining, color: .blue)
    }
}
