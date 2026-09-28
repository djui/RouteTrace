import Combine
import Foundation
import SwiftData
import RouteTraceShared

/// Precomputed figures for list rows and cards.
///
/// `ActivityEntity.recording` decodes the whole track from JSON on every access; doing that per
/// row render (several times per row) made the activity list stutter.
struct ActivitySummary: Sendable {
    let distanceMeters: Double
    let elapsedSeconds: TimeInterval
    let elevationGainMeters: Double?
    let averageSpeedMetersPerSecond: Double?
    let averageHeartRateBPM: Double?
    let thumbnail: [GeoCoordinate]
}

struct OfflineBuildFailure: Identifiable, Equatable {
    let id = UUID()
    let routeID: UUID
    let routeName: String
    let message: String
}

@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var isCloudSyncEnabled = true
    @Published private(set) var lastCloudRestoreAt: Date?
    /// Offline map builds in progress. Kept here rather than in a view so progress survives
    /// navigating away and also shows in the route list.
    @Published private(set) var offlineBuilds: [UUID: OfflinePackBuildProgress] = [:]
    @Published var offlineBuildFailure: OfflineBuildFailure?

    private let context: ModelContext
    private var offlineBuildTasks: [UUID: Task<Void, Never>] = [:]
    private var thumbnailCache: [UUID: (stamp: String, points: [GeoCoordinate])] = [:]
    private var activitySummaryCache: [UUID: ActivitySummary] = [:]

    /// Called after a route package is persisted locally. Used for automatic Watch transfer.
    var onRoutePackageSaved: ((UUID) -> Void)?
    /// Called after a route was deleted, so the Watch can drop its copy too.
    var onRouteDeleted: ((UUID) -> Void)?

    static let thumbnailPointLimit = 160

    init(context: ModelContext) {
        self.context = context
        try? RouteTracePaths.ensureDirectoriesExist()
    }

    // MARK: - Fetching

    func fetchRoutes() throws -> [RouteEntity] {
        let descriptor = FetchDescriptor<RouteEntity>(
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchRoute(id: UUID) throws -> RouteEntity? {
        let descriptor = FetchDescriptor<RouteEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchActivities() throws -> [ActivityEntity] {
        let descriptor = FetchDescriptor<ActivityEntity>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchActivity(id: UUID) throws -> ActivityEntity? {
        let descriptor = FetchDescriptor<ActivityEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Settings

    func loadSettings() throws -> AppSettingsEntity {
        let descriptor = FetchDescriptor<AppSettingsEntity>()
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettingsEntity()
        context.insert(settings)
        try context.save()
        return settings
    }

    func saveSettings() throws {
        try context.save()
    }

    // MARK: - Routes

    @discardableResult
    func saveRoutePackage(_ package: RoutePackage, createArchive: Bool = true) throws -> RouteEntity {
        let entity = try persistRoutePackage(package)
        if createArchive {
            let archiveURL = RoutePackaging.makeArchiveURL(for: package, in: RouteTracePaths.routesRoot)
            try RoutePackaging.zipRouteDirectory(entity.routeDirectoryURL, to: archiveURL)
            onRoutePackageSaved?(package.id)
        }
        return entity
    }

    private func persistRoutePackage(_ package: RoutePackage) throws -> RouteEntity {
        let encodedPackage = try RouteTracePayloadCoding.encode(package)
        _ = try RoutePackaging.writeRoutePackage(package, to: RouteTracePaths.routesRoot)
        invalidateCaches(for: package.id)

        let entity: RouteEntity
        if let existing = try fetchRoute(id: package.id) {
            existing.apply(package)
            existing.routePackageData = encodedPackage
            entity = existing
        } else {
            entity = RouteEntity.from(package)
            entity.routePackageData = encodedPackage
            context.insert(entity)
        }

        try context.save()
        return entity
    }

    /// The route as this device should use it.
    ///
    /// The synced SwiftData payload is the source of truth (it carries renames and reversals made
    /// on other devices); offline map data is device-local, so the manifest reflects the tiles
    /// actually present on this device.
    func loadRoutePackage(for entity: RouteEntity) throws -> RoutePackage {
        let package: RoutePackage
        if let synced = try? entity.decodedPackage() {
            package = synced
        } else {
            let routeJSON = entity.routeDirectoryURL.appendingPathComponent("route.json")
            guard FileManager.default.fileExists(atPath: routeJSON.path) else {
                throw RouteStoreError.routePackageUnavailable
            }
            package = try RoutePackaging.loadRoutePackage(from: entity.routeDirectoryURL)
        }
        return package.withLocalOfflineManifest(in: entity.routeDirectoryURL)
    }

    func routepackURL(for entity: RouteEntity) -> URL {
        RouteTracePaths.routesRoot
            .appendingPathComponent("\(entity.id.uuidString).\(RoutePackaging.routepackExtension)")
    }

    func ensureRoutepackArchive(for entity: RouteEntity) throws -> URL {
        let archiveURL = routepackURL(for: entity)
        let routeDirectory = entity.routeDirectoryURL

        let package = try loadRoutePackage(for: entity)
        try writeRouteJSONIfChanged(package, in: routeDirectory)

        if RoutePackaging.archiveNeedsRebuild(routeDirectory: routeDirectory, archiveURL: archiveURL) {
            try RoutePackaging.zipRouteDirectory(routeDirectory, to: archiveURL)
        }

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw RouteStoreError.routePackageUnavailable
        }
        return archiveURL
    }

    func deleteOfflinePack(for entity: RouteEntity) throws {
        let package = try loadRoutePackage(for: entity)
        Self.removeLocalOfflinePack(in: entity.routeDirectoryURL)
        _ = try saveRoutePackage(package.withOfflineManifest(nil))
    }

    func updateTransferState(for routeID: UUID, state: TransferState) throws {
        guard let entity = try fetchRoute(id: routeID), entity.transferState != state else { return }
        entity.transferState = state
        try context.save()
    }

    func renameRoute(for entity: RouteEntity, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RouteStoreError.emptyRouteName
        }
        guard trimmed != entity.name else { return }

        let existing = try loadRoutePackage(for: entity)
        try saveAndResend(existing.renamed(to: trimmed))
    }

    func updateActivityHint(for entity: RouteEntity, to kind: ActivityKind) async throws {
        let existing = try loadRoutePackage(for: entity)
        guard existing.activityHint != kind else { return }

        let sourceURL = RouteTracePaths.sourceGPXURL(for: entity.id)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw RouteStoreError.sourceGPXUnavailable
        }

        let parsed = try await Self.parseGPX(at: sourceURL)
        let updated = RouteProcessor().reprocessPackage(existing, parsed: parsed, activityHint: kind)

        // The tile corridor depends on the activity (e.g. 400 m for runs, 3.5 km for gravel).
        cancelOfflinePackBuild(for: entity.id)
        Self.removeLocalOfflinePack(in: entity.routeDirectoryURL)
        try saveAndResend(updated)
    }

    func reverseRoute(for entity: RouteEntity) async throws {
        let existing = try loadRoutePackage(for: entity)
        let sourceURL = RouteTracePaths.sourceGPXURL(for: entity.id)
        let processor = RouteProcessor()

        // Same geometry, so the offline tiles remain valid.
        let updated: RoutePackage
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            let parsed = try await Self.parseGPX(at: sourceURL)
            updated = processor.reprocessPackage(
                existing,
                parsed: parsed,
                activityHint: existing.activityHint,
                reverseDirection: true,
                preservingOfflineMap: true
            )

            let validPoints = parsed.primaryTrackPoints.filter {
                MapMath.isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
            try GPXExporter.writeTrack(
                name: existing.name,
                points: Array(validPoints.reversed()),
                to: sourceURL
            )
        } else {
            updated = processor.reversePackage(existing, preservingOfflineMap: true)
        }

        try saveAndResend(updated)
    }

    /// Saves a changed route and marks it for re-sending, so the Watch picks up the change.
    private func saveAndResend(_ package: RoutePackage) throws {
        let entity = try persistRoutePackage(package)
        entity.transferState = .notSent
        try context.save()
        let archiveURL = RoutePackaging.makeArchiveURL(for: package, in: RouteTracePaths.routesRoot)
        try RoutePackaging.zipRouteDirectory(entity.routeDirectoryURL, to: archiveURL)
        onRoutePackageSaved?(package.id)
    }

    // MARK: - Offline maps

    func isBuildingOfflinePack(_ routeID: UUID) -> Bool {
        offlineBuildTasks[routeID] != nil
    }

    /// Starts building the offline map in the background; progress is published in `offlineBuilds`.
    func startOfflinePackBuild(for entity: RouteEntity) {
        let routeID = entity.id
        guard offlineBuildTasks[routeID] == nil else { return }

        offlineBuilds[routeID] = OfflinePackBuildProgress(phase: .generatingTiles, completedTiles: 0, totalTiles: 0)
        offlineBuildTasks[routeID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.buildOfflinePack(for: entity) { progress in
                    self.offlineBuilds[routeID] = progress
                }
            } catch is CancellationError {
                // User cancelled; the builder already removed partial tiles.
            } catch {
                self.offlineBuildFailure = OfflineBuildFailure(
                    routeID: routeID,
                    routeName: entity.name,
                    message: RouteActions.offlineMapBuildErrorMessage(for: error)
                )
            }
            self.offlineBuilds[routeID] = nil
            self.offlineBuildTasks[routeID] = nil
        }
    }

    func cancelOfflinePackBuild(for routeID: UUID) {
        offlineBuildTasks[routeID]?.cancel()
    }

    func buildOfflinePack(
        for entity: RouteEntity,
        onProgress: ((OfflinePackBuildProgress) -> Void)? = nil
    ) async throws {
        let package = try loadRoutePackage(for: entity)
        let updated = try await OfflinePackBuilder().buildPack(
            for: package,
            into: entity.routeDirectoryURL,
            onProgress: onProgress
        )
        try Task.checkCancellation()
        let saved = try persistRoutePackage(updated)
        let archiveURL = RoutePackaging.makeArchiveURL(for: updated, in: RouteTracePaths.routesRoot)
        do {
            try RoutePackaging.zipRouteDirectory(saved.routeDirectoryURL, to: archiveURL)
        } catch {
            throw RouteStoreError.offlinePackSavedArchiveFailed
        }
        onRoutePackageSaved?(updated.id)
    }

    // MARK: - Deletion

    func deleteRoute(_ entity: RouteEntity) throws {
        let routeID = entity.id
        let directory = entity.routeDirectoryURL
        let archiveURL = routepackURL(for: entity)
        cancelOfflinePackBuild(for: routeID)
        context.delete(entity)
        try context.save()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: archiveURL)
        invalidateCaches(for: routeID)
        onRouteDeleted?(routeID)
    }

    // MARK: - Activities

    @discardableResult
    func saveActivity(_ recording: ActivityRecording) throws -> ActivityEntity {
        let entity: ActivityEntity
        if let existing = try fetchActivity(id: recording.id) {
            // Update in place: delete + insert churns CloudKit and can briefly duplicate rows.
            existing.update(from: recording)
            entity = existing
        } else {
            entity = ActivityEntity.from(recording)
            context.insert(entity)
        }

        let activityURL = RouteTracePaths.activitiesRoot
            .appendingPathComponent("\(recording.id.uuidString).json")
        let data = try RouteTracePayloadCoding.encode(recording)
        try data.write(to: activityURL, options: .atomic)

        try context.save()
        activitySummaryCache[recording.id] = nil
        return entity
    }

    func renameActivity(for entity: ActivityEntity, to title: String) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RouteStoreError.emptyActivityTitle
        }
        guard trimmed != entity.title else { return }

        let updated = ((try? entity.decodedRecording()) ?? entity.recording).renamed(to: trimmed)
        entity.title = trimmed
        entity.activityPayloadData = try RouteTracePayloadCoding.encode(updated)

        let activityURL = RouteTracePaths.activitiesRoot
            .appendingPathComponent("\(entity.id.uuidString).json")
        try RouteTracePayloadCoding.encode(updated).write(to: activityURL, options: .atomic)

        try context.save()
    }

    func deleteActivity(_ entity: ActivityEntity) throws {
        let activityURL = RouteTracePaths.activitiesRoot
            .appendingPathComponent("\(entity.id.uuidString).json")
        activitySummaryCache[entity.id] = nil
        context.delete(entity)
        try context.save()
        try? FileManager.default.removeItem(at: activityURL)
    }

    /// Full recording, decoded once per call site (views keep the result in state).
    func recording(for entity: ActivityEntity) -> ActivityRecording {
        (try? entity.decodedRecording()) ?? entity.recording
    }

    func summary(for entity: ActivityEntity) -> ActivitySummary {
        if let cached = activitySummaryCache[entity.id] {
            return cached
        }
        let recording = recording(for: entity)
        let distance = ActivityTrackStatistics.gpsDistanceMeters(from: recording.trackPoints)
        let summary = ActivitySummary(
            distanceMeters: distance > 0 ? distance : recording.totalDistanceMeters,
            elapsedSeconds: recording.elapsedSeconds,
            elevationGainMeters: ActivityTrackStatistics.elevationGainMeters(
                from: recording.trackPoints,
                fallback: recording.elevationGainMeters
            ),
            averageSpeedMetersPerSecond: ActivityTrackStatistics.averageSpeedMetersPerSecond(
                gpsDistanceMeters: distance,
                elapsedSeconds: recording.elapsedSeconds
            ),
            averageHeartRateBPM: recording.averageHeartRateBPM,
            thumbnail: ProfileDownsampler.downsample(
                recording.trackPoints.map(\.coordinate),
                maxCount: Self.thumbnailPointLimit
            )
        )
        activitySummaryCache[entity.id] = summary
        return summary
    }

    // MARK: - Thumbnails

    /// Downsampled route geometry for list thumbnails, cached per route revision.
    func thumbnailPoints(for entity: RouteEntity) -> [GeoCoordinate] {
        let stamp = entity.thumbnailStamp
        if let cached = thumbnailCache[entity.id], cached.stamp == stamp {
            return cached.points
        }
        let points = (try? loadRoutePackage(for: entity))
            .map { ProfileDownsampler.downsample($0.route.map(\.coordinate), maxCount: Self.thumbnailPointLimit) }
            ?? []
        thumbnailCache[entity.id] = (stamp, points)
        return points
    }

    private func invalidateCaches(for routeID: UUID) {
        thumbnailCache[routeID] = nil
    }

    // MARK: - Sync

    /// Backfills local route files and cloud payloads after iCloud sync or upgrades.
    func restoreCloudBackedFilesIfNeeded() async throws {
        let routes = try fetchRoutes()
        for route in routes {
            if route.routePackageData.isEmpty, let package = try? loadRoutePackageFromDisk(for: route) {
                route.routePackageData = try RouteTracePayloadCoding.encode(package)
                continue
            }

            if let package = try route.decodedPackage() {
                try materializeRouteFiles(for: route, package: package)
            }
        }

        let activities = try fetchActivities()
        for activity in activities {
            let activityURL = RouteTracePaths.activitiesRoot
                .appendingPathComponent("\(activity.id.uuidString).json")
            if FileManager.default.fileExists(atPath: activityURL.path) { continue }
            if let recording = try activity.decodedRecording() {
                let data = try RouteTracePayloadCoding.encode(recording)
                try data.write(to: activityURL, options: .atomic)
            }
        }

        for activity in activities {
            let recording = (try? activity.decodedRecording()) ?? activity.recording
            guard recording.plannedRoutePoints?.isEmpty ?? true else { continue }
            guard let routeEntity = try fetchRoute(id: activity.routeId),
                  let package = try? loadRoutePackage(for: routeEntity),
                  !package.route.isEmpty else {
                continue
            }
            var updated = recording
            updated.plannedRoutePoints = package.route
            _ = try saveActivity(updated)
        }

        try context.save()
        lastCloudRestoreAt = Date()
    }

    private func loadRoutePackageFromDisk(for entity: RouteEntity) throws -> RoutePackage? {
        let routeJSON = entity.routeDirectoryURL.appendingPathComponent("route.json")
        guard FileManager.default.fileExists(atPath: routeJSON.path) else { return nil }
        return try RoutePackaging.loadRoutePackage(from: entity.routeDirectoryURL)
    }

    private func materializeRouteFiles(for entity: RouteEntity, package: RoutePackage) throws {
        let localPackage = package.withLocalOfflineManifest(in: entity.routeDirectoryURL)
        try writeRouteJSONIfChanged(localPackage, in: entity.routeDirectoryURL)
        let archiveURL = routepackURL(for: entity)
        if RoutePackaging.archiveNeedsRebuild(routeDirectory: entity.routeDirectoryURL, archiveURL: archiveURL) {
            try RoutePackaging.zipRouteDirectory(entity.routeDirectoryURL, to: archiveURL)
        }
    }

    /// Keeps the on-disk working copy in step with the synced payload (e.g. a rename on iPad).
    private func writeRouteJSONIfChanged(_ package: RoutePackage, in routeDirectory: URL) throws {
        let routeJSON = routeDirectory.appendingPathComponent("route.json")
        let data = try RouteTracePayloadCoding.encode(package)
        if let existing = try? Data(contentsOf: routeJSON), existing == data {
            return
        }
        try FileManager.default.createDirectory(at: routeDirectory, withIntermediateDirectories: true)
        try data.write(to: routeJSON, options: .atomic)
    }

    private static func removeLocalOfflinePack(in routeDirectory: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: routeDirectory.appendingPathComponent("tiles", isDirectory: true))
        try? fileManager.removeItem(at: routeDirectory.appendingPathComponent("manifest.json"))
    }

    private nonisolated static func parseGPX(at url: URL) async throws -> ParsedGPX {
        try await Task.detached(priority: .userInitiated) {
            try GPXParser().parse(data: Data(contentsOf: url))
        }.value
    }
}

private extension RouteEntity {
    /// Changes whenever the stored geometry or its presentation changes.
    var thumbnailStamp: String {
        "\(simplifiedPointCount)|\(distanceMeters)|\(minLatitude),\(minLongitude)|\(elevationGainMeters ?? -1)|\(elevationLossMeters ?? -1)"
    }
}

extension RoutePackage {
    func withOfflineManifest(_ manifest: OfflineMapManifest?) -> RoutePackage {
        RoutePackage(
            id: id,
            name: name,
            sourceFileName: sourceFileName,
            importedAt: importedAt,
            activityHint: activityHint,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            boundingBox: boundingBox,
            originalPointCount: originalPointCount,
            simplifiedPointCount: simplifiedPointCount,
            route: route,
            cues: cues,
            offlineMapManifest: manifest,
            navigationWarning: navigationWarning
        )
    }

    /// Offline tiles are device-local; a manifest synced from another device must not claim
    /// tiles that are not here, and tiles built here must be reflected in the package.
    func withLocalOfflineManifest(in routeDirectory: URL) -> RoutePackage {
        let tilesExist = FileManager.default.fileExists(
            atPath: routeDirectory.appendingPathComponent("tiles", isDirectory: true).path
        )
        let localManifest = tilesExist ? (try? OfflineTileStore(routeDirectory: routeDirectory).manifest()) : nil
        guard let localManifest else {
            return offlineMapManifest == nil ? self : withOfflineManifest(nil)
        }
        if let offlineMapManifest,
           offlineMapManifest.tileCount == localManifest.tileCount,
           offlineMapManifest.packBuiltAt == localManifest.packBuiltAt {
            return self
        }
        return withOfflineManifest(localManifest)
    }
}

extension ActivityEntity {
    func update(from recording: ActivityRecording) {
        routeId = recording.routeId
        routeName = recording.routeName
        title = recording.title
        startedAt = recording.startedAt
        endedAt = recording.endedAt
        activityKind = recording.activityKind
        totalDistanceMeters = recording.totalDistanceMeters
        elapsedSeconds = recording.elapsedSeconds
        elevationGainMeters = recording.elevationGainMeters
        averageHeartRateBPM = recording.averageHeartRateBPM
        trackPoints = recording.trackPoints
        offRouteEvents = recording.offRouteEvents
        plannedRoutePoints = recording.plannedRoutePoints
        activityPayloadData = (try? RouteTracePayloadCoding.encode(recording)) ?? activityPayloadData
        syncedAt = Date()
    }
}

enum RouteStoreError: Error, LocalizedError {
    case routeNotFound
    case routePackageUnavailable
    case sourceGPXUnavailable
    case offlinePackSavedArchiveFailed
    case emptyRouteName
    case emptyActivityTitle

    var errorDescription: String? {
        switch self {
        case .routeNotFound:
            "The route could not be found."
        case .routePackageUnavailable:
            "The route package is not available locally or in iCloud."
        case .sourceGPXUnavailable:
            "The original GPX file is not available. Re-import this route to change its activity type."
        case .offlinePackSavedArchiveFailed:
            "Offline map downloaded, but the Watch transfer package could not be created. Tap Send to Watch to retry."
        case .emptyRouteName:
            "Route name cannot be empty."
        case .emptyActivityTitle:
            "Activity name cannot be empty."
        }
    }
}
