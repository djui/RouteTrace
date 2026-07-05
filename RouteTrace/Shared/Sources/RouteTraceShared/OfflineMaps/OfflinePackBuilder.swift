import Foundation

#if canImport(MapKit) && os(iOS) && os(iOS)
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
    public static func tiles(
        for route: [RoutePoint],
        bufferMeters: Double,
        minZoom: Int = 13,
        maxZoom: Int = 15
    ) -> [TileCoordinate] {
        guard let box = MapMath.boundingBox(for: route.map(\.coordinate)) else { return [] }
        let expanded = expand(box: box, bufferMeters: bufferMeters)
        var result = Set<TileCoordinate>()

        for zoom in minZoom...maxZoom {
            let minX = MapMath.tileX(longitude: expanded.minLongitude, zoom: zoom)
            let maxX = MapMath.tileX(longitude: expanded.maxLongitude, zoom: zoom)
            let minY = MapMath.tileY(latitude: expanded.maxLatitude, zoom: zoom)
            let maxY = MapMath.tileY(latitude: expanded.minLatitude, zoom: zoom)

            for x in minX...maxX {
                for y in minY...maxY {
                    result.insert(TileCoordinate(zoom: zoom, x: x, y: y))
                }
            }
        }

        return Array(result).sorted {
            if $0.zoom != $1.zoom { return $0.zoom < $1.zoom }
            if $0.x != $1.x { return $0.x < $1.x }
            return $0.y < $1.y
        }
    }

    private static func expand(box: GeoBoundingBox, bufferMeters: Double) -> GeoBoundingBox {
        let latDelta = bufferMeters / 111_000
        let lonDelta = bufferMeters / (111_000 * max(0.2, cos(box.center.latitude * .pi / 180)))
        return GeoBoundingBox(
            minLatitude: box.minLatitude - latDelta,
            maxLatitude: box.maxLatitude + latDelta,
            minLongitude: box.minLongitude - lonDelta,
            maxLongitude: box.maxLongitude + lonDelta
        )
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
                "Offline pack is too large (\(size) bytes). Try a shorter route or lower zoom."
            }
        }
    }

    private let maxPackBytes: Int64 = 100 * 1024 * 1024

    public init() {}

    public func buildPack(
        for package: RoutePackage,
        into routeDirectory: URL
    ) async throws -> RoutePackage {
        let tiles = OfflineTilePlanner.tiles(
            for: package.route,
            bufferMeters: package.activityHint.corridorBufferMeters,
            minZoom: package.distanceMeters > 200_000 ? 13 : 13,
            maxZoom: package.distanceMeters > 200_000 ? 14 : 15
        )

        let tilesDirectory = routeDirectory.appendingPathComponent("tiles", isDirectory: true)
        let manifestURL = routeDirectory.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: tilesDirectory.path) {
            try FileManager.default.removeItem(at: tilesDirectory)
        }
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        try FileManager.default.createDirectory(at: tilesDirectory, withIntermediateDirectories: true)

        var totalBytes: Int64 = 0
        var writtenTiles: [TileCoordinate] = []

        do {
            for tile in tiles {
                let tileURL = tilesDirectory.appendingPathComponent(tile.filename)
                let data = try await snapshotTile(tile)
                try data.write(to: tileURL, options: .atomic)
                guard FileManager.default.fileExists(atPath: tileURL.path) else {
                    throw BuildError.snapshotFailed
                }
                writtenTiles.append(tile)
                totalBytes += Int64(data.count)
                if totalBytes > maxPackBytes {
                    throw BuildError.packTooLarge(totalBytes)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: tilesDirectory)
            try? FileManager.default.removeItem(at: manifestURL)
            throw error
        }

        for tile in writtenTiles {
            let tileURL = tilesDirectory.appendingPathComponent(tile.filename)
            guard FileManager.default.fileExists(atPath: tileURL.path),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: tileURL.path),
                  let size = attrs[.size] as? Int64, size > 0 else {
                try? FileManager.default.removeItem(at: tilesDirectory)
                try? FileManager.default.removeItem(at: manifestURL)
                throw BuildError.snapshotFailed
            }
        }

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

    private func snapshotTile(_ tile: TileCoordinate) async throws -> Data {
        let bounds = MapMath.tileBounds(x: tile.x, y: tile.y, zoom: tile.zoom)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
                longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: bounds.maxLatitude - bounds.minLatitude,
                longitudeDelta: bounds.maxLongitude - bounds.minLongitude
            )
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: 256, height: 256)
        options.scale = UITraitCollection.current.displayScale
        options.traitCollection = UITraitCollection(traitsFrom: [
            options.traitCollection,
            UITraitCollection(userInterfaceStyle: .dark)
        ])

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await snapshotter.start()

        guard let data = snapshot.image.pngData() else {
            throw BuildError.snapshotFailed
        }
        return data
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
