import Foundation
import Observation
import RouteTraceShared

/// Figures shown in lists, computed once when an activity is loaded or saved.
struct WatchActivitySummary: Sendable {
    let distanceMeters: Double
    let averageSpeedMetersPerSecond: Double?
    let elevationGainMeters: Double?
    let thumbnail: [GeoCoordinate]

    init(_ recording: ActivityRecording) {
        let distance = ActivityTrackStatistics.gpsDistanceMeters(from: recording.trackPoints)
        distanceMeters = distance > 0 ? distance : recording.totalDistanceMeters
        averageSpeedMetersPerSecond = ActivityTrackStatistics.averageSpeedMetersPerSecond(
            gpsDistanceMeters: distanceMeters,
            elapsedSeconds: recording.elapsedSeconds
        )
        elevationGainMeters = ActivityTrackStatistics.elevationGainMeters(
            from: recording.trackPoints,
            fallback: recording.elevationGainMeters
        )
        thumbnail = ProfileDownsampler.downsample(recording.trackPoints.map(\.coordinate), maxCount: 120)
    }
}

@MainActor
@Observable
final class WatchActivityStore {
    static let shared = WatchActivityStore()

    private(set) var activities: [ActivityRecording] = []
    private(set) var summaries: [UUID: WatchActivitySummary] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    static let maxStoredActivities = 30

    private let fileManager = FileManager.default

    var activitiesRootURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Activities", isDirectory: true)
    }

    private init() {}

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        let root = activitiesRootURL
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let loaded = try await Task.detached(priority: .userInitiated) {
                try Self.loadRecordings(in: root)
            }.value
            activities = loaded.map(\.recording).sorted { $0.startedAt > $1.startedAt }
            summaries = Dictionary(uniqueKeysWithValues: loaded.map { ($0.recording.id, $0.summary) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private nonisolated static func loadRecordings(in root: URL) throws -> [(recording: ActivityRecording, summary: WatchActivitySummary)] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let recording = try? RouteTracePayloadCoding.decode(ActivityRecording.self, from: data) else {
                    return nil
                }
                return (recording, WatchActivitySummary(recording))
            }
    }

    func save(_ recording: ActivityRecording) async throws {
        try fileManager.createDirectory(at: activitiesRootURL, withIntermediateDirectories: true)
        let data = try RouteTracePayloadCoding.encode(recording)
        try data.write(to: fileURL(for: recording.id), options: .atomic)

        activities.removeAll { $0.id == recording.id }
        activities.insert(recording, at: activities.firstIndex { $0.startedAt < recording.startedAt } ?? activities.endIndex)
        summaries[recording.id] = WatchActivitySummary(recording)
        pruneIfNeeded()
    }

    func delete(id: UUID) async throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        activities.removeAll { $0.id == id }
        summaries[id] = nil
    }

    func activity(with id: UUID) -> ActivityRecording? {
        activities.first { $0.id == id }
    }

    func summary(for recording: ActivityRecording) -> WatchActivitySummary {
        summaries[recording.id] ?? WatchActivitySummary(recording)
    }

    private func fileURL(for id: UUID) -> URL {
        activitiesRootURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func pruneIfNeeded() {
        guard activities.count > Self.maxStoredActivities else { return }
        for recording in activities.dropFirst(Self.maxStoredActivities) {
            try? fileManager.removeItem(at: fileURL(for: recording.id))
            summaries[recording.id] = nil
        }
        activities = Array(activities.prefix(Self.maxStoredActivities))
    }
}
