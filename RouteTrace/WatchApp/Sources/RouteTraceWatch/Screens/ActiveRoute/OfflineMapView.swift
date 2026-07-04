import RouteTraceShared
import SwiftUI
import UIKit

struct OfflineMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    var showChrome: Bool = true

    @Environment(WatchRouteStore.self) private var routeStore

    @State private var tileImages: [String: CGImage] = [:]
    @State private var renderZoom = 14
    @State private var loadError: String?

    var body: some View {
        if showChrome {
            AlwaysOnAware {
                activeOfflineMap
            } dimmed: {
                ActiveRouteDimmedSummary(viewModel: viewModel)
            }
        } else {
            activeOfflineMap
        }
    }

    private var activeOfflineMap: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                Canvas { context, size in
                    drawMap(context: &context, size: size)
                }
                .background(Color(white: 0.12))

                if showChrome, viewModel.navigationSnapshot?.isOffRoute == true {
                    offRouteBanner
                }
            }
        }
        .onAppear {
            loadTiles()
        }
        .onChange(of: viewModel.navigationSnapshot?.currentCoordinate?.latitude) { _, _ in
            loadTiles()
        }
        .overlay(alignment: .bottom) {
            if let loadError {
                Text(loadError)
                    .font(.caption2)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var offRouteBanner: some View {
        Label("Off route", systemImage: "location.slash")
            .font(.caption2)
            .padding(6)
            .background(Color.orange.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .padding(.top, 4)
    }

    private func loadTiles() {
        guard let routeID = viewModel.routePackage?.id,
              let tileStore = routeStore.tileStore(for: routeID),
              let coordinate = viewModel.navigationSnapshot?.currentCoordinate ?? viewModel.routePackage?.boundingBox.center else {
            return
        }

        Task {
            do {
                let manifest = try tileStore.manifest()
                let zoom = manifest?.maxZoom ?? 0
                renderZoom = manifest != nil ? zoom : 0

                var images: [String: CGImage] = [:]
                let tiles = tileStore.tilesCovering(coordinate: coordinate, zoom: renderZoom)

                for tile in tiles {
                    let url = tileStore.tileURL(for: tile)
                    if let image = loadCGImage(from: url) {
                        images[tile.filename] = image
                    }
                }

                if images.isEmpty, renderZoom > 0 {
                    // Fallback to L0 world tile if corridor tiles are missing.
                    renderZoom = 0
                    let fallback = TileCoordinate(zoom: 0, x: 0, y: 0)
                    let url = tileStore.tileURL(for: fallback)
                    if let image = loadCGImage(from: url) {
                        images[fallback.filename] = image
                    }
                }

                tileImages = images
                loadError = images.isEmpty ? "No offline tiles — showing route only." : nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data)?.cgImage else {
            return nil
        }
        return uiImage
    }

    private func drawMap(context: inout GraphicsContext, size: CGSize) {
        guard let route = viewModel.routePackage else { return }

        if renderZoom == 0 {
            drawL0Fallback(context: &context, size: size, route: route)
        } else if let coordinate = viewModel.navigationSnapshot?.currentCoordinate ?? Optional(route.boundingBox.center) {
            drawTiles(context: &context, size: size, center: coordinate, route: route)
        }

        drawRouteOverlay(context: &context, size: size, route: route)
    }

    private func drawL0Fallback(context: inout GraphicsContext, size: CGSize, route: RoutePackage) {
        if let image = tileImages[TileCoordinate(zoom: 0, x: 0, y: 0).filename] {
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
        } else {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.15)))
        }

        let box = route.boundingBox
        let routeRect = CGRect(
            x: size.width * 0.15,
            y: size.height * 0.2,
            width: size.width * 0.7,
            height: size.height * 0.6
        )
        var routePath = Path()
        for (index, point) in route.route.enumerated() {
            let nx = (point.longitude - box.minLongitude) / max(0.0001, box.maxLongitude - box.minLongitude)
            let ny = 1 - (point.latitude - box.minLatitude) / max(0.0001, box.maxLatitude - box.minLatitude)
            let pt = CGPoint(x: routeRect.minX + routeRect.width * nx, y: routeRect.minY + routeRect.height * ny)
            if index == 0 { routePath.move(to: pt) } else { routePath.addLine(to: pt) }
        }
        context.stroke(routePath, with: .color(.blue.opacity(0.8)), lineWidth: 2)
    }

    private func drawTiles(
        context: inout GraphicsContext,
        size: CGSize,
        center: GeoCoordinate,
        route: RoutePackage
    ) {
        guard let tileStore = routeStore.tileStore(for: route.id) else { return }
        let tile = tileStore.tilesCovering(coordinate: center, zoom: renderZoom).first ?? TileCoordinate(zoom: renderZoom, x: 0, y: 0)

        if let image = tileImages[tile.filename] {
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
        }
    }

    private func drawRouteOverlay(context: inout GraphicsContext, size: CGSize, route: RoutePackage) {
        guard renderZoom > 0,
              let tileStore = routeStore.tileStore(for: route.id),
              let center = viewModel.navigationSnapshot?.currentCoordinate ?? Optional(route.boundingBox.center) else { return }

        let tile = tileStore.tilesCovering(coordinate: center, zoom: renderZoom).first
            ?? TileCoordinate(zoom: renderZoom, x: MapMath.tileX(longitude: center.longitude, zoom: renderZoom), y: MapMath.tileY(latitude: center.latitude, zoom: renderZoom))

        var path = Path()
        for (index, point) in route.route.enumerated() {
            let pixel = MapMath.coordinateToPixel(
                coordinate: point.coordinate,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let pt = CGPoint(
                x: size.width * pixel.x / 256,
                y: size.height * pixel.y / 256
            )
            if index == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        context.stroke(path, with: .color(.blue), lineWidth: 2)

        let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)
        if actual.count >= 2 {
            var actualPath = Path()
            for (index, coordinate) in actual.enumerated() {
                let geo = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let pixel = MapMath.coordinateToPixel(
                    coordinate: geo,
                    tileX: tile.x,
                    tileY: tile.y,
                    zoom: renderZoom
                )
                let pt = CGPoint(x: size.width * pixel.x / 256, y: size.height * pixel.y / 256)
                if index == 0 { actualPath.move(to: pt) } else { actualPath.addLine(to: pt) }
            }
            context.stroke(actualPath, with: .color(.green), lineWidth: 2)
        }

        for event in viewModel.recording.offRouteEvents {
            let pixel = MapMath.coordinateToPixel(
                coordinate: event.coordinate,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let pt = CGPoint(x: size.width * pixel.x / 256, y: size.height * pixel.y / 256)
            context.fill(
                Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                with: .color(event.endedAt == nil ? .red : .orange)
            )
        }

        if let current = viewModel.navigationSnapshot?.currentCoordinate {
            let pixel = MapMath.coordinateToPixel(
                coordinate: current,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let pt = CGPoint(x: size.width * pixel.x / 256, y: size.height * pixel.y / 256)
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)), with: .color(.green))
        }
    }
}
