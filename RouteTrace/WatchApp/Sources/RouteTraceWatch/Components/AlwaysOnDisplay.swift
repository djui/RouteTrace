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

struct ActiveRouteDimmedSummary: View {
  @Bindable var viewModel: ActiveRouteViewModel

  var body: some View {
    VStack(spacing: 8) {
      if let snapshot = viewModel.navigationSnapshot, let cue = snapshot.nextCue {
        Image(systemName: symbol(for: cue.kind))
          .font(.title2)
          .foregroundStyle(snapshot.isOffRoute ? .orange : .primary)

        Text(cue.instruction)
          .font(.headline)
          .multilineTextAlignment(.center)
          .lineLimit(2)

        if let distance = snapshot.distanceToNextCueMeters {
          Text("in \(RouteFormatting.distance(distance))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Text(viewModel.routePackage?.name ?? "Active Route")
          .font(.headline)
          .lineLimit(1)

        Text("\(Int(viewModel.progressFraction * 100))%")
          .font(.title3)
      }

      HStack {
        Text(RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0))
        Spacer()
        Text(RouteFormatting.duration(viewModel.elapsedSeconds))
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      if viewModel.navigationSnapshot?.isOffRoute == true {
        Label("Off route", systemImage: "location.slash")
          .font(.caption2)
          .foregroundStyle(.orange)
      } else if viewModel.isPaused {
        Label("Paused", systemImage: "pause.fill")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
    .background(Color.black)
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
