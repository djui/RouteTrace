import RouteTraceShared
import SwiftUI

struct AlwaysOnAware<Full: View, Dimmed: View>: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @ViewBuilder let full: () -> Full
    @ViewBuilder let dimmed: () -> Dimmed

    var body: some View {
        if isLuminanceReduced {
            dimmed()
        } else {
            full()
        }
    }
}

/// Low-power view for Always On: the next instruction, distance left and a system-driven timer.
struct ActiveRouteDimmedSummary: View {
    @Bindable var viewModel: ActiveRouteViewModel

    var body: some View {
        VStack(spacing: 6) {
            if let guidance = viewModel.rejoinGuidance {
                Image(systemName: "location.slash")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("Route \(RouteFormatting.distance(guidance.distanceMeters)) \(guidance.compassDirection)")
                    .font(.headline)
                    .foregroundStyle(.orange)
            } else if let snapshot = viewModel.navigationSnapshot, let cue = snapshot.nextCue {
                Image(systemName: ActiveRouteMapOverlay.cueSymbol(for: cue.kind))
                    .font(.title2)
                if let distance = snapshot.distanceToNextCueMeters {
                    Text(RouteFormatting.distance(distance))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                }
                Text(cue.kind == .finish ? "Finish" : cue.instruction)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(viewModel.routePackage?.name ?? "Route")
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            HStack {
                Text(RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0))
                Spacer()
                elapsedText
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()

            if viewModel.isPaused {
                Label("Paused", systemImage: "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .routeScreenBackground()
    }

    /// Updated by the system while dimmed, without waking the app every second.
    @ViewBuilder
    private var elapsedText: some View {
        if viewModel.isPaused || viewModel.phase != .active {
            Text(RouteFormatting.duration(viewModel.elapsedSeconds))
        } else {
            let start = Date().addingTimeInterval(-viewModel.elapsedSeconds)
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        }
    }
}
