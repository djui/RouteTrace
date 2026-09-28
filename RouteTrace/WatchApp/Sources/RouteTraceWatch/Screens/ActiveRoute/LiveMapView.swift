import MapKit
import RouteTraceShared
import SwiftUI

struct LiveMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchRouteStore.self) private var routeStore

    @FocusState private var mapCrownFocused: Bool
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var isFocused: Bool {
        uiState.isMapFocus
    }

    private var isMapVisible: Bool {
        uiState.selectedPage == .liveMap || isFocused
    }

    private var crownEnabled: Bool {
        uiState.selectedPage == .liveMap
    }

    private var batteryPolicy: BatteryModePolicy {
        BatteryModePolicy.policy(userMode: preferences.batteryMode)
    }

    private var headingUp: Bool {
        batteryPolicy.allowsHeadingUpRotation && preferences.mapOrientation == .headingUp
    }

    private var offlineTileStore: OfflineTileStore? {
        guard let route = viewModel.routePackage, route.offlineStatus != .missing else { return nil }
        return routeStore.tileStore(for: route.id)
    }

    var body: some View {
        AlwaysOnAware {
            ZStack {
                mapSurface
                if !isFocused {
                    // Tapping the map enters focus mode (pan + crown zoom).
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            uiState.selectedPage = .liveMap
                            uiState.enterMapFocus()
                        }
                }
            }
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(crownEnabled)
        .focused($mapCrownFocused)
        .modifier(MapCrownInteraction(
            isEnabled: crownEnabled,
            hapticFeedback: isFocused,
            mapSpan: $uiState.mapSpan
        ))
        .onChange(of: viewModel.displayCoordinate) { _, _ in
            recenterIfNeeded()
        }
        .onChange(of: uiState.mapSpan) { _, _ in
            recenterIfNeeded(force: true)
        }
        .onChange(of: uiState.isMapFocus) { _, focused in
            if !focused {
                recenterIfNeeded(force: true)
            }
            requestMapCrownFocus()
        }
        .onChange(of: uiState.selectedPage) { _, _ in
            requestMapCrownFocus()
        }
        .onAppear {
            recenterIfNeeded(force: true)
            requestMapCrownFocus()
        }
    }

    private var mapSurface: some View {
        mapContent
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var mapContent: some View {
        switch preferences.mapDisplayMode {
        case .onlineNative:
            onlineMap
        case .offlineCorridor:
            WatchMapCanvas(
                viewModel: viewModel,
                uiState: uiState,
                tileStore: offlineTileStore,
                isInteractive: isFocused,
                headingUp: headingUp
            )
            .overlay(alignment: .bottomLeading) {
                if offlineTileStore == nil {
                    OfflineStatusPill(text: "No offline map")
                        .padding(.leading, RouteAppearance.watchOverlayHorizontalInset)
                        .padding(.bottom, 26)
                }
            }
        case .routeOnly:
            WatchMapCanvas(
                viewModel: viewModel,
                uiState: uiState,
                tileStore: nil,
                isInteractive: isFocused,
                headingUp: headingUp
            )
        }
    }

    private var onlineMap: some View {
        Map(position: $cameraPosition, interactionModes: isFocused ? [.pan, .zoom] : []) {
            if let route = viewModel.routePackage {
                let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
                let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)

                OutlinedRoutePolyline(coordinates: split.traveled, color: RouteAppearance.routeColor.opacity(0.35))
                OutlinedRoutePolyline(coordinates: split.remaining, color: RouteAppearance.routeColor)

                if viewModel.displayTrack.count >= 2 {
                    OutlinedRoutePolyline(
                        coordinates: viewModel.displayTrack.map(ActiveRouteMapOverlay.clLocation),
                        color: RouteAppearance.trackColor
                    )
                }

                if let display = viewModel.upcomingCueDisplay {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(display.cue.coordinate)) {
                        TurnArrowMarker(kind: display.cue.kind, bearing: display.cue.bearingAfter, size: 28)
                    }
                }

                if let coordinate = viewModel.displayCoordinate {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(coordinate)) {
                        UserHeadingMarker(headingDegrees: headingUp ? nil : viewModel.courseDegrees)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(isFocused)
    }

    private func requestMapCrownFocus() {
        guard crownEnabled else {
            mapCrownFocused = false
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if crownEnabled {
                mapCrownFocused = true
            }
        }
    }

    /// Keeps the online map centered on the runner (the canvas maps center themselves).
    private func recenterIfNeeded(force: Bool = false) {
        guard preferences.mapDisplayMode == .onlineNative, !isFocused else { return }
        guard let coordinate = viewModel.displayCoordinate ?? viewModel.routePackage?.boundingBox.center else { return }
        guard preferences.mapFollowMode || force else { return }

        if !force {
            guard viewModel.displayUpdateCoordinator.shouldRecenter(
                policy: batteryPolicy.displayUpdatePolicy,
                coordinate: coordinate,
                isMapVisible: isMapVisible,
                followEnabled: preferences.mapFollowMode
            ) else { return }
        }
        viewModel.displayUpdateCoordinator.recordRecenter(at: coordinate)

        let center = ActiveRouteMapOverlay.clLocation(coordinate)
        let meters = uiState.mapSpan * 111_000
        if headingUp, let course = viewModel.courseDegrees {
            cameraPosition = .camera(MapCamera(centerCoordinate: center, distance: meters * 1.2, heading: course, pitch: 0))
        } else {
            cameraPosition = .region(MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters))
        }
    }
}

struct MapCrownInteraction: ViewModifier {
    let isEnabled: Bool
    let hapticFeedback: Bool
    @Binding var mapSpan: Double

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .digitalCrownRotation(
                    $mapSpan,
                    from: 0.002,
                    through: 0.04,
                    by: RouteAppearance.mapCrownStep,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: hapticFeedback
                )
        } else {
            content
        }
    }
}
