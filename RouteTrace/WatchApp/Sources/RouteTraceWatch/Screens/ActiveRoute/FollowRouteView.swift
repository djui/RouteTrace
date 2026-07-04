import RouteTraceShared
import SwiftUI

struct FollowRouteView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isOffRoute: Bool {
        viewModel.navigationSnapshot?.isOffRoute == true
    }

    var body: some View {
        if isLuminanceReduced {
            ActiveRouteDimmedSummary(viewModel: viewModel)
        } else {
            followContent
        }
    }

    private var followContent: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 24)

            if isOffRoute {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)

                Text("Off Route")
                    .font(.title3.weight(.semibold))

                Text("Return to the blue route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)

                Text("On Route")
                    .font(.title3.weight(.semibold))

                Text("You're on track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOffRoute ? "From route" : "Remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(isOffRoute
                         ? RouteFormatting.distance(viewModel.navigationSnapshot?.offRouteDistanceMeters ?? 0)
                         : RouteFormatting.distance(viewModel.navigationSnapshot?.distanceRemainingMeters ?? 0))
                        .font(.body.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Elapsed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(RouteFormatting.duration(viewModel.elapsedSeconds))
                        .font(.body.weight(.semibold))
                }
            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
