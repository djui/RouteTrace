import RouteTraceShared
import SwiftUI

/// A route or track drawn to scale (aspect preserved), centered in a rounded tile.
struct RouteShapeThumbnail: View {
    let coordinates: [GeoCoordinate]
    var color: Color = RouteAppearance.routeColor
    var size: CGFloat = 34

    init(coordinates: [GeoCoordinate], color: Color = RouteAppearance.routeColor, size: CGFloat = 34) {
        self.coordinates = coordinates
        self.color = color
        self.size = size
    }

    init(route: RoutePackage, size: CGFloat = 34) {
        self.init(coordinates: ProfileDownsampler.downsample(route.route.map(\.coordinate), maxCount: 120), size: size)
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard coordinates.count >= 2, let box = MapMath.boundingBox(for: coordinates) else { return }
            let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: canvasSize.width * 0.16, dy: canvasSize.height * 0.16)
            let longitudeScale = cos(box.center.latitude * .pi / 180)
            let width = max((box.maxLongitude - box.minLongitude) * longitudeScale, 1e-9)
            let height = max(box.maxLatitude - box.minLatitude, 1e-9)
            let scale = min(rect.width / width, rect.height / height)
            let originX = rect.midX - width * scale / 2
            let originY = rect.midY - height * scale / 2

            var path = Path()
            for (index, coordinate) in coordinates.enumerated() {
                let point = CGPoint(
                    x: originX + (coordinate.longitude - box.minLongitude) * longitudeScale * scale,
                    y: originY + (box.maxLatitude - coordinate.latitude) * scale
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}
