import RouteTraceShared
import SwiftUI

/// Turn-by-turn at a glance; when off the route, points the way back to it.
struct DirectionsView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 20)

            if let guidance = viewModel.rejoinGuidance {
                rejoinContent(guidance)
            } else if let snapshot = viewModel.navigationSnapshot, let cue = snapshot.nextCue {
                cueContent(cue, distance: snapshot.distanceToNextCueMeters)
            } else {
                symbolBadge("checkmark", tint: .green)
                Text("Follow the route")
                    .font(.headline)
            }

            Spacer(minLength: 4)

            if !isLuminanceReduced {
                footer
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .routeScreenBackground()
    }

    @ViewBuilder
    private func cueContent(_ cue: RouteCue, distance: Double?) -> some View {
        let isFinish = cue.kind == .finish
        symbolBadge(ActiveRouteMapOverlay.cueSymbol(for: cue.kind), tint: isFinish ? .red : RouteAppearance.routeColor)

        if let distance {
            Text(RouteFormatting.distance(distance))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        Text(isFinish ? "Finish" : cue.instruction)
            .font(.headline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func rejoinContent(_ guidance: RejoinGuidance) -> some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.2))
            Image(systemName: guidance.relativeBearingDegrees == nil ? "location.north.fill" : "arrow.up")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(guidance.relativeBearingDegrees ?? guidance.bearingDegrees))
                .animation(.snappy, value: guidance.relativeBearingDegrees ?? guidance.bearingDegrees)
        }
        .frame(width: 58, height: 58)

        Text(RouteFormatting.distance(guidance.distanceMeters))
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .foregroundStyle(.orange)
            .monospacedDigit()
            .contentTransition(.numericText())
        Text(guidance.relativeBearingDegrees == nil ? "Route is \(guidance.compassDirection)" : "Back to route")
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func symbolBadge(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(tint.gradient, in: Circle())
            .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0))
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("Time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(RouteFormatting.duration(viewModel.elapsedSeconds))
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
        }
        .monospacedDigit()
    }
}
