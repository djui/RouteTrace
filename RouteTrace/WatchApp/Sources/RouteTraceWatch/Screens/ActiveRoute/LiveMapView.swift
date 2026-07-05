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
    @State private var offlineRecenterToken = 0

    private var isFocused: Bool {
        uiState.isMapFocus
    }

    private var isMapVisible: Bool {
        uiState.selectedPage == .liveMap || isFocused
    }

    private var crownEnabled: Bool {
        uiState.isMapFocus || (uiState.selectedPage == .liveMap && !uiState.isMapFocus)
    }

    private var batteryPolicy: BatteryModePolicy {
        BatteryModePolicy.policy(userMode: preferences.batteryMode)
    }

    private var offlinePackAvailable: Bool {
        guard let route = viewModel.routePackage else { return false }
        return (route.offlineStatus == .ready || route.offlineStatus == .partial)
            && routeStore.tileStore(for: route.id) != nil
    }

    private var usesRouteOnly: Bool {
        preferences.mapDisplayMode == .routeOnly
    }

    private var usesOfflineTiles: Bool {
        switch preferences.mapDisplayMode {
        case .routeOnly:
            return false
        case .onlineNative:
            return false
        case .offlineCorridor:
            return offlinePackAvailable
        }
    }

    var body: some View {
        mapContent
        .onChange(of: viewModel.displayCoordinate?.latitude) { _, _ in
            followLocationIfNeeded()
        }
        .onChange(of: viewModel.displayCoordinate?.longitude) { _, _ in
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
            requestMapCrownFocus()
        }
        .onChange(of: uiState.selectedPage) { _, _ in
            requestMapCrownFocus()
        }
        .onChange(of: uiState.isMapFocus) { _, _ in
            requestMapCrownFocus()
        }
    }

    private var mapContent: some View {
        AlwaysOnAware {
            ZStack {
                mapSurface

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

    @ViewBuilder
    private var mapSurface: some View {
        Group {
            if usesRouteOnly {
                RouteOnlyMapView(viewModel: viewModel, uiState: uiState)
            } else if usesOfflineTiles {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(crownEnabled && !usesRouteOnly)
        .focused($mapCrownFocused)
        .modifier(MapCrownInteraction(
            isEnabled: crownEnabled && !usesRouteOnly,
            hapticFeedback: isFocused,
            mapSpan: $uiState.mapSpan
        ))
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

                if let display = viewModel.upcomingCueDisplay {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(display.cue.coordinate)) {
                        TurnArrowMarker(kind: display.cue.kind, bearing: display.cue.bearingAfter)
                    }
                }

                if let coordinate = viewModel.displayCoordinate {
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

    private func requestMapCrownFocus() {
        guard crownEnabled, !usesRouteOnly else {
            mapCrownFocused = false
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if crownEnabled, !usesRouteOnly {
                mapCrownFocused = true
            }
        }
    }

    private func enterMapFocusIfNeeded() {
        guard !uiState.isMapFocus else { return }
        uiState.selectedPage = .liveMap
        uiState.enterMapFocus()
    }

    private func followLocationIfNeeded() {
        guard !isFocused else { return }
        recenterIfNeeded()
    }

    func recenterIfNeeded() {
        guard !isFocused else { return }
        guard let coordinate = viewModel.displayCoordinate else { return }
        guard preferences.mapFollowMode else { return }

        let policy = batteryPolicy.displayUpdatePolicy
        guard viewModel.displayUpdateCoordinator.shouldRecenter(
            policy: policy,
            coordinate: coordinate,
            isMapVisible: isMapVisible,
            followEnabled: preferences.mapFollowMode
        ) else {
            return
        }

        viewModel.displayUpdateCoordinator.recordRecenter(at: coordinate)
        offlineRecenterToken += 1

        let center = ActiveRouteMapOverlay.clLocation(coordinate)
        if batteryPolicy.allowsHeadingUpRotation,
           preferences.mapOrientation == .headingUp,
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
