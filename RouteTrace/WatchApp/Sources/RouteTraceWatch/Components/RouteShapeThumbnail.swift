import RouteTraceShared
import SwiftUI

struct RouteShapeThumbnail: View {
    let route: RoutePackage
    var size: CGFloat = 32

    var body: some View {
        Canvas { context, canvasSize in
            let box = route.boundingBox
            let inset: CGFloat = 3
            let drawRect = CGRect(
                x: inset,
                y: inset,
                width: canvasSize.width - inset * 2,
                height: canvasSize.height - inset * 2
            )

            var path = Path()
            for (index, point) in route.route.enumerated() {
                let nx = (point.longitude - box.minLongitude) / max(0.0001, box.maxLongitude - box.minLongitude)
                let ny = 1 - (point.latitude - box.minLatitude) / max(0.0001, box.maxLatitude - box.minLatitude)
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

            context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
