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

    var isMapFocus: Bool { interactionMode == .mapFocus }

    func enterMapFocus() {
        guard selectedPage.supportsMapFocus else { return }
        interactionMode = .mapFocus
    }

    func exitMapFocus() {
        interactionMode = .browse
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
        .padding(.vertical, 5)
        .allowsHitTesting(false)
    }
}

struct ActiveRouteStatusBar: View {
    let showActivityIcon: Bool
    let activityKind: ActivityKind
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showActivityIcon {
                Image(systemName: activityKind.systemImage)
                    .foregroundStyle(.green)
                    .font(.caption2)
            }
            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct ActiveRouteChrome<Content: View>: View {
    @Bindable var uiState: ActiveRouteUIState
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences

    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if uiState.isMapFocus {
                    mapFocusDoneBar
                }
                ActiveRoutePageDots(selectedPage: uiState.selectedPage)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .routeScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            ActiveRouteStatusBar(
                showActivityIcon: !showsSystemWorkoutIndicator,
                activityKind: viewModel.activityKind,
                isPaused: viewModel.isPaused
            )
            .padding(.top, 2)
            .padding(.leading, 2)

            Spacer()
        }
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

    private var mapFocusDoneBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                uiState.exitMapFocus()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RouteAppearance.overlayFill, in: Capsule())
        }
        .padding(.bottom, 4)
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
            .background(RouteAppearance.overlayFill, in: Capsule())
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
        .background(RouteAppearance.overlayFill, in: Capsule())
    }
}
