import RouteTraceShared
import SwiftUI

struct RouteControlsView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            VStack(spacing: 12) {
                Spacer(minLength: 20)

                Button {
                    viewModel.togglePauseResume(preferences: preferences)
                } label: {
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isPaused ? .green : .orange)

                Button {
                    viewModel.prepareSummary(preferences: preferences)
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .routeScreenBackground()
        }
    }
}
