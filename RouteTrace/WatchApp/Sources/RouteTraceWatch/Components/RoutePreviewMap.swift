import MapKit
import RouteTraceShared
import SwiftUI

struct RoutePreviewMap: View {
    let route: RoutePackage

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            MapPolyline(coordinates: ActiveRouteMapOverlay.routeCoordinates(route))
                .stroke(
                    .blue,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .onAppear { fitRoute() }
    }

    private func fitRoute() {
        let box = route.boundingBox
        let span = max(0.005, max(box.maxLatitude - box.minLatitude, box.maxLongitude - box.minLongitude) * 1.4)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: box.center.latitude, longitude: box.center.longitude),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        )
    }
}
