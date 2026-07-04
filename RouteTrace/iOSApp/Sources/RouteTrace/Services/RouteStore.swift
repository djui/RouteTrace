import Combine
import Foundation
import SwiftData
import RouteTraceShared

@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var isCloudSyncEnabled = true
    @Published private(set) var lastCloudRestoreAt: Date?

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        try? RouteTracePaths.ensureDirectoriesExist()
    }

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

    @discardableResult
    func saveRoutePackage(_ package: RoutePackage) throws -> RouteEntity {
        let encodedPackage = try RouteTracePayloadCoding.encode(package)
        let routeDirectory = try RoutePackaging.writeRoutePackage(package, to: RouteTracePaths.routesRoot)
        let archiveURL = RoutePackaging.makeArchiveURL(for: package, in: RouteTracePaths.routesRoot)
        try RoutePackaging.zipRouteDirectory(routeDirectory, to: archiveURL)

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

    func loadRoutePackage(for entity: RouteEntity) throws -> RoutePackage {
        let routeJSON = entity.routeDirectoryURL.appendingPathComponent("route.json")
        if FileManager.default.fileExists(atPath: routeJSON.path) {
            return try RoutePackaging.loadRoutePackage(from: entity.routeDirectoryURL)
        }

        guard let package = try entity.decodedPackage() else {
            throw RouteStoreError.routePackageUnavailable
        }

        try materializeRouteFiles(for: entity, package: package)
        return package
    }

    func routepackURL(for entity: RouteEntity) -> URL {
        RouteTracePaths.routesRoot
            .appendingPathComponent("\(entity.id.uuidString).\(RoutePackaging.routepackExtension)")
    }

    func ensureRoutepackArchive(for entity: RouteEntity) throws -> URL {
        let archiveURL = routepackURL(for: entity)
        let routeDirectory = entity.routeDirectoryURL

        if RoutePackaging.archiveNeedsRebuild(routeDirectory: routeDirectory, archiveURL: archiveURL) {
            _ = try loadRoutePackage(for: entity)
            try RoutePackaging.zipRouteDirectory(routeDirectory, to: archiveURL)
        }

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw RouteStoreError.routePackageUnavailable
        }
        return archiveURL
    }

    func deleteOfflinePack(for entity: RouteEntity) throws -> RouteEntity {
        let updated = try RoutePackaging.deleteOfflinePack(from: entity.routeDirectoryURL)
        let archiveURL = routepackURL(for: entity)
        try RoutePackaging.zipRouteDirectory(entity.routeDirectoryURL, to: archiveURL)
        entity.apply(updated)
        entity.routePackageData = try RouteTracePayloadCoding.encode(updated)
        try context.save()
        guard let refreshed = try fetchRoute(id: entity.id) else {
            throw RouteStoreError.routeNotFound
        }
        return refreshed
    }

    func updateTransferState(for routeID: UUID, state: TransferState) throws {
        guard let entity = try fetchRoute(id: routeID) else { return }
        entity.transferState = state
        try context.save()
    }

    func updateActivityHint(for entity: RouteEntity, to kind: ActivityKind) async throws -> RouteEntity {
        let sourceURL = RouteTracePaths.sourceGPXURL(for: entity.id)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw RouteStoreError.sourceGPXUnavailable
        }

        let data = try Data(contentsOf: sourceURL)
        let parser = GPXParser()
        let parsed = try parser.parse(data: data)
        let processor = RouteProcessor()
        let existing = try loadRoutePackage(for: entity)
        guard existing.activityHint != kind else {
            return entity
        }

        let updated = processor.reprocessPackage(existing, parsed: parsed, activityHint: kind)

        let tilesDirectory = entity.routeDirectoryURL.appendingPathComponent("tiles", isDirectory: true)
        if FileManager.default.fileExists(atPath: tilesDirectory.path) {
            try? FileManager.default.removeItem(at: tilesDirectory)
        }

        _ = try saveRoutePackage(updated)
        guard let refreshed = try fetchRoute(id: entity.id) else {
            throw RouteStoreError.routeNotFound
        }
        return refreshed
    }

    func buildOfflinePack(for entity: RouteEntity) async throws -> RouteEntity {
        var package = try loadRoutePackage(for: entity)
        let builder = OfflinePackBuilder()
        let updated = try await builder.buildPack(for: package, into: entity.routeDirectoryURL)
        package = updated
        _ = try saveRoutePackage(updated)
        guard let refreshed = try fetchRoute(id: entity.id) else {
            throw RouteStoreError.routeNotFound
        }
        return refreshed
    }

    func deleteRoute(_ entity: RouteEntity) throws {
        let directory = entity.routeDirectoryURL
        let archiveURL = routepackURL(for: entity)
        context.delete(entity)
        try context.save()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: archiveURL)
    }

    @discardableResult
    func saveActivity(_ recording: ActivityRecording) throws -> ActivityEntity {
        let entity: ActivityEntity
        if let existing = try fetchActivity(id: recording.id) {
            context.delete(existing)
        }
        entity = ActivityEntity.from(recording)
        context.insert(entity)

        let activityURL = RouteTracePaths.activitiesRoot
            .appendingPathComponent("\(recording.id.uuidString).json")
        let data = try RouteTracePayloadCoding.encode(recording)
        try data.write(to: activityURL, options: .atomic)

        try context.save()
        return entity
    }

    func deleteActivity(_ entity: ActivityEntity) throws {
        let activityURL = RouteTracePaths.activitiesRoot
            .appendingPathComponent("\(entity.id.uuidString).json")
        context.delete(entity)
        try context.save()
        try? FileManager.default.removeItem(at: activityURL)
    }

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

        try context.save()
        lastCloudRestoreAt = Date()
    }

    private func loadRoutePackageFromDisk(for entity: RouteEntity) throws -> RoutePackage? {
        let routeJSON = entity.routeDirectoryURL.appendingPathComponent("route.json")
        guard FileManager.default.fileExists(atPath: routeJSON.path) else { return nil }
        return try RoutePackaging.loadRoutePackage(from: entity.routeDirectoryURL)
    }

    private func materializeRouteFiles(for entity: RouteEntity, package: RoutePackage) throws {
        let routeJSON = entity.routeDirectoryURL.appendingPathComponent("route.json")
        guard !FileManager.default.fileExists(atPath: routeJSON.path) else { return }

        _ = try RoutePackaging.writeRoutePackage(package, to: RouteTracePaths.routesRoot)
        let archiveURL = routepackURL(for: entity)
        if !FileManager.default.fileExists(atPath: archiveURL.path) {
            try RoutePackaging.zipRouteDirectory(entity.routeDirectoryURL, to: archiveURL)
        }
    }
}

enum RouteStoreError: Error, LocalizedError {
    case routeNotFound
    case routePackageUnavailable
    case sourceGPXUnavailable

    var errorDescription: String? {
        switch self {
        case .routeNotFound:
            "The route could not be found."
        case .routePackageUnavailable:
            "The route package is not available locally or in iCloud."
        case .sourceGPXUnavailable:
            "The original GPX file is not available. Re-import this route to change its activity type."
        }
    }
}
