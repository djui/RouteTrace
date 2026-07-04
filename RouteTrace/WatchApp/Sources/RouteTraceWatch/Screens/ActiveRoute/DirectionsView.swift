import RouteTraceShared
import SwiftUI

struct DirectionsView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(spacing: 12) {
            if let snapshot = viewModel.navigationSnapshot, let cue = snapshot.nextCue {
                Image(systemName: symbol(for: cue.kind))
                    .font(.system(size: 36))
                    .foregroundStyle(snapshot.isOffRoute ? .orange : .primary)

                Text(cue.instruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let distance = snapshot.distanceToNextCueMeters {
                    Text("in \(RouteFormatting.distance(distance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("Follow the route")
                    .font(.headline)
            }

            if !isLuminanceReduced {
                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Elapsed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(RouteFormatting.duration(viewModel.elapsedSeconds))
                    }
                }

                if viewModel.navigationSnapshot?.isOffRoute == true {
                    Label("Off route", systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLuminanceReduced ? Color.black : Color.black.opacity(0.2))
    }

    private func symbol(for kind: RouteCueKind) -> String {
        switch kind {
        case .start: "flag.fill"
        case .finish: "flag.checkered"
        case .continue: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .turnLeft: "arrow.turn.up.left"
        case .turnRight: "arrow.turn.up.right"
        case .sharpLeft: "arrow.turn.left.up"
        case .sharpRight: "arrow.turn.right.up"
        case .uTurn: "arrow.uturn.up"
        }
    }
}
