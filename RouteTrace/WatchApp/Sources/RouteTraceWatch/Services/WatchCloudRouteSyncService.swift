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
            let store = WatchRouteStore.shared

            for entity in entities where !store.isDeletedOnWatch(entity.id) {
                guard let package = try entity.decodedPackage() else { continue }
                try materializeRouteIfNeeded(routeID: entity.id, package: package, routesRoot: store.routesRootURL)
            }

            await store.reload()
            lastSyncedAt = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func materializeRouteIfNeeded(routeID: UUID, package: RoutePackage, routesRoot: URL) throws {
        let routeDirectory = routesRoot.appendingPathComponent(routeID.uuidString, isDirectory: true)
        let routeJSON = routeDirectory.appendingPathComponent("route.json")

        if FileManager.default.fileExists(atPath: routeJSON.path),
           let existing = try? RoutePackaging.loadRoutePackage(from: routeDirectory) {
            // A route delivered from the iPhone with its offline map stays as delivered; the iPhone
            // re-sends it (tiles included) whenever it changes.
            let hasLocalTiles = FileManager.default.fileExists(
                atPath: routeDirectory.appendingPathComponent("tiles", isDirectory: true).path
            )
            if hasLocalTiles || existing.hasSameWatchMaterializedContent(as: package) {
                return
            }
        }

        _ = try RoutePackaging.writeRoutePackage(package, to: routesRoot)
    }
}
