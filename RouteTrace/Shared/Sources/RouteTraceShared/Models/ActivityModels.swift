import Foundation

public struct TrackPoint: Codable, Sendable, Hashable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let altitudeMeters: Double?
    public let horizontalAccuracyMeters: Double
    public let speedMetersPerSecond: Double?
    public let heartRateBPM: Double?
    public let snappedDistanceFromStartMeters: Double?
    public let offRouteDistanceMeters: Double?

    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    public init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double? = nil,
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double? = nil,
        heartRateBPM: Double? = nil,
        snappedDistanceFromStartMeters: Double? = nil,
        offRouteDistanceMeters: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.heartRateBPM = heartRateBPM
        self.snappedDistanceFromStartMeters = snappedDistanceFromStartMeters
        self.offRouteDistanceMeters = offRouteDistanceMeters
    }
}

public struct OffRouteEvent: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let maxDistanceMeters: Double
    public let coordinate: GeoCoordinate

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        maxDistanceMeters: Double,
        coordinate: GeoCoordinate
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.maxDistanceMeters = maxDistanceMeters
        self.coordinate = coordinate
    }
}

public struct ActivityRecording: Codable, Sendable, Identifiable {
    public let id: UUID
    public let routeId: UUID
    public let routeName: String
    public var title: String?
    public let startedAt: Date
    public var endedAt: Date?
    public let activityKind: ActivityKind
    public var trackPoints: [TrackPoint]
    public var totalDistanceMeters: Double
    public var elapsedSeconds: TimeInterval
    public var offRouteEvents: [OffRouteEvent]
    public var elevationGainMeters: Double?
    public var averageHeartRateBPM: Double?

    public var isActive: Bool { endedAt == nil }

    public var displayTitle: String {
        title ?? routeName
    }

    public init(
        id: UUID = UUID(),
        routeId: UUID,
        routeName: String,
        title: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        activityKind: ActivityKind,
        trackPoints: [TrackPoint] = [],
        totalDistanceMeters: Double = 0,
        elapsedSeconds: TimeInterval = 0,
        offRouteEvents: [OffRouteEvent] = [],
        elevationGainMeters: Double? = nil,
        averageHeartRateBPM: Double? = nil
    ) {
        self.id = id
        self.routeId = routeId
        self.routeName = routeName
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activityKind = activityKind
        self.trackPoints = trackPoints
        self.totalDistanceMeters = totalDistanceMeters
        self.elapsedSeconds = elapsedSeconds
        self.offRouteEvents = offRouteEvents
        self.elevationGainMeters = elevationGainMeters
        self.averageHeartRateBPM = averageHeartRateBPM
    }

    public func renamed(to newTitle: String) -> ActivityRecording {
        var copy = self
        copy.title = newTitle
        return copy
    }
}

public enum SpeedDisplayMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case pace
    case speed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pace: "Pace (min/km)"
        case .speed: "Speed (km/h)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .pace: "Pace"
        case .speed: "Speed"
        }
    }

    public var averageLabel: String {
        switch self {
        case .pace: "Avg Pace"
        case .speed: "Avg Speed"
        }
    }
}

public enum SpeedCategory: String, Codable, Sendable {
    case running
    case cycling
}

public enum BatteryMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case normal
    case saver
    case ultraSaver

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Normal"
        case .saver: "Battery Saver"
        case .ultraSaver: "Ultra Saver"
        }
    }

    public var detailDescription: String {
        switch self {
        case .normal:
            "Best GPS accuracy · map updates with your position · full workout recording"
        case .saver:
            "Reduced GPS · map updates throttled · directions-friendly"
        case .ultraSaver:
            "Minimal GPS · route line only · directions-first · longest battery life"
        }
    }

    public var mapSettingsConflictHint: String? {
        switch self {
        case .ultraSaver:
            "Online map uses more battery; Route Only is recommended."
        default:
            nil
        }
    }
}

public enum MapOrientationMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case northUp
    case headingUp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .northUp: "North Up"
        case .headingUp: "Heading Up"
        }
    }

    public var detailDescription: String {
        switch self {
        case .northUp: "Map stays oriented to north"
        case .headingUp: "Map rotates with your direction of travel"
        }
    }
}

public enum MapDisplayMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case onlineNative
    case offlineCorridor
    case routeOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onlineNative: "Online Map"
        case .offlineCorridor: "Offline Map"
        case .routeOnly: "Route Only"
        }
    }

    public var detailDescription: String {
        switch self {
        case .onlineNative: "Live MapKit tiles with GPS. Uses more battery than offline or route-only views."
        case .offlineCorridor: "Downloaded corridor tiles from iPhone. Lower battery use than online map."
        case .routeOnly: "Route line only, lowest battery use."
        }
    }
}

public struct NavigationSnapshot: Codable, Sendable {
    public let routeId: UUID
    public let progressDistanceMeters: Double
    public let distanceRemainingMeters: Double
    public let offRouteDistanceMeters: Double
    public let isOffRoute: Bool
    public let isCriticallyOffRoute: Bool
    public let nextCue: RouteCue?
    public let distanceToNextCueMeters: Double?
    public let currentSpeedMetersPerSecond: Double?
    public let currentCoordinate: GeoCoordinate?
    public let completedTrack: [GeoCoordinate]
    public let actualTrack: [GeoCoordinate]
    public let updatedAt: Date

    public init(
        routeId: UUID,
        progressDistanceMeters: Double,
        distanceRemainingMeters: Double,
        offRouteDistanceMeters: Double,
        isOffRoute: Bool,
        isCriticallyOffRoute: Bool,
        nextCue: RouteCue?,
        distanceToNextCueMeters: Double?,
        currentSpeedMetersPerSecond: Double?,
        currentCoordinate: GeoCoordinate?,
        completedTrack: [GeoCoordinate],
        actualTrack: [GeoCoordinate] = [],
        updatedAt: Date
    ) {
        self.routeId = routeId
        self.progressDistanceMeters = progressDistanceMeters
        self.distanceRemainingMeters = distanceRemainingMeters
        self.offRouteDistanceMeters = offRouteDistanceMeters
        self.isOffRoute = isOffRoute
        self.isCriticallyOffRoute = isCriticallyOffRoute
        self.nextCue = nextCue
        self.distanceToNextCueMeters = distanceToNextCueMeters
        self.currentSpeedMetersPerSecond = currentSpeedMetersPerSecond
        self.currentCoordinate = currentCoordinate
        self.completedTrack = completedTrack
        self.actualTrack = actualTrack
        self.updatedAt = updatedAt
    }
}

public enum RouteTracePayloadCoding {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
