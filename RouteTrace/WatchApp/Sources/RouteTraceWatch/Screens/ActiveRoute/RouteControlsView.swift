import RouteTraceShared
import SwiftUI
import WatchKit

struct RouteControlsView: View {
    @Bindable var viewModel: ActiveRouteViewModel

    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            VStack(spacing: 10) {
                Text(RouteFormatting.duration(viewModel.elapsedSeconds))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(viewModel.isPaused ? .orange : .yellow)
                    .monospacedDigit()
                    .padding(.top, 18)

                HStack(spacing: 10) {
                    controlButton(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill",
                        tint: viewModel.isPaused ? .green : .orange
                    ) {
                        viewModel.togglePauseResume(preferences: preferences)
                    }

                    controlButton("Lock", systemImage: "drop.fill", tint: .cyan) {
                        // Ignores taps from rain and sweat; turn the crown to unlock.
                        WKInterfaceDevice.current().enableWaterLock()
                    }
                    .disabled(!viewModel.workoutService.isSessionActive)
                }

                Button {
                    viewModel.prepareSummary(preferences: preferences)
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .routeGlassButton(prominent: true, tint: .red)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .routeScreenBackground()
        }
    }

    private func controlButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .routeGlassButton(tint: tint)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}
