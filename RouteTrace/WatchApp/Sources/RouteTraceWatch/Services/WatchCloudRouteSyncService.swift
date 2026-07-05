import Foundation
import Observation
import RouteTraceShared

@MainActor
@Observable
final class WatchCloudRouteSyncService {
    static let shared = WatchCloudRouteSyncService()

    private(set) var isSyncing = false
    private(set) var lastSyncError: String?
    private(set) var lastSyncedAt: Date?

    private init() {}

    func applyCloudRoutes(_ entities: [RouteEntity]) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            try RouteTracePaths.ensureDirectoriesExist()

            for entity in entities {
                guard let package = try entity.decodedPackage() else { continue }
                try materializeRouteIfNeeded(routeID: entity.id, package: package)
            }

            await WatchRouteStore.shared.reload()
            lastSyncedAt = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func materializeRouteIfNeeded(routeID: UUID, package: RoutePackage) throws {
        let routeDirectory = WatchRouteStore.shared.routesRootURL
            .appendingPathComponent(routeID.uuidString, isDirectory: true)
        let routeJSON = routeDirectory.appendingPathComponent("route.json")

        if FileManager.default.fileExists(atPath: routeJSON.path),
           let existing = try? RoutePackaging.loadRoutePackage(from: routeDirectory),
           existing.importedAt == package.importedAt,
           existing.name == package.name,
           existing.simplifiedPointCount == package.simplifiedPointCount,
           existing.offlineStatus == package.offlineStatus {
            return
        }

        _ = try RoutePackaging.writeRoutePackage(package, to: WatchRouteStore.shared.routesRootURL)
    }
}
