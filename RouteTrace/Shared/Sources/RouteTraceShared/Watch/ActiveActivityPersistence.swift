import Foundation

public struct PersistedNavigationEngineState: Codable, Sendable {
    public let lastSegmentIndex: Int
    public let lastProgressMeters: Double
    public let completedTrack: [GeoCoordinate]
    public let actualTrack: [GeoCoordinate]

    public init(
        lastSegmentIndex: Int,
        lastProgressMeters: Double,
        completedTrack: [GeoCoordinate],
        actualTrack: [GeoCoordinate]
    ) {
        self.lastSegmentIndex = lastSegmentIndex
        self.lastProgressMeters = lastProgressMeters
        self.completedTrack = completedTrack
        self.actualTrack = actualTrack
    }
}

public struct PersistedActiveActivity: Codable, Sendable {
    public let phase: String
    public let routeId: UUID
    public let activityKind: ActivityKind
    public let recording: ActivityRecording
    public let elapsedSeconds: TimeInterval
    public let engineState: PersistedNavigationEngineState
    public let savedAt: Date

    public init(
        phase: String,
        routeId: UUID,
        activityKind: ActivityKind,
        recording: ActivityRecording,
        elapsedSeconds: TimeInterval,
        engineState: PersistedNavigationEngineState,
        savedAt: Date = Date()
    ) {
        self.phase = phase
        self.routeId = routeId
        self.activityKind = activityKind
        self.recording = recording
        self.elapsedSeconds = elapsedSeconds
        self.engineState = engineState
        self.savedAt = savedAt
    }
}

public enum ActiveActivityPersistence {
    private static let fileName = "active-activity.json"

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(fileName)
    }

    public static func save(_ snapshot: PersistedActiveActivity) {
        guard let data = try? RouteTracePayloadCoding.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func load() -> PersistedActiveActivity? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? RouteTracePayloadCoding.decode(PersistedActiveActivity.self, from: data)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
