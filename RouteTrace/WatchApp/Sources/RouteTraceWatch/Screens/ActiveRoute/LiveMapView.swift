import MapKit
import RouteTraceShared
import SwiftUI

struct LiveMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState

    @Environment(WatchPreferences.self) private var preferences
    @Environment(WatchRouteStore.self) private var routeStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var userPannedAway = false
    @State private var lastFollowAt = Date()

    private var isFocused: Bool {
        uiState.isMapFocus && uiState.selectedPage == .liveMap
    }

    private var crownEnabled: Bool {
        uiState.selectedPage == .liveMap || isFocused
    }

    private var usesOfflineTiles: Bool {
        guard let route = viewModel.routePackage else { return false }
        return (route.offlineStatus == .ready || route.offlineStatus == .partial)
            && routeStore.tileStore(for: route.id) != nil
    }

    var body: some View {
        AlwaysOnAware {
            ZStack {
                if usesOfflineTiles {
                    OfflineMapView(viewModel: viewModel, uiState: uiState, showChrome: false)
                } else {
                    mapLayer
                }

                if isFocused {
                    focusOverlayChrome
                } else {
                    overlayChrome
                }
            }
        } dimmed: {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(crownEnabled)
        .digitalCrownRotation(
            $uiState.mapSpan,
            from: 0.002,
            through: 0.04,
            by: 0.001,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: viewModel.navigationSnapshot?.currentCoordinate?.latitude) { _, _ in
            if !isFocused { recenterIfNeeded() }
        }
        .onChange(of: uiState.mapSpan) { _, _ in
            if isFocused {
                userPannedAway = true
            } else {
                recenterIfNeeded()
            }
        }
        .onAppear { recenterIfNeeded() }
    }

    @ViewBuilder
    private var overlayChrome: some View {
        VStack {
            HStack(alignment: .top) {
                RouteDistanceBubble(
                    covered: RouteFormatting.distance(viewModel.navigationSnapshot?.progressDistanceMeters ?? 0),
                    remaining: RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0)
                )
                .allowsHitTesting(true)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        enterMapFocusIfNeeded()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                            .foregroundStyle(RouteAppearance.overlayText.opacity(0.85))
                            .padding(6)
                            .background(RouteAppearance.overlayFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        userPannedAway = false
                        lastFollowAt = Date()
                        recenterIfNeeded()
                    } label: {
                        Image(systemName: "scope")
                            .font(.caption)
                            .foregroundStyle(RouteAppearance.overlayText.opacity(0.85))
                            .padding(6)
                            .background(RouteAppearance.overlayFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .allowsHitTesting(true)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            Spacer()
                .allowsHitTesting(false)

            if let snapshot = viewModel.navigationSnapshot,
               let cue = snapshot.nextCue,
               let distance = snapshot.distanceToNextCueMeters,
               distance <= 500 {
                NavigationGuidanceBar(
                    cue: cue,
                    distanceMeters: distance,
                    isOffRoute: snapshot.isOffRoute
                )
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
            }

            Spacer()
                .frame(height: 12)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private var focusOverlayChrome: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    userPannedAway = false
                    lastFollowAt = Date()
                    recenterIfNeeded()
                } label: {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(RouteAppearance.overlayText.opacity(0.85))
                        .padding(6)
                        .background(RouteAppearance.overlayFill, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            Spacer()
        }
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
                        TurnArrowMarker(bearing: cue.bearingAfter)
                    }
                }

                if let coordinate = viewModel.navigationSnapshot?.currentCoordinate {
                    Annotation("", coordinate: ActiveRouteMapOverlay.clLocation(coordinate)) {
                        UserHeadingMarker(
                            courseDegrees: viewModel.locationService.lastSample?.courseDegrees
                        )
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .onMapCameraChange(frequency: .continuous) { _ in
            guard isFocused else { return }
            userPannedAway = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func enterMapFocusIfNeeded() {
        guard !uiState.isMapFocus else { return }
        uiState.selectedPage = .liveMap
        uiState.enterMapFocus()
    }

    func recenterIfNeeded() {
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
