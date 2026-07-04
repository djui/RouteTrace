import RouteTraceShared
import SwiftUI

struct ActiveRouteContainerView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var uiState = ActiveRouteUIState()
    @State private var showFinishConfirm = false

    var body: some View {
        Group {
            if viewModel.isShowingSummary {
                ActivitySummaryView(viewModel: viewModel)
            } else if uiState.isMapFocus {
                focusedMapPage
            } else {
                carousel
            }
        }
        .confirmationDialog("Finish this activity?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Review Summary") {
                viewModel.prepareSummary(preferences: preferences)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var carousel: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel, showFinishConfirm: $showFinishConfirm) {
            TabView(selection: $uiState.selectedPage) {
                RouteMapView(viewModel: viewModel, uiState: uiState)
                    .tag(RoutePage.routeMap)

                FollowRouteView(viewModel: viewModel)
                    .tag(RoutePage.followRoute)

                LiveMapView(viewModel: viewModel, uiState: uiState)
                    .tag(RoutePage.liveMap)

                AltitudeProfileView(viewModel: viewModel)
                    .tag(RoutePage.altitude)

                MetricsView(viewModel: viewModel, uiState: uiState)
                    .tag(RoutePage.metrics)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    @ViewBuilder
    private var focusedMapPage: some View {
        ActiveRouteChrome(uiState: uiState, viewModel: viewModel, showFinishConfirm: $showFinishConfirm) {
            switch uiState.selectedPage {
            case .routeMap:
                RouteMapView(viewModel: viewModel, uiState: uiState)
            case .liveMap:
                LiveMapView(viewModel: viewModel, uiState: uiState)
            default:
                EmptyView()
            }
        }
    }
}
