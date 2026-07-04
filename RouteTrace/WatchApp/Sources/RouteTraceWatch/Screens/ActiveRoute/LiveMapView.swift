import MapKit
import RouteTraceShared
import SwiftUI

struct LiveMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(WatchPreferences.self) private var preferences

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var userPannedAway = false
    @State private var lastFollowAt = Date()

    private var isFocused: Bool {
        uiState.isMapFocus && uiState.selectedPage == .liveMap
    }

    var body: some View {
        AlwaysOnAware {
            ZStack(alignment: .bottom) {
                mapLayer

                HStack(spacing: 8) {
                    RouteMetricCard(
                        title: "Progress",
                        value: RouteFormatting.distance(viewModel.navigationSnapshot?.progressDistanceMeters ?? 0)
                    )
                    RouteMetricCard(
                        title: "Remaining",
                        value: RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0)
                    )
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 28)

                if !isFocused {
                    VStack {
                        HStack {
                            Spacer()
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
                        Spacer()
                    }
                    .padding(4)
                }
            }
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
        .onChange(of: viewModel.navigationSnapshot?.currentCoordinate?.latitude) { _, _ in
            if !isFocused { recenterIfNeeded() }
        }
        .onAppear { recenterIfNeeded() }
    }

    private var mapLayer: some View {
        Map(position: $cameraPosition, interactionModes: isFocused ? .all : []) {
            if let route = viewModel.routePackage {
                MapPolyline(coordinates: ActiveRouteMapOverlay.routeCoordinates(route))
                    .stroke(.blue, lineWidth: 3)

                let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)
                if !actual.isEmpty {
                    MapPolyline(coordinates: actual)
                        .stroke(.green.opacity(0.85), lineWidth: 2)
                }

                if let coordinate = viewModel.navigationSnapshot?.currentCoordinate {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(coordinate)) {
                        Circle()
                            .fill(.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .focusable(isFocused)
        .digitalCrownRotation(
            $uiState.mapSpan,
            from: 0.002,
            through: 0.04,
            by: 0.001,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: isFocused
        )
        .onChange(of: uiState.mapSpan) { _, _ in
            if isFocused { userPannedAway = true }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !uiState.isMapFocus {
                uiState.selectedPage = .liveMap
                uiState.enterMapFocus()
            }
        }
    }

    private func recenterIfNeeded() {
        guard let coordinate = viewModel.navigationSnapshot?.currentCoordinate else { return }

        if preferences.mapFollowMode {
            if userPannedAway, Date().timeIntervalSince(lastFollowAt) < 5 { return }
            userPannedAway = false
        }

        let center = ActiveRouteMapOverlay.clLocation(coordinate)
        if preferences.mapOrientation == .headingUp,
           let course = viewModel.locationService.lastSample?.courseDegrees {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: center,
                    distance: uiState.mapSpan * 120_000,
                    heading: course,
                    pitch: 0
                )
            )
        } else {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: uiState.mapSpan, longitudeDelta: uiState.mapSpan)
                )
            )
        }
    }
}
