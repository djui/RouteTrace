import MapKit
import SwiftUI
import RouteTraceShared

struct RouteMapPreview: View {
    let routePoints: [RoutePoint]
    var trackPoints: [TrackPoint] = []
    var lineColor: Color = .blue
    var trackColor: Color = .green
    var gapColor: Color = .secondary.opacity(0.6)
    var lineWidth: CGFloat = 4

    @State private var cameraPosition: MapCameraPosition = .automatic
    @Environment(\.colorScheme) private var colorScheme

    private var routeCoordinates: [CLLocationCoordinate2D] {
        routePoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var trackSegments: [TrackSegment] {
        guard trackPoints.count >= 2 else { return [] }
        return TrackSegmentSplitter.segments(from: trackPoints)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
            }

            ForEach(Array(trackSegments.enumerated()), id: \.offset) { _, segment in
                let coordinates = segment.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                if coordinates.count >= 2 {
                    if segment.isGapConnector {
                        MapPolyline(coordinates: coordinates)
                            .stroke(
                                gapColor,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4])
                            )
                    } else {
                        MapPolyline(coordinates: coordinates)
                            .stroke(
                                trackColor,
                                style: StrokeStyle(lineWidth: lineWidth - 1, lineCap: .round, lineJoin: .round)
                            )
                    }
                }
            }

            if let start = routeCoordinates.first {
                Marker("Start", coordinate: start)
                    .tint(.green)
            }

            if let finish = routeCoordinates.last, routeCoordinates.count > 1 {
                Marker("Finish", coordinate: finish)
                    .tint(.red)
            }
        }
        .mapStyle(mapStyle)
        .onAppear {
            updateCamera()
        }
        .onChange(of: routePoints.count) { _, _ in
            updateCamera()
        }
        .onChange(of: trackPoints.count) { _, _ in
            updateCamera()
        }
    }

    private var mapStyle: MapStyle {
        switch colorScheme {
        case .dark:
            .standard(elevation: .realistic, emphasis: .muted)
        default:
            .standard(elevation: .realistic)
        }
    }

    private func updateCamera() {
        let trackCoordinates = trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let allCoordinates = routeCoordinates + trackCoordinates
        guard !allCoordinates.isEmpty else { return }

        if allCoordinates.count == 1, let coordinate = allCoordinates.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
            return
        }

        var rect = MKMapRect.null
        for coordinate in allCoordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.isNull ? MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)) : rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }

        let padding = rect.size.width * 0.2
        let padded = rect.insetBy(dx: -padding, dy: -padding)
        cameraPosition = .rect(padded)
    }
}
