import MapKit
import RouteTraceShared
import SwiftUI

struct LiveMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchRouteStore.self) private var routeStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var offlineRecenterToken = 0

    private var isFocused: Bool {
        uiState.isMapFocus && uiState.selectedPage == .liveMap
    }

    private var usesOfflineTiles: Bool {
        guard let route = viewModel.routePackage else { return false }
        return (route.offlineStatus == .ready || route.offlineStatus == .partial)
            && routeStore.tileStore(for: route.id) != nil
    }

    var body: some View {
        Group {
            if isFocused {
                mapContent
                    .focusable(true)
                    .digitalCrownRotation(
                        $uiState.mapSpan,
                        from: 0.002,
                        through: 0.04,
                        by: 0.001,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
            } else {
                mapContent
            }
        }
        .onChange(of: viewModel.navigationSnapshot?.currentCoordinate?.latitude) { _, _ in
            followLocationIfNeeded()
        }
        .onChange(of: viewModel.navigationSnapshot?.currentCoordinate?.longitude) { _, _ in
            followLocationIfNeeded()
        }
        .onChange(of: uiState.mapSpan) { _, _ in
            if !isFocused {
                recenterIfNeeded()
            }
        }
        .onAppear {
            if !isFocused {
                recenterIfNeeded()
            }
        }
    }

    private var mapContent: some View {
        AlwaysOnAware {
            ZStack {
                if usesOfflineTiles {
                    OfflineMapView(
                        viewModel: viewModel,
                        uiState: uiState,
                        showChrome: false,
                        allowsHitTesting: isFocused,
                        recenterToken: offlineRecenterToken
                    )
                } else {
                    mapLayer
                }

                if !isFocused {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            enterMapFocusIfNeeded()
                        }
                        .allowsHitTesting(true)
                }
            }
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapLayer: some View {
        Map(position: $cameraPosition, interactionModes: isFocused ? .all : []) {
            if let route = viewModel.routePackage {
                let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
                let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)
                let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)

                OutlinedRoutePolyline(coordinates: split.remaining, color: .blue)

                if actual.count >= 2 {
                    OutlinedRoutePolyline(coordinates: actual, color: .green)
                }

                if let snapshot = viewModel.navigationSnapshot,
                   let cue = snapshot.nextCue,
                   let distance = snapshot.distanceToNextCueMeters,
                   distance <= 500 {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(cue.coordinate)) {
                        TurnArrowMarker(kind: cue.kind, bearing: cue.bearingAfter)
                    }
                }

                if let coordinate = viewModel.navigationSnapshot?.currentCoordinate {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(coordinate)) {
                        UserHeadingMarker(headingDegrees: headingDegrees)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(isFocused)
    }

    private var headingDegrees: Double {
        ActiveRouteMapOverlay.resolvedHeadingDegrees(
            courseDegrees: viewModel.locationService.lastSample?.courseDegrees,
            fallbackBearing: viewModel.navigationSnapshot?.nextCue?.bearingAfter
        )
    }

    private func enterMapFocusIfNeeded() {
        guard !uiState.isMapFocus else { return }
        uiState.selectedPage = .liveMap
        uiState.enterMapFocus()
    }

    private func followLocationIfNeeded() {
        guard !isFocused else { return }
        offlineRecenterToken += 1
        recenterIfNeeded()
    }

    func recenterIfNeeded() {
        guard !isFocused else { return }
        guard let coordinate = viewModel.navigationSnapshot?.currentCoordinate else { return }

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
