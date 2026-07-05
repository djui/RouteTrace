import RouteTraceShared
import SwiftUI

struct ActiveRouteContainerView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences

    @State private var uiState = ActiveRouteUIState()
    @FocusState private var carouselCrownFocus: CarouselCrownFocus?

    private var usesTransparentBackground: Bool {
        !viewModel.isShowingSummary && uiState.selectedPage == .liveMap && !uiState.isMapFocus
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
    }

    private var carousel: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel) {
            ZStack {
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

                if uiState.selectedPage == .liveMap {
                    BrowseMapCrownLayer(
                        uiState: uiState,
                        carouselCrownFocus: $carouselCrownFocus
                    )
                }

                if uiState.selectedPage == .altitude {
                    AltitudeCrownLayer(
                        uiState: uiState,
                        routeDistance: viewModel.routePackage?.distanceMeters ?? 0,
                        progressMeters: viewModel.navigationSnapshot?.progressDistanceMeters ?? 0,
                        carouselCrownFocus: $carouselCrownFocus
                    )
                }
            }
        }
        .onChange(of: uiState.selectedPage) { _, page in
            assignCrownFocus(for: page)
            if page != .altitude {
                uiState.clearAltitudeInspect()
                uiState.altitudeCrownMeters = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
            }
        }
        .onAppear {
            assignCrownFocus(for: uiState.selectedPage)
        }
    }

    @ViewBuilder
    private var focusedMapPage: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel) {
            LiveMapView(viewModel: viewModel, uiState: uiState)
        }
    }

    private func assignCrownFocus(for page: RoutePage) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            switch page {
            case .liveMap:
                carouselCrownFocus = .liveMap
            case .altitude:
                carouselCrownFocus = .altitude
            case .metrics:
                carouselCrownFocus = .metrics
            default:
                carouselCrownFocus = nil
            }
        }
    }
}
