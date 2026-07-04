import MapKit
import RouteTraceShared
import SwiftUI

struct RouteMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(WatchRouteStore.self) private var routeStore

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var isFocused: Bool {
        uiState.isMapFocus && uiState.selectedPage == .routeMap
    }

    var body: some View {
        AlwaysOnAware {
            ZStack(alignment: .bottomLeading) {
                mapLayer

                VStack(alignment: .leading, spacing: 6) {
                    offlinePill
                    if !uiState.isMapFocus {
                        focusHint
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 28)

                if !isFocused {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            uiState.selectedPage = .routeMap
                            uiState.enterMapFocus()
                        }
                }
            }
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
        .onAppear { fitRoute() }
    }

    @ViewBuilder
    private var mapLayer: some View {
        if let route = viewModel.routePackage,
           route.offlineStatus == .ready || route.offlineStatus == .partial,
           routeStore.tileStore(for: route.id) != nil {
            OfflineMapView(viewModel: viewModel, showChrome: false)
        } else {
            Map(position: $cameraPosition, interactionModes: isFocused ? .all : []) {
                if let route = viewModel.routePackage {
                    MapPolyline(coordinates: ActiveRouteMapOverlay.routeCoordinates(route))
                        .stroke(.blue, lineWidth: 3)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .focusable(isFocused)
            .digitalCrownRotation(
                $uiState.mapSpan,
                from: 0.004,
                through: 0.08,
                by: 0.001,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: isFocused
            )
            .onChange(of: uiState.mapSpan) { _, span in
                guard isFocused, let route = viewModel.routePackage else { return }
                let box = route.boundingBox
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: box.center.latitude, longitude: box.center.longitude),
                        span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var offlinePill: some View {
        if let route = viewModel.routePackage {
            switch route.offlineStatus {
            case .ready:
                OfflineStatusPill(text: "Offline")
            case .partial:
                OfflineStatusPill(text: "Partial offline")
            case .missing:
                OfflineStatusPill(text: "Route only")
            }
        }
    }

    private var focusHint: some View {
        Button {
            uiState.enterMapFocus()
        } label: {
            Image(systemName: "scope")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(6)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func fitRoute() {
        guard let route = viewModel.routePackage else { return }
        let box = route.boundingBox
        let span = max(0.008, max(box.maxLatitude - box.minLatitude, box.maxLongitude - box.minLongitude) * 1.4)
        uiState.mapSpan = span
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: box.center.latitude, longitude: box.center.longitude),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
        )
    }
}
