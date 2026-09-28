import MapKit
import SwiftUI
import RouteTraceShared

/// Planned route (blue) and optional recorded track (green, or in zone colours) on a map,
/// framed to fit.
struct RouteMapPreview: View {
    private let routeCoordinates: [CLLocationCoordinate2D]
    private let trackSegments: [TrackSegment]
    private let trackZones: WorkoutZones?
    private let zoneSegments: [ZonedTrackSegment]
    private let allCoordinates: [CLLocationCoordinate2D]
    private let isLoop: Bool

    var routeColor: Color = RouteDesign.routeColor
    var trackColor: Color = RouteDesign.trackColor
    var interactive = false
    var mapStyle: MapStyle = .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
    /// Lets callers place map controls (location button, compass) themselves.
    var mapScope: Namespace.ID?

    @State private var cameraPosition: MapCameraPosition = .automatic

    /// With `trackZones`, the track takes the colour of the zone its recorded heart rate was in.
    init(
        routePoints: [RoutePoint],
        trackPoints: [TrackPoint] = [],
        trackZones: WorkoutZones? = nil,
        routeColor: Color = RouteDesign.routeColor,
        trackColor: Color = RouteDesign.trackColor,
        interactive: Bool = false,
        mapStyle: MapStyle = .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll),
        mapScope: Namespace.ID? = nil
    ) {
        routeCoordinates = routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        trackSegments = trackPoints.count >= 2 ? TrackSegmentSplitter.segments(from: trackPoints) : []
        self.trackZones = trackZones
        if let trackZones, trackPoints.count >= 2 {
            zoneSegments = ZonedTrackSegmenter.segments(from: trackPoints, zones: trackZones)
        } else {
            zoneSegments = []
        }
        allCoordinates = routeCoordinates
            + trackPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if let first = routePoints.first, let last = routePoints.last, routePoints.count > 1 {
            isLoop = MapMath.haversineMeters(from: first.coordinate, to: last.coordinate) < 60
        } else {
            isLoop = false
        }
        self.routeColor = routeColor
        self.trackColor = trackColor
        self.interactive = interactive
        self.mapStyle = mapStyle
        self.mapScope = mapScope
    }

    var body: some View {
        Map(position: $cameraPosition, interactionModes: interactive ? .all : [], scope: mapScope) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(routeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if zoneSegments.isEmpty {
                ForEach(Array(trackSegments.enumerated()), id: \.offset) { _, segment in
                    let coordinates = segment.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    if segment.isGapConnector {
                        MapPolyline(coordinates: coordinates)
                            .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                    } else {
                        MapPolyline(coordinates: coordinates)
                            .stroke(trackColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                // A light casing keeps the blue easy zone apart from the blue planned route.
                ForEach(Array(trackSegments.enumerated()), id: \.offset) { _, segment in
                    if !segment.isGapConnector {
                        MapPolyline(coordinates: segment.coordinates.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        })
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(Array(zoneSegments.enumerated()), id: \.offset) { _, segment in
                    let coordinates = segment.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    if segment.isGapConnector {
                        MapPolyline(coordinates: coordinates)
                            .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                    } else {
                        MapPolyline(coordinates: coordinates)
                            .stroke(zoneColor(for: segment), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            if let start = routeCoordinates.first {
                Annotation(isLoop ? "Start & Finish" : "Start", coordinate: start, anchor: .center) {
                    EndpointMarker(kind: isLoop ? .loop : .start)
                }
                .annotationTitles(.hidden)
            }

            if !isLoop, let finish = routeCoordinates.last, routeCoordinates.count > 1 {
                Annotation("Finish", coordinate: finish, anchor: .center) {
                    EndpointMarker(kind: .finish)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(mapStyle)
        .mapControlVisibility(interactive ? .automatic : .hidden)
        .onAppear(perform: frameContent)
        .onChange(of: allCoordinates.count) { _, _ in frameContent() }
    }

    private func zoneColor(for segment: ZonedTrackSegment) -> Color {
        guard let trackZones, let zone = segment.zoneIndex else { return trackColor }
        return trackZones.color(forZone: zone)
    }

    private func frameContent() {
        guard let first = allCoordinates.first else { return }

        guard allCoordinates.count > 1 else {
            cameraPosition = .region(MKCoordinateRegion(center: first, latitudinalMeters: 800, longitudinalMeters: 800))
            return
        }

        var rect = MKMapRect.null
        for coordinate in allCoordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1))
        }
        // Pad by the larger side so north-south routes don't touch the edges.
        let padding = max(rect.size.width, rect.size.height) * 0.18
        cameraPosition = .rect(rect.insetBy(dx: -padding, dy: -padding))
    }
}

struct EndpointMarker: View {
    enum Kind { case start, finish, loop }
    let kind: Kind

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch kind {
        case .start, .loop: .green
        case .finish: .red
        }
    }

    private var symbol: String {
        switch kind {
        case .start: "play.fill"
        case .finish: "flag.checkered"
        case .loop: "arrow.triangle.2.circlepath"
        }
    }
}

/// Full-screen map with standard map controls and a style switch.
struct RouteMapFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Namespace private var mapScope

    let title: String
    let subtitle: String
    let routePoints: [RoutePoint]
    let trackPoints: [TrackPoint]
    var trackZones: WorkoutZones?

    @State private var style: Style = .standard

    enum Style: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case satellite = "Satellite"
        var id: String { rawValue }

        var mapStyle: MapStyle {
            switch self {
            case .standard: .standard(elevation: .realistic, emphasis: .muted)
            case .satellite: .hybrid(elevation: .realistic)
            }
        }
    }

    var body: some View {
        RouteMapPreview(
            routePoints: routePoints,
            trackPoints: trackPoints,
            trackZones: trackZones,
            interactive: true,
            mapStyle: style.mapStyle,
            mapScope: mapScope
        )
        .id(style)
        .mapControls {
            MapScaleView()
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close")

                    Menu {
                        Picker("Map Style", selection: $style) {
                            ForEach(Style.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                    } label: {
                        Image(systemName: "square.2.layers.3d")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Map Style")

                    MapUserLocationButton(scope: mapScope)
                        .buttonBorderShape(.circle)
                    MapCompass(scope: mapScope)
                }
            }
            .padding(.horizontal)
        }
        .mapScope(mapScope)
    }
}
