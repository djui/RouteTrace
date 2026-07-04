import RouteTraceShared
import SwiftUI

struct ActivityTrackThumbnail: View {
    let trackPoints: [TrackPoint]
    var size: CGFloat = 40

    private var boundingBox: GeoBoundingBox? {
        guard !trackPoints.isEmpty else { return nil }
        let latitudes = trackPoints.map(\.latitude)
        let longitudes = trackPoints.map(\.longitude)
        return GeoBoundingBox(
            minLatitude: latitudes.min() ?? 0,
            maxLatitude: latitudes.max() ?? 0,
            minLongitude: longitudes.min() ?? 0,
            maxLongitude: longitudes.max() ?? 0
        )
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard trackPoints.count >= 2, let box = boundingBox else { return }

            let inset: CGFloat = 3
            let drawRect = CGRect(
                x: inset,
                y: inset,
                width: canvasSize.width - inset * 2,
                height: canvasSize.height - inset * 2
            )

            var path = Path()
            for (index, point) in trackPoints.enumerated() {
                let nx = (point.longitude - box.minLongitude)
                    / max(0.0001, box.maxLongitude - box.minLongitude)
                let ny = 1 - (point.latitude - box.minLatitude)
                    / max(0.0001, box.maxLatitude - box.minLatitude)
                let pt = CGPoint(
                    x: drawRect.minX + drawRect.width * nx,
                    y: drawRect.minY + drawRect.height * ny
                )
                if index == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
            }

            context.stroke(
                path,
                with: .color(.green),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if trackPoints.count < 2 {
                Image(systemName: "figure.run")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
