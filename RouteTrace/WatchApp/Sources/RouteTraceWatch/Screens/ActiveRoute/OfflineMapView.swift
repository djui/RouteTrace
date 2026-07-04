import RouteTraceShared
import SwiftUI
import UIKit

struct OfflineMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    var uiState: ActiveRouteUIState?
    var showChrome: Bool = true

    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var tileImages: [String: CGImage] = [:]
    @State private var renderZoom = 14
    @State private var activeTile = TileCoordinate(zoom: 0, x: 0, y: 0)
    @State private var loadError: String?
    @State private var localSpan: Double = 0.012

    private var spanBinding: Binding<Double> {
        if let uiState {
            Binding(
                get: { uiState.mapSpan },
                set: { uiState.mapSpan = $0 }
            )
        } else {
            $localSpan
        }
    }

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
                .background(RouteAppearance.offlineMapCanvas(for: colorScheme))

                if showChrome, viewModel.navigationSnapshot?.isOffRoute == true {
                    offRouteBanner
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(true)
        .digitalCrownRotation(
            spanBinding,
            from: 0.002,
            through: 0.04,
            by: 0.001,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear { loadTiles() }
        .onChange(of: viewModel.navigationSnapshot?.currentCoordinate?.latitude) { _, _ in
            loadTiles()
        }
        .onChange(of: spanBinding.wrappedValue) { _, _ in
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
            let manifest = try? tileStore.manifest()
            let result = tileStore.bestAvailableTile(for: coordinate, manifest: manifest)

            if let result {
                renderZoom = result.zoom
                activeTile = result.tile
                if let image = loadCGImage(from: tileStore.tileURL(for: result.tile)) {
                    tileImages = [result.tile.filename: image]
                    loadError = result.usedFallback ? "Partial offline map" : nil
                } else {
                    tileImages = [:]
                    loadError = "Partial offline map"
                }
            } else {
                renderZoom = 0
                activeTile = TileCoordinate(zoom: 0, x: 0, y: 0)
                let fallbackURL = tileStore.tileURL(for: activeTile)
                if let image = loadCGImage(from: fallbackURL) {
                    tileImages = [activeTile.filename: image]
                    loadError = nil
                } else {
                    tileImages = [:]
                    loadError = "Partial offline map"
                }
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
        let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
        let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)
        strokePath(context: &context, coordinates: split.traveled, box: box, routeRect: routeRect, color: .green)
        strokePath(context: &context, coordinates: split.remaining, box: box, routeRect: routeRect, color: .blue)
    }

    private func strokePath(
        context: inout GraphicsContext,
        coordinates: [CLLocationCoordinate2D],
        box: GeoBoundingBox,
        routeRect: CGRect,
        color: Color
    ) {
        guard coordinates.count >= 2 else { return }
        var path = Path()
        for (index, coordinate) in coordinates.enumerated() {
            let nx = (coordinate.longitude - box.minLongitude) / max(0.0001, box.maxLongitude - box.minLongitude)
            let ny = 1 - (coordinate.latitude - box.minLatitude) / max(0.0001, box.maxLatitude - box.minLatitude)
            let pt = CGPoint(x: routeRect.minX + routeRect.width * nx, y: routeRect.minY + routeRect.height * ny)
            if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 4)
        context.stroke(path, with: .color(color), lineWidth: 2.5)
    }

    private func drawTiles(
        context: inout GraphicsContext,
        size: CGSize,
        center: GeoCoordinate,
        route: RoutePackage
    ) {
        if let image = tileImages[activeTile.filename] {
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
        }
    }

    private func drawRouteOverlay(context: inout GraphicsContext, size: CGSize, route: RoutePackage) {
        guard renderZoom > 0 else { return }

        let tile = activeTile
        let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
        let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)

        strokeProjectedPath(context: &context, coordinates: split.traveled, tile: tile, size: size, color: .green)
        strokeProjectedPath(context: &context, coordinates: split.remaining, tile: tile, size: size, color: .blue)

        if let snapshot = viewModel.navigationSnapshot,
           let cue = snapshot.nextCue,
           let distance = snapshot.distanceToNextCueMeters,
           distance <= 500 {
            let pixel = MapMath.coordinateToPixel(
                coordinate: cue.coordinate,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let pt = CGPoint(x: size.width * pixel.x / 256, y: size.height * pixel.y / 256)
            context.fill(
                Path(ellipseIn: CGRect(x: pt.x - 10, y: pt.y - 10, width: 20, height: 20)),
                with: .color(.black.opacity(0.75))
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
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(.blue))
            context.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(.white), lineWidth: 1.5)
        }
    }

    private func strokeProjectedPath(
        context: inout GraphicsContext,
        coordinates: [CLLocationCoordinate2D],
        tile: TileCoordinate,
        size: CGSize,
        color: Color
    ) {
        guard coordinates.count >= 2 else { return }
        var path = Path()
        for (index, coordinate) in coordinates.enumerated() {
            let geo = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let pixel = MapMath.coordinateToPixel(
                coordinate: geo,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let pt = CGPoint(x: size.width * pixel.x / 256, y: size.height * pixel.y / 256)
            if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 4)
        context.stroke(path, with: .color(color), lineWidth: 2.5)
    }
}
