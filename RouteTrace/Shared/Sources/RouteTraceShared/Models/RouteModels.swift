import Foundation

public enum ActivityKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case trailRunning
    case running
    case gravelCycling
    case roadCycling

    public var id: String { rawValue }

    public static var allCases: [ActivityKind] {
        [.trailRunning, .running, .gravelCycling, .roadCycling]
    }

    public var displayName: String {
        switch self {
        case .running: "Running"
        case .roadCycling: "Road Cycling"
        case .gravelCycling: "Gravel Cycling"
        case .trailRunning: "Trail Running"
        }
    }

    public var systemImage: String {
        switch self {
        case .trailRunning, .running: "figure.run"
        case .gravelCycling, .roadCycling: "bicycle"
        }
    }

    public var simplificationToleranceMeters: Double {
        switch self {
        case .running, .trailRunning: 4
        case .gravelCycling: 6
        case .roadCycling: 12
        }
    }

    public var corridorBufferMeters: Double {
        switch self {
        case .running, .trailRunning: 400
        case .roadCycling: 1500
        case .gravelCycling: 3500
        }
    }

    public var offRouteWarningMeters: Double {
        switch self {
        case .running, .trailRunning: 25
        case .roadCycling: 40
        case .gravelCycling: 50
        }
    }

    public var offRouteCriticalMeters: Double {
        switch self {
        case .running, .trailRunning: 50
        case .roadCycling: 80
        case .gravelCycling: 100
        }
    }
}

public struct GeoCoordinate: Codable, Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct GeoBoundingBox: Codable, Sendable, Hashable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    public var center: GeoCoordinate {
        GeoCoordinate(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
    }
}

public struct RoutePoint: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let latitude: Double
    public let longitude: Double
    public let elevationMeters: Double?
    public let distanceFromStartMeters: Double
    public let bearingDegrees: Double?

    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }
}

public enum RouteCueKind: String, Codable, Sendable {
    case start
    case finish
    case `continue`
    case slightLeft
    case slightRight
    case turnLeft
    case turnRight
    case sharpLeft
    case sharpRight
    case uTurn
}

public struct RouteCue: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let distanceFromStartMeters: Double
    public let coordinate: GeoCoordinate
    public let kind: RouteCueKind
    public let instruction: String
    public let bearingBefore: Double
    public let bearingAfter: Double
}

public enum OfflinePackStatus: String, Codable, Sendable {
    case missing
    case partial
    case ready
}

public struct OfflineMapManifest: Codable, Sendable {
    public let packBuiltAt: Date
    public let minZoom: Int
    public let maxZoom: Int
    public let tileCount: Int
    public let packSizeBytes: Int64
    public let tileFormat: String
    public let tileSizePixels: Int

    public init(
        packBuiltAt: Date = Date(),
        minZoom: Int,
        maxZoom: Int,
        tileCount: Int,
        packSizeBytes: Int64,
        tileFormat: String = "png",
        tileSizePixels: Int = 256
    ) {
        self.packBuiltAt = packBuiltAt
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.tileCount = tileCount
        self.packSizeBytes = packSizeBytes
        self.tileFormat = tileFormat
        self.tileSizePixels = tileSizePixels
    }
}

public struct RoutePackage: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let sourceFileName: String
    public let importedAt: Date
    public let activityHint: ActivityKind
    public let distanceMeters: Double
    public let elevationGainMeters: Double?
    public let elevationLossMeters: Double?
    public let boundingBox: GeoBoundingBox
    public let originalPointCount: Int
    public let simplifiedPointCount: Int
    public let route: [RoutePoint]
    public let cues: [RouteCue]
    public let offlineMapManifest: OfflineMapManifest?

    public var hasElevationData: Bool {
        route.contains { $0.elevationMeters != nil }
    }

    public var offlineStatus: OfflinePackStatus {
        guard let manifest = offlineMapManifest else { return .missing }
        if manifest.tileCount == 0 { return .missing }
        if manifest.tileCount < 3 { return .partial }
        return .ready
    }
}

public enum TransferState: String, Codable, Sendable {
    case notSent
    case queued
    case transferring
    case installed
    case failed
}

public struct RouteTransferMetadata: Codable, Sendable {
    public static let schemaVersion = 1

    public let type: String
    public let routeId: UUID
    public let name: String
    public let distanceMeters: Double
    public let hasOfflineMap: Bool
    public let activityHint: ActivityKind
    public let schemaVersion: Int

    public init(routePackage: RoutePackage) {
        self.type = "routePackage"
        self.routeId = routePackage.id
        self.name = routePackage.name
        self.distanceMeters = routePackage.distanceMeters
        self.hasOfflineMap = routePackage.offlineMapManifest != nil
        self.activityHint = routePackage.activityHint
        self.schemaVersion = Self.schemaVersion
    }

    public var dictionaryRepresentation: [String: Any] {
        [
            "type": type,
            "routeId": routeId.uuidString,
            "name": name,
            "distanceMeters": distanceMeters,
            "hasOfflineMap": hasOfflineMap,
            "activityHint": activityHint.rawValue,
            "schemaVersion": schemaVersion
        ]
    }
}
