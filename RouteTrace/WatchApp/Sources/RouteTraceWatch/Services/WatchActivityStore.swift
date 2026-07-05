import Foundation
import Observation
import RouteTraceShared

@MainActor
@Observable
final class WatchActivityStore {
    static let shared = WatchActivityStore()

    private(set) var activities: [ActivityRecording] = []
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

        do {
            try fileManager.createDirectory(at: activitiesRootURL, withIntermediateDirectories: true)
            let contents = try fileManager.contentsOfDirectory(
                at: activitiesRootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            var loaded: [ActivityRecording] = []
            for url in contents where url.pathExtension == "json" {
                do {
                    let data = try Data(contentsOf: url)
                    let recording = try RouteTracePayloadCoding.decode(ActivityRecording.self, from: data)
                    loaded.append(recording)
                } catch {
                    lastError = error.localizedDescription
                }
            }

            activities = loaded.sorted { $0.startedAt > $1.startedAt }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save(_ recording: ActivityRecording) async throws {
        try fileManager.createDirectory(at: activitiesRootURL, withIntermediateDirectories: true)
        let url = activitiesRootURL.appendingPathComponent("\(recording.id.uuidString).json")
        let data = try RouteTracePayloadCoding.encode(recording)
        try data.write(to: url, options: .atomic)
        await reload()
        try await pruneIfNeeded()
    }

    func delete(id: UUID) async throws {
        let url = activitiesRootURL.appendingPathComponent("\(id.uuidString).json")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        await reload()
    }

    func activity(with id: UUID) -> ActivityRecording? {
        activities.first { $0.id == id }
    }

    private func pruneIfNeeded() async throws {
        guard activities.count > Self.maxStoredActivities else { return }

        let excess = activities.dropFirst(Self.maxStoredActivities)
        for recording in excess {
            let url = activitiesRootURL.appendingPathComponent("\(recording.id.uuidString).json")
            try? fileManager.removeItem(at: url)
        }
        await reload()
    }
}
