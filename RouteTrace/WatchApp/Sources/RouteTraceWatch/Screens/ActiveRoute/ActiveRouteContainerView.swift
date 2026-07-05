import RouteTraceShared
import SwiftUI

struct ActiveRouteContainerView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var uiState = ActiveRouteUIState()
    @FocusState private var carouselCrownFocus: CarouselCrownFocus?

    private var usesTransparentBackground: Bool {
        !viewModel.isShowingSummary && uiState.selectedPage == .liveMap && !isLuminanceReduced
    }

    var body: some View {
        Group {
            if viewModel.isShowingSummary {
                NavigationStack {
                    ActivitySummaryView(viewModel: viewModel)
                }
            } else if uiState.isMapFocus {
                focusedMapPage
            } else {
                carousel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .conditionalRouteScreenBackground(isOpaque: !usesTransparentBackground)
        .onReceive(NotificationCenter.default.publisher(for: RouteTraceIntentNotifications.toggleMapDirections)) { _ in
            handleToggleMapDirections()
        }
        .onChange(of: viewModel.preferredStartPage) { _, page in
            applyPreferredStartPage(page)
        }
        .onChange(of: preferences.batteryMode) { _, _ in
            viewModel.applyBatterySettings(from: preferences)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            viewModel.applyBatterySettings(from: preferences)
        }
    }

    private var carousel: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel) {
            TabView(selection: $uiState.selectedPage) {
                RouteControlsView(viewModel: viewModel)
                    .tag(RoutePage.controls)

                LiveMapView(viewModel: viewModel, uiState: uiState)
                    .tag(RoutePage.liveMap)

                DirectionsView(viewModel: viewModel)
                    .tag(RoutePage.directions)

                AltitudeProfileView(viewModel: viewModel, uiState: uiState)
                    .tag(RoutePage.altitude)

                MetricsView(
                    viewModel: viewModel,
                    uiState: uiState,
                    carouselCrownFocus: $carouselCrownFocus
                )
                    .tag(RoutePage.metrics)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .disabled(uiState.isMapFocus)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: uiState.selectedPage) { _, page in
            assignCrownFocus(for: page)
            if page != .altitude {
                uiState.clearAltitudeInspect()
                uiState.altitudeCrownMeters = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
            }
        }
        .onChange(of: uiState.isMapFocus) { _, _ in
            assignCrownFocus(for: uiState.selectedPage)
        }
        .onAppear {
            applyPreferredStartPage(viewModel.preferredStartPage)
            assignCrownFocus(for: uiState.selectedPage)
        }
    }

    @ViewBuilder
    private var focusedMapPage: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel) {
            LiveMapView(viewModel: viewModel, uiState: uiState)
        }
    }

    private func handleToggleMapDirections() {
        if preferences.mapDisplayMode == .routeOnly {
            uiState.selectedPage = .directions
        } else {
            uiState.selectedPage = .liveMap
        }
    }

    private func applyPreferredStartPage(_ page: BatteryPreferredStartPage?) {
        guard let page else { return }
        switch page {
        case .directions:
            uiState.selectedPage = .directions
        }
        viewModel.clearPreferredStartPage()
    }

    private func assignCrownFocus(for page: RoutePage) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            switch page {
            case .metrics where !uiState.isMapFocus:
                carouselCrownFocus = .metrics
            default:
                carouselCrownFocus = nil
            }
        }
    }
}
