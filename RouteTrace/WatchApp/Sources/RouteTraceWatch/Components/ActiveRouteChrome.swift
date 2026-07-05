import RouteTraceShared
import SwiftUI

enum RoutePage: Int, CaseIterable, Identifiable {
    case controls
    case liveMap
    case directions
    case altitude
    case metrics

    var id: Int { rawValue }

    var activeDotColor: Color {
        RouteAppearance.pageDotActive(for: self)
    }

    var supportsMapFocus: Bool {
        self == .liveMap
    }
}

enum ActiveInteractionMode: Equatable {
    case browse
    case mapFocus
}

@MainActor
@Observable
final class ActiveRouteUIState {
    var selectedPage: RoutePage = .liveMap
    var interactionMode: ActiveInteractionMode = .browse
    var mapSpan: Double = 0.012
    var altitudeCrownMeters: Double = 0
    var isAltitudeScrubbing: Bool = false

    var isMapFocus: Bool { interactionMode == .mapFocus }

    func enterMapFocus() {
        guard selectedPage.supportsMapFocus else { return }
        interactionMode = .mapFocus
    }

    func exitMapFocus() {
        interactionMode = .browse
    }

    func clearAltitudeInspect() {
        isAltitudeScrubbing = false
    }
}

struct ActiveRoutePageDots: View {
    let selectedPage: RoutePage

    var body: some View {
        HStack(spacing: 7) {
            ForEach(RoutePage.allCases) { page in
                Circle()
                    .fill(page == selectedPage ? page.activeDotColor : RouteAppearance.pageDotInactive)
                    .frame(
                        width: page == selectedPage ? 6 : 5,
                        height: page == selectedPage ? 6 : 5
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .allowsHitTesting(false)
    }
}

struct ActiveRouteStatusBar: View {
    let showActivityIcon: Bool
    let activityKind: ActivityKind
    let isPaused: Bool
    let animateActivityIcon: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if showActivityIcon {
                Group {
                    Image(systemName: activityKind.systemImage)
                        .foregroundStyle(.green)
                        .font(.caption2)
                }
                .modifier(ConditionalPulseEffect(isEnabled: animateActivityIcon))
            }
        }
    }
}

private struct ConditionalPulseEffect: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}

struct ActiveRouteChrome<Content: View>: View {
    @Bindable var uiState: ActiveRouteUIState
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @ViewBuilder let content: () -> Content

    private var usesTransparentBackground: Bool {
        uiState.selectedPage == .liveMap && !isLuminanceReduced
    }

    private var showsLiveMapBrowseChrome: Bool {
        uiState.selectedPage == .liveMap && !uiState.isMapFocus && !isLuminanceReduced
    }

    private var animatesActivityIcon: Bool {
        uiState.selectedPage == .liveMap && !isLuminanceReduced
    }

    var body: some View {
        chromeContent
            .conditionalRouteScreenBackground(isOpaque: !usesTransparentBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var chromeContent: some View {
        ZStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            if showsLiveMapBrowseChrome {
                liveMapBrowseOverlays
            } else if !uiState.isMapFocus && !isLuminanceReduced {
                standardChromeOverlay
            }

            if uiState.isMapFocus {
                mapFocusExitOverlay
            }
        }
    }

    private var mapFocusExitOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                RouteMapIconButton(systemName: "xmark") {
                    uiState.exitMapFocus()
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, RouteAppearance.watchMapFocusControlInset)
            .padding(.top, RouteAppearance.watchMapFocusControlInset)

            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(true)
    }

    private var liveMapBrowseOverlays: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                RouteDistanceBubble(
                    covered: RouteFormatting.distance(viewModel.navigationSnapshot?.progressDistanceMeters ?? 0),
                    remaining: RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0)
                )
                .padding(.top, RouteAppearance.watchMapDistanceTopInset)
            }
            .overlay(alignment: .topLeading) {
                if viewModel.showsWeakGPSIndicator, let label = viewModel.gpsStatusLabel {
                    GPSStatusPill(label: label)
                        .padding(.leading, RouteAppearance.watchCornerClearance)
                        .padding(.top, RouteAppearance.watchEdgeInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                ActiveRouteStatusBar(
                    showActivityIcon: !showsSystemWorkoutIndicator,
                    activityKind: viewModel.activityKind,
                    isPaused: viewModel.isPaused,
                    animateActivityIcon: animatesActivityIcon
                )
                .padding(.trailing, RouteAppearance.watchCornerClearance)
                .padding(.top, RouteAppearance.watchEdgeInset)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 2) {
                    if let snapshot = viewModel.navigationSnapshot,
                       let cue = snapshot.nextCue,
                       let distance = snapshot.distanceToNextCueMeters,
                       distance <= 500 {
                        NavigationGuidanceBar(
                            cue: cue,
                            distanceMeters: distance,
                            isOffRoute: snapshot.isOffRoute
                        )
                    }

                    ActiveRoutePageDots(selectedPage: uiState.selectedPage)
                }
                .padding(.horizontal, RouteAppearance.watchOverlayHorizontalInset)
                .padding(.bottom, RouteAppearance.watchEdgeInset)
            }
            .ignoresSafeArea(edges: .vertical)
    }

    private var standardChromeOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                if viewModel.showsWeakGPSIndicator, let label = viewModel.gpsStatusLabel {
                    GPSStatusPill(label: label)
                }

                Spacer(minLength: 0)

                ActiveRouteStatusBar(
                    showActivityIcon: !showsSystemWorkoutIndicator,
                    activityKind: viewModel.activityKind,
                    isPaused: viewModel.isPaused,
                    animateActivityIcon: animatesActivityIcon
                )
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)

            ActiveRoutePageDots(selectedPage: uiState.selectedPage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .ignoresSafeArea(edges: .bottom)
    }

    private var showsSystemWorkoutIndicator: Bool {
        guard preferences.useHealthKitWorkouts else { return false }
        switch viewModel.workoutService.status {
        case .running, .paused:
            return true
        default:
            return false
        }
    }
}

struct GPSStatusPill: View {
    let label: String

    var body: some View {
        Label(label, systemImage: "location.slash")
            .font(.caption2)
            .foregroundStyle(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .routeMapOverlayBackground(in: Capsule())
    }
}

struct OfflineStatusPill: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "icloud.slash")
            .font(.caption2)
            .foregroundStyle(RouteAppearance.overlayText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .routeMapOverlayBackground(in: Capsule())
    }
}

struct RouteDistanceBubble: View {
    let covered: String
    let remaining: String

    var body: some View {
        HStack(spacing: 10) {
            metricRow(symbol: "location.circle.fill", value: covered)
            metricRow(symbol: "flag.fill", value: remaining)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .routeMapOverlayBackground(in: Capsule())
    }

    private func metricRow(symbol: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RouteAppearance.overlayText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct RouteMetricInline: View {
    let symbol: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RouteAppearance.overlayText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .routeMapOverlayBackground(in: Capsule())
    }
}
