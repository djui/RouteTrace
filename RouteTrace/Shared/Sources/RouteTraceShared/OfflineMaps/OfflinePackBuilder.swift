import Foundation

#if canImport(MapKit) && os(iOS)
import MapKit
import CoreLocation
import UIKit
#endif

public struct TileCoordinate: Codable, Sendable, Hashable {
    public let zoom: Int
    public let x: Int
    public let y: Int

    public var filename: String {
        "z\(zoom)_x\(x)_y\(y).png"
    }

    public init(zoom: Int, x: Int, y: Int) {
        self.zoom = zoom
        self.x = x
        self.y = y
    }
}

public enum OfflineTilePlanner {
    /// Smallest corridor kept at any zoom, so the map around the route itself is always present.
    public static let minimumBufferMeters = 300.0

    /// Tiles covering a corridor of `bufferMeters` around the route.
    ///
    /// The corridor narrows at higher zooms: far from the route an overview is enough, while
    /// detail matters close to it. This keeps packs for long or diagonal routes a fraction of the
    /// size of a bounding-box pack.
    public static func tiles(
        for route: [RoutePoint],
        bufferMeters: Double,
        minZoom: Int = 13,
        maxZoom: Int = 15
    ) -> [TileCoordinate] {
        let coordinates = route.map(\.coordinate)
        guard !coordinates.isEmpty, minZoom <= maxZoom else { return [] }

        var result = Set<TileCoordinate>()
        for zoom in minZoom...maxZoom {
            let zoomBuffer = max(
                minimumBufferMeters,
                bufferMeters * pow(0.5, Double(zoom - minZoom))
            )
            addCorridorTiles(
                along: coordinates,
                zoom: zoom,
                bufferMeters: zoomBuffer,
                into: &result
            )
        }

        return result.sorted {
            if $0.zoom != $1.zoom { return $0.zoom < $1.zoom }
            if $0.x != $1.x { return $0.x < $1.x }
            return $0.y < $1.y
        }
    }

    private static func addCorridorTiles(
        along coordinates: [GeoCoordinate],
        zoom: Int,
        bufferMeters: Double,
        into result: inout Set<TileCoordinate>
    ) {
        let zoomValue = Double(zoom)
        let maxIndex = Int(pow(2.0, zoomValue)) - 1

        func insertTiles(around coordinate: GeoCoordinate) {
            let units = MapMath.tileUnits(for: coordinate, zoom: zoomValue)
            let tileMeters = MapMath.tileSizeMeters(atLatitude: coordinate.latitude, zoom: zoomValue)
            let radius = bufferMeters / max(tileMeters, 1)
            let minX = max(0, Int(floor(units.x - radius)))
            let maxX = min(maxIndex, Int(floor(units.x + radius)))
            let minY = max(0, Int(floor(units.y - radius)))
            let maxY = min(maxIndex, Int(floor(units.y + radius)))
            guard minX <= maxX, minY <= maxY else { return }
            for x in minX...maxX {
                for y in minY...maxY {
                    result.insert(TileCoordinate(zoom: zoom, x: x, y: y))
                }
            }
        }

        insertTiles(around: coordinates[0])
        guard coordinates.count >= 2 else { return }

        for index in 1..<coordinates.count {
            let start = coordinates[index - 1]
            let end = coordinates[index]
            // Sample each segment at least every half tile so no tile along it is skipped.
            let tileMeters = MapMath.tileSizeMeters(atLatitude: start.latitude, zoom: zoomValue)
            let length = MapMath.haversineMeters(from: start, to: end)
            let steps = max(1, Int(ceil(length / max(tileMeters * 0.5, 1))))
            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                insertTiles(around: GeoCoordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                ))
            }
        }
    }
}

/// A 2x2 group of tiles rendered with a single snapshot.
struct TileBlock: Hashable, Comparable, Sendable {
    let zoom: Int
    let x: Int
    let y: Int

    init(containing tile: TileCoordinate) {
        zoom = tile.zoom
        x = tile.x >> 1
        y = tile.y >> 1
    }

    /// The four tiles with their column/row inside the block.
    var tiles: [(TileCoordinate, Int, Int)] {
        [(0, 0), (1, 0), (0, 1), (1, 1)].map { column, row in
            (TileCoordinate(zoom: zoom, x: x * 2 + column, y: y * 2 + row), column, row)
        }
    }

    static func < (lhs: TileBlock, rhs: TileBlock) -> Bool {
        (lhs.zoom, lhs.x, lhs.y) < (rhs.zoom, rhs.x, rhs.y)
    }
}

public struct OfflinePackBuildProgress: Sendable {
    public enum Phase: Sendable {
        case generatingTiles
        case finalizing
    }

    public let phase: Phase
    public let completedTiles: Int
    public let totalTiles: Int

    public init(phase: Phase, completedTiles: Int, totalTiles: Int) {
        self.phase = phase
        self.completedTiles = completedTiles
        self.totalTiles = totalTiles
    }

    public var fractionComplete: Double {
        switch phase {
        case .generatingTiles:
            guard totalTiles > 0 else { return 0 }
            return Double(completedTiles) / Double(totalTiles)
        case .finalizing:
            return 1
        }
    }

    public var statusText: String {
        switch phase {
        case .generatingTiles:
            "\(completedTiles) of \(totalTiles) tiles"
        case .finalizing:
            "Finalizing…"
        }
    }
}

#if canImport(MapKit) && os(iOS)
@MainActor
public final class OfflinePackBuilder {
    public enum BuildError: Error, LocalizedError {
        case snapshotFailed
        case packTooLarge(Int64)

        public var errorDescription: String? {
            switch self {
            case .snapshotFailed:
                "Failed to build offline map snapshots."
            case .packTooLarge(let size):
                "The offline map would be too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Try a shorter route."
            }
        }
    }

    private let maxPackBytes: Int64 = 100 * 1024 * 1024
    /// MapKit renders snapshots off the main thread; a few in flight keeps the pipeline full.
    private let maxConcurrentSnapshots = 6
    /// Watch screens are 2x; 3x tiles would be ~2.25x the bytes for no visible gain.
    private nonisolated static let tileDisplayScale: CGFloat = 2
    private nonisolated static let renderQueue = DispatchQueue(label: "com.uwe.RouteTrace.offline-tiles", qos: .userInitiated, attributes: .concurrent)

    public init() {}

    public func buildPack(
        for package: RoutePackage,
        into routeDirectory: URL,
        onProgress: ((OfflinePackBuildProgress) -> Void)? = nil
    ) async throws -> RoutePackage {
        let tiles = OfflineTilePlanner.tiles(
            for: package.route,
            bufferMeters: package.activityHint.corridorBufferMeters,
            minZoom: 13,
            maxZoom: package.distanceMeters > 200_000 ? 14 : 15
        )

        onProgress?(OfflinePackBuildProgress(phase: .generatingTiles, completedTiles: 0, totalTiles: tiles.count))

        let fileManager = FileManager.default
        let tilesDirectory = routeDirectory.appendingPathComponent("tiles", isDirectory: true)
        let manifestURL = routeDirectory.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: tilesDirectory.path) {
            try fileManager.removeItem(at: tilesDirectory)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
        try fileManager.createDirectory(at: tilesDirectory, withIntermediateDirectories: true)

        var totalBytes: Int64 = 0
        var completed = 0
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = .dark
            traits.displayScale = Self.tileDisplayScale
        }
        let wanted = Set(tiles)
        // Tiles are rendered in 2x2 blocks: a quarter of the snapshot calls, labels are cut at
        // fewer edges, and MapKit's logo lands on one tile per block instead of on every tile.
        let blocks = Array(Set(tiles.map(TileBlock.init(containing:)))).sorted()

        do {
            try await withThrowingTaskGroup(of: [(TileCoordinate, Data)].self) { group in
                var pending = blocks[...]

                func enqueueNext() {
                    guard let block = pending.popFirst() else { return }
                    group.addTask {
                        try await Self.renderBlock(block, keeping: wanted, traits: traits)
                    }
                }

                for _ in 0 ..< maxConcurrentSnapshots {
                    enqueueNext()
                }

                while let rendered = try await group.next() {
                    try Task.checkCancellation()
                    for (tile, data) in rendered {
                        guard !data.isEmpty else { throw BuildError.snapshotFailed }
                        try data.write(to: tilesDirectory.appendingPathComponent(tile.filename), options: .atomic)
                        totalBytes += Int64(data.count)
                        completed += 1
                    }
                    if totalBytes > maxPackBytes {
                        throw BuildError.packTooLarge(totalBytes)
                    }
                    onProgress?(OfflinePackBuildProgress(
                        phase: .generatingTiles,
                        completedTiles: completed,
                        totalTiles: tiles.count
                    ))
                    enqueueNext()
                }
            }
        } catch {
            try? fileManager.removeItem(at: tilesDirectory)
            try? fileManager.removeItem(at: manifestURL)
            throw error
        }

        onProgress?(OfflinePackBuildProgress(phase: .finalizing, completedTiles: tiles.count, totalTiles: tiles.count))

        let manifest = OfflineMapManifest(
            packBuiltAt: Date(),
            minZoom: tiles.map(\.zoom).min() ?? 13,
            maxZoom: tiles.map(\.zoom).max() ?? 15,
            tileCount: tiles.count,
            packSizeBytes: totalBytes
        )

        try RouteTracePayloadCoding.encode(manifest).write(to: manifestURL, options: .atomic)

        return RoutePackage(
            id: package.id,
            name: package.name,
            sourceFileName: package.sourceFileName,
            importedAt: package.importedAt,
            activityHint: package.activityHint,
            distanceMeters: package.distanceMeters,
            elevationGainMeters: package.elevationGainMeters,
            elevationLossMeters: package.elevationLossMeters,
            boundingBox: package.boundingBox,
            originalPointCount: package.originalPointCount,
            simplifiedPointCount: package.simplifiedPointCount,
            route: package.route,
            cues: package.cues,
            offlineMapManifest: manifest,
            navigationWarning: package.navigationWarning
        )
    }

    /// Renders a 2x2 block of 256 pt tiles and slices it. Runs entirely off the main actor,
    /// including PNG encoding.
    private nonisolated static func renderBlock(
        _ block: TileBlock,
        keeping wanted: Set<TileCoordinate>,
        traits: UITraitCollection
    ) async throws -> [(TileCoordinate, Data)] {
        // Exact Web Mercator alignment (a lat/lon region would be off by a few pixels vertically).
        let tileSpan = MKMapSize.world.width / pow(2.0, Double(block.zoom))
        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(
            x: Double(block.x * 2) * tileSpan,
            y: Double(block.y * 2) * tileSpan,
            width: tileSpan * 2,
            height: tileSpan * 2
        )
        options.size = CGSize(width: 512, height: 512)
        // Same muted, flat look as the Watch's live map so the blue route stays the hero;
        // business POIs are noise on a wrist-sized map.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        options.traitCollection = traits

        let snapshotter = MKMapSnapshotter(options: options)
        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            snapshotter.start(with: renderQueue) { snapshot, error in
                if let image = snapshot?.image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? BuildError.snapshotFailed)
                }
            }
        }

        let tilePixels = 256 * tileDisplayScale
        var rendered: [(TileCoordinate, Data)] = []
        for (tile, column, row) in block.tiles where wanted.contains(tile) {
            guard let data = pngData(image, pixelSide: tilePixels, column: column, row: row) else {
                throw BuildError.snapshotFailed
            }
            rendered.append((tile, data))
        }
        return rendered
    }

    /// Cuts one tile out of a block snapshot at a fixed pixel size. Snapshots render at the
    /// phone's screen scale (3x) regardless of the requested display scale.
    private nonisolated static func pngData(_ image: UIImage, pixelSide: CGFloat, column: Int, row: Int) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: pixelSide, height: pixelSide)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            image.draw(in: CGRect(
                x: -CGFloat(column) * pixelSide,
                y: -CGFloat(row) * pixelSide,
                width: pixelSide * 2,
                height: pixelSide * 2
            ))
        }
    }
}
#endif

public struct OfflineTileStore: Sendable {
    public let routeDirectory: URL

    public init(routeDirectory: URL) {
        self.routeDirectory = routeDirectory
    }

    public func manifest() throws -> OfflineMapManifest? {
        let url = routeDirectory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try RouteTracePayloadCoding.decode(OfflineMapManifest.self, from: data)
    }

    public func tileURL(for tile: TileCoordinate) -> URL {
        routeDirectory.appendingPathComponent("tiles").appendingPathComponent(tile.filename)
    }

    public func tilesCovering(coordinate: GeoCoordinate, zoom: Int) -> [TileCoordinate] {
        [TileCoordinate(zoom: zoom, x: MapMath.tileX(longitude: coordinate.longitude, zoom: zoom), y: MapMath.tileY(latitude: coordinate.latitude, zoom: zoom))]
    }

    public func tileExists(_ tile: TileCoordinate) -> Bool {
        FileManager.default.fileExists(atPath: tileURL(for: tile).path)
    }

    public func neighboringTiles(around tile: TileCoordinate, radius: Int = 1) -> [TileCoordinate] {
        guard tile.zoom > 0 else { return [tile] }
        var result: [TileCoordinate] = []
        for dx in -radius ... radius {
            for dy in -radius ... radius {
                result.append(TileCoordinate(zoom: tile.zoom, x: tile.x + dx, y: tile.y + dy))
            }
        }
        return result
    }

    public struct ResolvedTile: Sendable {
        public let tile: TileCoordinate
        public let zoom: Int
        public let usedFallback: Bool
    }

    public func bestAvailableTile(for coordinate: GeoCoordinate, manifest: OfflineMapManifest?) -> ResolvedTile? {
        if let manifest {
            for zoom in stride(from: manifest.maxZoom, through: manifest.minZoom, by: -1) {
                let tile = tilesCovering(coordinate: coordinate, zoom: zoom)[0]
                if tileExists(tile) {
                    return ResolvedTile(tile: tile, zoom: zoom, usedFallback: zoom < manifest.maxZoom)
                }
            }
        }

        let fallback = TileCoordinate(zoom: 0, x: 0, y: 0)
        if tileExists(fallback) {
            return ResolvedTile(tile: fallback, zoom: 0, usedFallback: true)
        }
        return nil
    }

    public func tileAtZoom(
        for coordinate: GeoCoordinate,
        preferredZoom: Int,
        manifest: OfflineMapManifest?
    ) -> ResolvedTile? {
        if let manifest {
            let clamped = min(manifest.maxZoom, max(manifest.minZoom, preferredZoom))
            for zoom in stride(from: clamped, through: manifest.minZoom, by: -1) {
                let tile = tilesCovering(coordinate: coordinate, zoom: zoom)[0]
                if tileExists(tile) {
                    return ResolvedTile(tile: tile, zoom: zoom, usedFallback: zoom < clamped)
                }
            }
        }
        return bestAvailableTile(for: coordinate, manifest: manifest)
    }
}
