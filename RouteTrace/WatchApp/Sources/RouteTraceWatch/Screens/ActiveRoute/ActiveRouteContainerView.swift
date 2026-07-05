import RouteTraceShared
import SwiftUI

struct ActiveRouteContainerView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences

    @State private var uiState = ActiveRouteUIState()

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

                    AltitudeProfileView(viewModel: viewModel)
                        .tag(RoutePage.altitude)

                    MetricsView(viewModel: viewModel, uiState: uiState)
                        .tag(RoutePage.metrics)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .disabled(uiState.isMapFocus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if uiState.selectedPage == .liveMap {
                    BrowseMapCrownLayer(uiState: uiState)
                }
            }
        }
    }

    @ViewBuilder
    private var focusedMapPage: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel) {
            LiveMapView(viewModel: viewModel, uiState: uiState)
        }
    }
}
