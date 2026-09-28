import CoreGraphics
import ImageIO
import RouteTraceShared
import SwiftUI

/// Route map drawn in Web Mercator, used for offline tiles and the route-only view.
///
/// Tiles are square and positioned exactly; zoom follows the crown continuously (the same
/// span semantics as the MapKit map); missing tiles fall back to the parent zoom level.
struct WatchMapCanvas: View {
    @Bindable var viewModel: ActiveRouteViewModel
    @Bindable var uiState: ActiveRouteUIState
    let tileStore: OfflineTileStore?
    var isInteractive = false
    var headingUp = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var tiles = TileImageCache()
    @State private var geometry = RouteGeometryCache()
    @State private var panOffset: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero

    private static let tileSide: Double = 256

    var body: some View {
        GeometryReader { proxy in
            let frame = frameState(size: proxy.size)
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                draw(frame, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(panGesture, including: isInteractive ? .all : .none)
            .task(id: frame.tileRequest) {
                await tiles.load(frame.tileRequest.tiles, from: tileStore)
            }
        }
        .onChange(of: isInteractive) { _, interactive in
            if !interactive {
                withAnimation(.snappy) { panOffset = .zero }
            }
        }
        .onChange(of: viewModel.routePackage?.id) { _, _ in
            geometry.reset()
            tiles.removeAll()
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { dragTranslation = $0.translation }
            .onEnded { value in
                panOffset.width += value.translation.width
                panOffset.height += value.translation.height
                dragTranslation = .zero
            }
    }

    // MARK: - Frame state

    /// Everything a frame needs, derived once per render.
    private struct FrameState {
        let zoom: Double
        let tileZoom: Int
        let scale: Double
        let center: (x: Double, y: Double)
        let rotationDegrees: Double
        let tileRequest: TileRequest
    }

    struct TileRequest: Hashable {
        let tiles: [TileCoordinate]
    }

    private func frameState(size: CGSize) -> FrameState {
        let route = viewModel.routePackage
        let focus = viewModel.displayCoordinate ?? route?.boundingBox.center ?? GeoCoordinate(latitude: 0, longitude: 0)
        let visibleMeters = uiState.mapSpan * 111_000
        let zoom = MapMath.zoomLevel(
            showingMeters: visibleMeters,
            acrossPoints: max(size.height, 1),
            tileSidePoints: Self.tileSide,
            latitude: focus.latitude
        )

        let manifest = tiles.manifest(for: tileStore)
        let minZoom = manifest?.minZoom ?? 0
        let maxZoom = manifest?.maxZoom ?? 18
        let tileZoom = min(maxZoom, max(minZoom, Int(zoom.rounded(.down))))
        let scale = pow(2, zoom - Double(tileZoom))

        var center = MapMath.tileUnits(for: focus, zoom: Double(tileZoom))
        let pan = CGSize(width: panOffset.width + dragTranslation.width, height: panOffset.height + dragTranslation.height)
        center.x -= pan.width / (Self.tileSide * scale)
        center.y -= pan.height / (Self.tileSide * scale)

        let rotation = (headingUp && !isInteractive) ? -(viewModel.courseDegrees ?? 0) : 0

        var wanted: [TileCoordinate] = []
        if tileStore != nil, size.width > 0 {
            // Cover the diagonal so rotated maps have no empty corners.
            let halfExtent = (hypot(size.width, size.height) / 2) / (Self.tileSide * scale) + 0.5
            let maxIndex = Int(pow(2, Double(tileZoom))) - 1
            for layer in [tileZoom - 1, tileZoom] where layer >= minZoom {
                let factor = pow(2, Double(layer - tileZoom))
                let cx = center.x * factor
                let cy = center.y * factor
                let extent = halfExtent * factor
                let layerMax = layer == tileZoom ? maxIndex : Int(pow(2, Double(layer))) - 1
                for x in max(0, Int(floor(cx - extent)))...min(layerMax, Int(floor(cx + extent))) {
                    for y in max(0, Int(floor(cy - extent)))...min(layerMax, Int(floor(cy + extent))) {
                        wanted.append(TileCoordinate(zoom: layer, x: x, y: y))
                    }
                }
            }
        }

        return FrameState(
            zoom: zoom,
            tileZoom: tileZoom,
            scale: scale,
            center: center,
            rotationDegrees: rotation,
            tileRequest: TileRequest(tiles: wanted)
        )
    }

    // MARK: - Drawing

    private func draw(_ frame: FrameState, in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(RouteAppearance.offlineMapCanvas(for: colorScheme)))

        let midpoint = CGPoint(x: size.width / 2, y: size.height / 2)
        var map = context
        if frame.rotationDegrees != 0 {
            map.translateBy(x: midpoint.x, y: midpoint.y)
            map.rotate(by: .degrees(frame.rotationDegrees))
            map.translateBy(x: -midpoint.x, y: -midpoint.y)
        }

        let pointsPerTile = Self.tileSide * frame.scale
        func screenPoint(tileX: Double, tileY: Double) -> CGPoint {
            CGPoint(
                x: midpoint.x + (tileX - frame.center.x) * pointsPerTile,
                y: midpoint.y + (tileY - frame.center.y) * pointsPerTile
            )
        }

        // Tiles: parent layer first as a fallback, the wanted zoom on top.
        for tile in frame.tileRequest.tiles {
            guard let image = tiles.images[tile] else { continue }
            let factor = pow(2, Double(frame.tileZoom - tile.zoom))
            let origin = screenPoint(tileX: Double(tile.x) * factor, tileY: Double(tile.y) * factor)
            let side = pointsPerTile * factor
            // Half-point overlap hides hairline seams between tiles.
            map.draw(
                Image(decorative: image, scale: 1),
                in: CGRect(x: origin.x - 0.25, y: origin.y - 0.25, width: side + 0.5, height: side + 0.5)
            )
        }

        guard let route = viewModel.routePackage else { return }
        let units = geometry.routeUnits(for: route)
        let zoomFactor = pow(2, Double(frame.tileZoom))
        func project(_ unit: SIMD2<Double>) -> CGPoint {
            screenPoint(tileX: unit.x * zoomFactor, tileY: unit.y * zoomFactor)
        }

        let progress = viewModel.navigationSnapshot?.progressDistanceMeters ?? 0
        let splitIndex = route.route.firstIndex { $0.distanceFromStartMeters > progress } ?? route.route.count

        strokeRoute(units[0..<min(splitIndex + 1, units.count)], project: project, color: RouteAppearance.routeColor.opacity(0.35), in: &map)
        strokeRoute(units[max(0, splitIndex - 1)..<units.count], project: project, color: RouteAppearance.routeColor, in: &map)

        let track = geometry.trackUnits(for: viewModel.displayTrack)
        strokeRoute(track[...], project: project, color: RouteAppearance.trackColor, in: &map)

        if let first = units.first {
            drawEndpoint(at: project(first), symbol: "flag.fill", color: .green, in: &map)
        }
        if let last = units.last, units.count > 1 {
            drawEndpoint(at: project(last), symbol: "flag.checkered", color: .red, in: &map)
        }

        if let display = viewModel.upcomingCueDisplay {
            let unit = GeometryUnits.unit(for: display.cue.coordinate)
            drawTurnMarker(at: project(unit), kind: display.cue.kind, in: &map)
        }

        if let coordinate = viewModel.displayCoordinate {
            // Draw unrotated so the heading wedge reads naturally in both orientations.
            var point = project(GeometryUnits.unit(for: coordinate))
            if frame.rotationDegrees != 0 {
                point = rotate(point, around: midpoint, degrees: frame.rotationDegrees)
            }
            let heading = frame.rotationDegrees != 0 ? 0 : viewModel.courseDegrees
            drawUserMarker(at: point, headingDegrees: heading, in: &context)
        }
    }

    private func strokeRoute(
        _ units: ArraySlice<SIMD2<Double>>,
        project: (SIMD2<Double>) -> CGPoint,
        color: Color,
        in context: inout GraphicsContext
    ) {
        guard units.count >= 2 else { return }
        var path = Path()
        var last: CGPoint?
        for unit in units {
            let point = project(unit)
            if let previous = last {
                // Sub-pixel segments add work without changing the picture.
                if abs(point.x - previous.x) + abs(point.y - previous.y) < 1.5 { continue }
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            last = point
        }
        if let finalPoint = units.last.map(project), let last, finalPoint != last {
            path.addLine(to: finalPoint)
        }

        context.stroke(path, with: .color(RouteAppearance.routeOutlineColor), style: StrokeStyle(lineWidth: RouteAppearance.routeOutlineWidth, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: RouteAppearance.routeStrokeWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawEndpoint(at point: CGPoint, symbol: String, color: Color, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
        context.fill(Path(ellipseIn: rect), with: .color(color))
        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
        let icon = context.resolve(
            Text(Image(systemName: symbol))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        )
        context.draw(icon, at: point, anchor: .center)
    }

    private func drawTurnMarker(at point: CGPoint, kind: RouteCueKind, in context: inout GraphicsContext) {
        let side: CGFloat = 26
        let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.85)))
        context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
        let symbol = context.resolve(
            Text(Image(systemName: ActiveRouteMapOverlay.cueSymbol(for: kind)))
                .font(.system(size: side * 0.48, weight: .bold))
                .foregroundStyle(.white)
        )
        context.draw(symbol, at: point, anchor: .center)
    }

    private func drawUserMarker(at point: CGPoint, headingDegrees: Double?, in context: inout GraphicsContext) {
        let ring: CGFloat = 18
        if let headingDegrees {
            var wedgeContext = context
            wedgeContext.translateBy(x: point.x, y: point.y)
            wedgeContext.rotate(by: .degrees(headingDegrees))
            var wedge = Path()
            wedge.move(to: CGPoint(x: 0, y: -ring / 2 - 8))
            wedge.addLine(to: CGPoint(x: -5, y: -ring / 2 + 1))
            wedge.addLine(to: CGPoint(x: 5, y: -ring / 2 + 1))
            wedge.closeSubpath()
            wedgeContext.fill(wedge, with: .color(.white))
        }
        let ringRect = CGRect(x: point.x - ring / 2, y: point.y - ring / 2, width: ring, height: ring)
        context.fill(Path(ellipseIn: ringRect), with: .color(.white))
        context.fill(Path(ellipseIn: ringRect.insetBy(dx: 3, dy: 3)), with: .color(RouteAppearance.routeColor))
    }

    private func rotate(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(radians) - dy * sin(radians),
            y: center.y + dx * sin(radians) + dy * cos(radians)
        )
    }
}

/// Normalized Web Mercator coordinates (0…1), which scale to any zoom by a multiplication.
enum GeometryUnits {
    static func unit(for coordinate: GeoCoordinate) -> SIMD2<Double> {
        let units = MapMath.tileUnits(for: coordinate, zoom: 0)
        return SIMD2(units.x, units.y)
    }
}

/// Projects the route once per route and the track incrementally, instead of every frame.
@MainActor
final class RouteGeometryCache {
    private var routeID: UUID?
    private var routeUnits: [SIMD2<Double>] = []
    private var trackUnits: [SIMD2<Double>] = []
    private var projectedTrackCount = 0

    func reset() {
        routeID = nil
        routeUnits = []
        trackUnits = []
        projectedTrackCount = 0
    }

    func routeUnits(for route: RoutePackage) -> [SIMD2<Double>] {
        if routeID != route.id {
            routeID = route.id
            routeUnits = route.route.map { GeometryUnits.unit(for: $0.coordinate) }
            trackUnits = []
            projectedTrackCount = 0
        }
        return routeUnits
    }

    func trackUnits(for track: [GeoCoordinate]) -> [SIMD2<Double>] {
        if track.count < projectedTrackCount {
            trackUnits = []
            projectedTrackCount = 0
        }
        if track.count > projectedTrackCount {
            trackUnits.append(contentsOf: track[projectedTrackCount...].map(GeometryUnits.unit(for:)))
            projectedTrackCount = track.count
        }
        return trackUnits
    }
}

/// Decoded tile images with least-recently-used eviction. Decoding happens off the main thread.
@MainActor
@Observable
final class TileImageCache {
    private(set) var images: [TileCoordinate: CGImage] = [:]
    @ObservationIgnored private var lastUse: [TileCoordinate: Int] = [:]
    @ObservationIgnored private var useCounter = 0
    @ObservationIgnored private var missing: Set<TileCoordinate> = []
    @ObservationIgnored private var manifestDirectory: URL?
    @ObservationIgnored private var cachedManifest: OfflineMapManifest?

    /// Roughly two screens of 512 px tiles; keeps memory bounded on the watch.
    private static let capacity = 30

    func removeAll() {
        images = [:]
        lastUse = [:]
        missing = []
        manifestDirectory = nil
        cachedManifest = nil
    }

    /// The pack's manifest, read from disk once per route rather than every frame.
    func manifest(for store: OfflineTileStore?) -> OfflineMapManifest? {
        guard let store else { return nil }
        if manifestDirectory != store.routeDirectory {
            manifestDirectory = store.routeDirectory
            cachedManifest = try? store.manifest()
        }
        return cachedManifest
    }

    func load(_ wanted: [TileCoordinate], from store: OfflineTileStore?) async {
        guard let store else { return }
        useCounter += 1
        for tile in wanted where images[tile] != nil {
            lastUse[tile] = useCounter
        }

        let toLoad = wanted.filter { images[$0] == nil && !missing.contains($0) }
        guard !toLoad.isEmpty else { return }

        let urls = toLoad.map { ($0, store.tileURL(for: $0)) }
        let decoded = await Task.detached(priority: .userInitiated) {
            urls.map { tile, url in (tile, Self.decode(url)) }
        }.value

        guard !Task.isCancelled else { return }
        var updated = images
        for (tile, image) in decoded {
            if let image {
                updated[tile] = image
                lastUse[tile] = useCounter
            } else {
                missing.insert(tile)
            }
        }
        if updated.count > Self.capacity {
            let evict = updated.keys
                .sorted { (lastUse[$0] ?? 0) < (lastUse[$1] ?? 0) }
                .prefix(updated.count - Self.capacity)
            for tile in evict {
                updated[tile] = nil
                lastUse[tile] = nil
            }
        }
        images = updated
    }

    private nonisolated static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
