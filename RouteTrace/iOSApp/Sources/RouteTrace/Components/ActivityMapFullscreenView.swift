import SwiftUI
import RouteTraceShared

struct ActivityMapFullscreenView: View {
    @Environment(\.dismiss) private var dismiss

    let routeName: String
    let distanceLabel: String
    let routePoints: [RoutePoint]
    let trackPoints: [TrackPoint]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RouteMapPreview(
                routePoints: routePoints,
                trackPoints: trackPoints,
                lineColor: .blue.opacity(0.55),
                trackColor: .green
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 4) {
                Text(routeName)
                    .font(.headline)
                Text(distanceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
    }
}
