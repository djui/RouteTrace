import Foundation
import Observation
import RouteTraceShared

@MainActor
@Observable
final class WatchRouteStore {
    static let shared = WatchRouteStore()

    enum DeletionOrigin {
        /// The user deleted the route on the watch.
        case watch
        /// The route was deleted on the iPhone.
        case iPhone
    }

    private(set) var routes: [RoutePackage] = []
    private(set) var routeDirectories: [UUID: URL] = [:]
    private(set) var isLoading = false
    private(set) var lastError: String?

    var lastSelectedRouteID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.lastRouteKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: Self.lastRouteKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastRouteKey)
            }
        }
    }

    var lastSelectedRoute: RoutePackage? {
        guard let id = lastSelectedRouteID else { return routes.first }
        return routes.first { $0.id == id } ?? routes.first
    }

    private static let lastRouteKey = "watch.lastSelectedRouteID"
    private static let deletedRoutesKey = "watch.deletedRouteIDs"

    private let fileManager = FileManager.default

    var routesRootURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Routes", isDirectory: true)
    }

    private init() {}

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        let root = routesRootURL
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            // Decoding every route package is too slow for the main thread on a watch.
            let loaded = try await Task.detached(priority: .userInitiated) {
                try Self.loadPackages(in: root)
            }.value
            routes = loaded.map(\.package).sorted { $0.importedAt > $1.importedAt }
            routeDirectories = Dictionary(uniqueKeysWithValues: loaded.map { ($0.package.id, $0.directory) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private nonisolated static func loadPackages(in root: URL) throws -> [(package: RoutePackage, directory: URL)] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let package = try? RoutePackaging.loadRoutePackage(from: url) else {
                return nil
            }
            return (normalizedOfflineStatus(package, directory: url), url)
        }
    }

    /// A route synced through iCloud carries the iPhone's offline manifest but no tiles; only
    /// claim an offline map when the tiles are actually on this watch.
    private nonisolated static func normalizedOfflineStatus(_ package: RoutePackage, directory: URL) -> RoutePackage {
        guard package.offlineMapManifest != nil else { return package }
        let tiles = directory.appendingPathComponent("tiles", isDirectory: true)
        if FileManager.default.fileExists(atPath: tiles.path) {
            return package
        }
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
            offlineMapManifest: nil,
            navigationWarning: package.navigationWarning
        )
    }

    func directory(for routeID: UUID) -> URL? {
        routeDirectories[routeID]
    }

    func tileStore(for routeID: UUID) -> OfflineTileStore? {
        guard let directory = directory(for: routeID) else { return nil }
        return OfflineTileStore(routeDirectory: directory)
    }

    @discardableResult
    func installRoutePackage(from archiveURL: URL) async throws -> RoutePackage {
        let routeDirectory = try RoutePackaging.installArchive(at: archiveURL, to: routesRootURL)
        let package = try RoutePackaging.loadRoutePackage(from: routeDirectory)
        // Explicitly sent from the iPhone: wanted again even if deleted here before.
        forgetDeletion(of: package.id)
        await reload()
        lastSelectedRouteID = package.id
        return package
    }

    func deleteRoute(id: UUID, origin: DeletionOrigin = .watch) async throws {
        if let directory = directory(for: id) ?? existingDirectory(for: id) {
            try fileManager.removeItem(at: directory)
        }
        if lastSelectedRouteID == id {
            lastSelectedRouteID = nil
        }
        switch origin {
        case .watch:
            // Remember the deletion so the iCloud copy doesn't bring the route back.
            rememberDeletion(of: id)
            WatchConnectivityManager.shared.notifyRouteRemoved(id)
        case .iPhone:
            forgetDeletion(of: id)
        }
        await reload()
    }

    func deleteOfflinePack(id: UUID) async throws {
        guard let directory = directory(for: id) else { return }
        _ = try RoutePackaging.deleteOfflinePack(from: directory)
        await reload()
    }

    func route(with id: UUID) -> RoutePackage? {
        routes.first { $0.id == id }
    }

    // MARK: - Deletion tombstones

    func isDeletedOnWatch(_ id: UUID) -> Bool {
        deletedRouteIDs.contains(id.uuidString)
    }

    private var deletedRouteIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.deletedRoutesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.deletedRoutesKey) }
    }

    private func rememberDeletion(of id: UUID) {
        deletedRouteIDs.insert(id.uuidString)
    }

    private func forgetDeletion(of id: UUID) {
        deletedRouteIDs.remove(id.uuidString)
    }

    private func existingDirectory(for id: UUID) -> URL? {
        let url = routesRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
