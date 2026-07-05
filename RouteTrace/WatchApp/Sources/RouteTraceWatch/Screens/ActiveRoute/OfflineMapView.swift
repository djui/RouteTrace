import RouteTraceShared
import SwiftUI
import UIKit

struct OfflineMapView: View {
    @Bindable var viewModel: ActiveRouteViewModel
    var uiState: ActiveRouteUIState?
    var showChrome: Bool = true
    var allowsHitTesting: Bool = true
    var recenterToken: Int = 0

    @Environment(WatchRouteStore.self) private var routeStore
    @Environment(WatchPreferences.self) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    @State private var tileImages: [String: CGImage] = [:]
    @State private var renderZoom = 14
    @State private var activeTile = TileCoordinate(zoom: 0, x: 0, y: 0)
    @State private var loadError: String?
    @State private var localSpan: Double = 0.012
    @State private var tileScale: CGFloat = 1
    @State private var panBaseOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    private var totalPanOffset: CGSize {
        CGSize(
            width: panBaseOffset.width + dragOffset.width,
            height: panBaseOffset.height + dragOffset.height
        )
    }

    private var isMapFocused: Bool {
        uiState?.isMapFocus == true
    }

    private var isMapVisible: Bool {
        uiState?.selectedPage == .liveMap || isMapFocused
    }

    private var batteryPolicy: BatteryModePolicy {
        BatteryModePolicy.policy(userMode: preferences.batteryMode)
    }

    private var currentSpan: Double {
        uiState?.mapSpan ?? localSpan
    }

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

    @ViewBuilder
    private var activeOfflineMap: some View {
        let map = GeometryReader { _ in
            ZStack(alignment: .top) {
                canvasLayer

                if showChrome, viewModel.navigationSnapshot?.isOffRoute == true {
                    offRouteBanner
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { loadTiles() }
        .onChange(of: viewModel.displayCoordinate?.latitude) { _, _ in
            handleLocationUpdate()
        }
        .onChange(of: viewModel.displayCoordinate?.longitude) { _, _ in
            handleLocationUpdate()
        }
        .onChange(of: currentSpan) { _, _ in
            loadTiles()
        }
        .onChange(of: recenterToken) { _, _ in
            resetPanOffset()
            loadTiles()
        }
        .overlay(alignment: .bottom) {
            if let loadError {
                Text(loadError)
                    .font(.caption2)
                    .padding(4)
                    .routeMapOverlayBackground(in: Capsule())
            }
        }

        if showChrome {
            map
                .focusable(isMapFocused)
                .digitalCrownRotation(
                    spanBinding,
                    from: 0.002,
                    through: 0.04,
                    by: RouteAppearance.mapCrownStep,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: isMapFocused
                )
        } else {
            map
        }
    }

    @ViewBuilder
    private var canvasLayer: some View {
        let canvas = Canvas { context, size in
            var transformed = context
            transformed.translateBy(x: totalPanOffset.width, y: totalPanOffset.height)
            drawMap(context: &transformed, size: size)
        }
        .background(RouteAppearance.offlineMapCanvas(for: colorScheme))
        .allowsHitTesting(allowsHitTesting)

        if isMapFocused {
            canvas.gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let total = CGSize(
                            width: panBaseOffset.width + value.translation.width,
                            height: panBaseOffset.height + value.translation.height
                        )
                        commitPanAfterDrag(total)
                        dragOffset = .zero
                    }
            )
        } else {
            canvas
        }
    }

    private var offRouteBanner: some View {
        Label("Off route", systemImage: "location.slash")
            .font(.caption2)
            .padding(6)
            .foregroundStyle(.white)
            .glassEffect(RouteAppearance.mapOverlayGlass.tint(.orange), in: .capsule)
            .padding(.top, 4)
    }

    private func resetPanOffset() {
        panBaseOffset = .zero
        dragOffset = .zero
    }

    private func handleLocationUpdate() {
        guard let coordinate = viewModel.displayCoordinate else { return }
        guard preferences.mapFollowMode || isMapFocused else { return }

        let policy = batteryPolicy.displayUpdatePolicy
        guard viewModel.displayUpdateCoordinator.shouldRecenter(
            policy: policy,
            coordinate: coordinate,
            isMapVisible: isMapVisible,
            followEnabled: preferences.mapFollowMode || isMapFocused
        ) else {
            return
        }

        viewModel.displayUpdateCoordinator.recordRecenter(at: coordinate)

        if !isMapFocused {
            resetPanOffset()
            loadTiles()
        } else if panBaseOffset == .zero && dragOffset == .zero {
            loadTiles()
        }
    }

    private func commitPanAfterDrag(_ total: CGSize) {
        let threshold: CGFloat = 128
        var dx = 0
        var dy = 0

        if total.width > threshold {
            dx = 1
        } else if total.width < -threshold {
            dx = -1
        }

        if total.height > threshold {
            dy = 1
        } else if total.height < -threshold {
            dy = -1
        }

        if dx != 0 || dy != 0 {
            activeTile = TileCoordinate(
                zoom: activeTile.zoom,
                x: activeTile.x + dx,
                y: activeTile.y + dy
            )
            resetPanOffset()
            loadTiles()
        } else {
            panBaseOffset = total
        }
    }

    private func loadTiles() {
        guard let routeID = viewModel.routePackage?.id,
              let tileStore = routeStore.tileStore(for: routeID),
              let coordinate = viewModel.displayCoordinate ?? viewModel.routePackage?.boundingBox.center else {
            return
        }

        Task {
            let manifest = try? tileStore.manifest()
            let zoomRequest = desiredZoom(from: currentSpan, manifest: manifest)
            tileScale = zoomRequest.scale
            let result = tileStore.tileAtZoom(
                for: coordinate,
                preferredZoom: zoomRequest.zoom,
                manifest: manifest
            )

            if let result {
                renderZoom = result.zoom
                activeTile = result.tile
                var images: [String: CGImage] = [:]
                var usedFallback = result.usedFallback

                for tile in tileStore.neighboringTiles(around: result.tile, radius: 1) {
                    guard tileStore.tileExists(tile),
                          let image = loadCGImage(from: tileStore.tileURL(for: tile)) else {
                        continue
                    }
                    images[tile.filename] = image
                }

                if images.isEmpty, let image = loadCGImage(from: tileStore.tileURL(for: result.tile)) {
                    images[result.tile.filename] = image
                } else if images.isEmpty {
                    usedFallback = true
                }

                tileImages = images
                loadError = usedFallback ? "Partial offline map" : nil
            } else {
                renderZoom = 0
                activeTile = TileCoordinate(zoom: 0, x: 0, y: 0)
                tileScale = 1
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

    private func desiredZoom(from span: Double, manifest: OfflineMapManifest?) -> (zoom: Int, scale: CGFloat) {
        let minZ = manifest?.minZoom ?? 10
        let maxZ = manifest?.maxZoom ?? 16
        let minSpan = 0.002
        let maxSpan = 0.04
        let clampedSpan = min(max(span, minSpan), maxSpan)
        let fraction = (maxSpan - clampedSpan) / (maxSpan - minSpan)
        let continuousZoom = Double(minZ) + fraction * Double(maxZ - minZ)
        let zoom = Int(continuousZoom.rounded(.down))
        let scale = CGFloat(pow(2, continuousZoom - Double(zoom)))
        return (min(maxZ, max(minZ, zoom)), scale)
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
            return
        }

        guard let coordinate = viewModel.displayCoordinate ?? Optional(route.boundingBox.center) else {
            return
        }

        if tileScale != 1 {
            let anchor = CGPoint(x: size.width / 2, y: size.height / 2)
            context.translateBy(x: anchor.x, y: anchor.y)
            context.scaleBy(x: tileScale, y: tileScale)
            context.translateBy(x: -anchor.x, y: -anchor.y)
        }

        drawTiles(context: &context, size: size, center: coordinate)
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
            x: size.width * 0.05,
            y: size.height * 0.05,
            width: size.width * 0.9,
            height: size.height * 0.9
        )
        let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
        let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)
        let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)

        strokePath(context: &context, coordinates: split.remaining, box: box, routeRect: routeRect, color: .blue)
        strokePath(context: &context, coordinates: actual, box: box, routeRect: routeRect, color: .green)
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
        context.stroke(
            path,
            with: .color(RouteAppearance.routeOutlineColor),
            style: StrokeStyle(lineWidth: RouteAppearance.routeOutlineWidth, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: RouteAppearance.routeStrokeWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawTiles(
        context: inout GraphicsContext,
        size: CGSize,
        center: GeoCoordinate
    ) {
        guard !tileImages.isEmpty else { return }

        let userPixel = MapMath.coordinateToPixel(
            coordinate: center,
            tileX: activeTile.x,
            tileY: activeTile.y,
            zoom: renderZoom
        )
        let userPoint = CGPoint(x: size.width * userPixel.x / 256, y: size.height * userPixel.y / 256)
        let centerOffset = CGPoint(x: size.width / 2 - userPoint.x, y: size.height / 2 - userPoint.y)

        guard let routeID = viewModel.routePackage?.id,
              let tileStore = routeStore.tileStore(for: routeID) else {
            return
        }

        for tile in tileStore.neighboringTiles(around: activeTile, radius: 1) {
            guard let image = tileImages[tile.filename] else { continue }

            let dx = tile.x - activeTile.x
            let dy = tile.y - activeTile.y
            let origin = CGPoint(
                x: centerOffset.x + CGFloat(dx) * size.width,
                y: centerOffset.y + CGFloat(dy) * size.height
            )
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: origin, size: size))
        }
    }

    private func drawRouteOverlay(context: inout GraphicsContext, size: CGSize, route: RoutePackage) {
        guard renderZoom > 0 else { return }

        let tile = activeTile
        let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
        let split = ActiveRouteMapOverlay.splitRouteCoordinates(route, atProgressMeters: progress)
        let actual = ActiveRouteMapOverlay.actualTrackCoordinates(from: viewModel)

        strokeProjectedPath(context: &context, coordinates: split.remaining, tile: tile, size: size, color: .blue)
        strokeProjectedPath(context: &context, coordinates: actual, tile: tile, size: size, color: .green)

        if let display = viewModel.upcomingCueDisplay {
            let cue = display.cue
            let pixel = MapMath.coordinateToPixel(
                coordinate: cue.coordinate,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let userPixel = viewModel.displayCoordinate.map {
                MapMath.coordinateToPixel(
                    coordinate: $0,
                    tileX: tile.x,
                    tileY: tile.y,
                    zoom: renderZoom
                )
            }
            let userPoint = userPixel.map {
                CGPoint(x: size.width * $0.x / 256, y: size.height * $0.y / 256)
            } ?? CGPoint(x: size.width / 2, y: size.height / 2)
            let centerOffset = CGPoint(x: size.width / 2 - userPoint.x, y: size.height / 2 - userPoint.y)
            let pt = CGPoint(
                x: centerOffset.x + size.width * pixel.x / 256,
                y: centerOffset.y + size.height * pixel.y / 256
            )
            drawTurnMarker(&context, at: pt, bearing: cue.bearingAfter, kind: cue.kind)
        }

        if viewModel.displayCoordinate != nil {
            let heading = ActiveRouteMapOverlay.resolvedHeadingDegrees(
                courseDegrees: viewModel.locationService.lastSample?.courseDegrees,
                fallbackBearing: viewModel.navigationSnapshot?.nextCue?.bearingAfter
            )
            drawUserHeadingMarker(&context, at: CGPoint(x: size.width / 2, y: size.height / 2), headingDegrees: heading)
        }
    }

    private func drawUserHeadingMarker(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        headingDegrees: Double
    ) {
        let size: CGFloat = 18
        let dotSize = size * 0.55
        let ringSize = size
        let wedgeLength = size * 0.38

        var wedgeContext = context
        wedgeContext.translateBy(x: point.x, y: point.y)
        wedgeContext.rotate(by: .degrees(headingDegrees))

        var wedge = Path()
        wedge.move(to: CGPoint(x: 0, y: -ringSize / 2 - wedgeLength))
        wedge.addLine(to: CGPoint(x: -wedgeLength * 0.55, y: -ringSize / 2))
        wedge.addLine(to: CGPoint(x: wedgeLength * 0.55, y: -ringSize / 2))
        wedge.closeSubpath()
        wedgeContext.fill(wedge, with: .color(.white))

        let ringRect = CGRect(
            x: point.x - ringSize / 2,
            y: point.y - ringSize / 2,
            width: ringSize,
            height: ringSize
        )
        context.stroke(Path(ellipseIn: ringRect), with: .color(.white), lineWidth: 2.5)

        let dotRect = CGRect(
            x: point.x - dotSize / 2,
            y: point.y - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        context.fill(Path(ellipseIn: dotRect), with: .color(.blue))
    }

    private func drawTurnMarker(
        _ context: inout GraphicsContext,
        at point: CGPoint,
        bearing: Double,
        kind: RouteCueKind
    ) {
        let markerSize: CGFloat = 32
        let rect = CGRect(
            x: point.x - markerSize / 2,
            y: point.y - markerSize / 2,
            width: markerSize,
            height: markerSize
        )
        context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.82)))
        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)

        let rotation = ActiveRouteMapOverlay.shouldRotateCueSymbol(kind) ? bearing : 0
        let symbolName = ActiveRouteMapOverlay.cueSymbol(for: kind)

        var symbolContext = context
        symbolContext.translateBy(x: point.x, y: point.y)
        symbolContext.rotate(by: .degrees(rotation))

        let resolved = symbolContext.resolve(
            Text(Image(systemName: symbolName))
                .font(.system(size: markerSize * 0.45, weight: .black))
                .foregroundStyle(.white)
        )
        symbolContext.draw(resolved, at: .zero, anchor: .center)
    }

    private func strokeProjectedPath(
        context: inout GraphicsContext,
        coordinates: [CLLocationCoordinate2D],
        tile: TileCoordinate,
        size: CGSize,
        color: Color
    ) {
        guard coordinates.count >= 2 else { return }

        let userPixel = viewModel.displayCoordinate.map {
            MapMath.coordinateToPixel(
                coordinate: $0,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
        }
        let userPoint = userPixel.map {
            CGPoint(x: size.width * $0.x / 256, y: size.height * $0.y / 256)
        } ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let centerOffset = CGPoint(x: size.width / 2 - userPoint.x, y: size.height / 2 - userPoint.y)

        var path = Path()
        for (index, coordinate) in coordinates.enumerated() {
            let geo = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let pixel = MapMath.coordinateToPixel(
                coordinate: geo,
                tileX: tile.x,
                tileY: tile.y,
                zoom: renderZoom
            )
            let pt = CGPoint(
                x: centerOffset.x + size.width * pixel.x / 256,
                y: centerOffset.y + size.height * pixel.y / 256
            )
            if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        context.stroke(
            path,
            with: .color(RouteAppearance.routeOutlineColor),
            style: StrokeStyle(lineWidth: RouteAppearance.routeOutlineWidth, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: RouteAppearance.routeStrokeWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
