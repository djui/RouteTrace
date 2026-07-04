import MapKit
import RouteTraceShared
import SwiftUI

struct OverviewView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    var compact: Bool = false

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        AlwaysOnAware {
            activeOverview
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
    }

    private var activeOverview: some View {
        VStack(spacing: compact ? 4 : 8) {
            Map(position: $cameraPosition, interactionModes: compact ? [] : .all) {
                if let route = viewModel.routePackage {
                    MapPolyline(coordinates: ActiveRouteMapOverlay.routeCoordinates(route))
                        .stroke(
                            .blue.opacity(0.6),
                            style: StrokeStyle(lineWidth: compact ? 2 : 3, lineCap: .round, lineJoin: .round)
                        )

                    let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)
                    if !actual.isEmpty {
                        MapPolyline(coordinates: actual)
                            .stroke(
                                .green,
                                style: StrokeStyle(lineWidth: compact ? 2 : 3, lineCap: .round, lineJoin: .round)
                            )
                    }

                    ForEach(viewModel.recording.offRouteEvents) { event in
                        Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(event.coordinate)) {
                            Circle()
                                .fill(event.endedAt == nil ? Color.red : Color.orange)
                                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                        }
                    }

                    if let current = viewModel.navigationSnapshot?.currentCoordinate {
                        Annotation("You", coordinate: ActiveRouteMapOverlay.clLocation(current)) {
                            Circle()
                                .fill(.blue)
                                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                                .overlay(Circle().stroke(.white, lineWidth: 1))
                        }
                    }
                }
            }
            .frame(height: compact ? 120 : 140)

            if !compact {
                progressRow
            }
        }
        .padding(compact ? 4 : 8)
        .onAppear { fitRoute() }
    }

    private var progressRow: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Progress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(viewModel.progressFraction * 100))%")
                    .font(.title3)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0))
            }
        }
    }

    private func fitRoute() {
        guard let route = viewModel.routePackage else { return }
        let box = route.boundingBox
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: box.center.latitude, longitude: box.center.longitude),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.005, box.maxLatitude - box.minLatitude) * 1.3,
                longitudeDelta: max(0.005, box.maxLongitude - box.minLongitude) * 1.3
            )
        )
        cameraPosition = .region(region)
    }
}
