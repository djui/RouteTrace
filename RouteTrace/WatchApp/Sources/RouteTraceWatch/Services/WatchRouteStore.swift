import Foundation
import Observation
import RouteTraceShared

@MainActor
@Observable
final class WatchRouteStore {
    static let shared = WatchRouteStore()

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

    private let fileManager = FileManager.default

    var routesRootURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Routes", isDirectory: true)
    }

    private init() {}

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try fileManager.createDirectory(at: routesRootURL, withIntermediateDirectories: true)
            let contents = try fileManager.contentsOfDirectory(
                at: routesRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var loaded: [RoutePackage] = []
            var directories: [UUID: URL] = [:]

            for url in contents {
                var isDirectory = ObjCBool(false)
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }
                do {
                    let package = try RoutePackaging.loadRoutePackage(from: url)
                    loaded.append(package)
                    directories[package.id] = url
                } catch {
                    lastError = error.localizedDescription
                }
            }

            routes = loaded.sorted { $0.importedAt > $1.importedAt }
            routeDirectories = directories
        } catch {
            lastError = error.localizedDescription
        }
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
        await reload()
        lastSelectedRouteID = package.id
        return package
    }

    @discardableResult
    func saveRoutePackage(_ package: RoutePackage) async throws -> URL {
        let directory = try RoutePackaging.writeRoutePackage(package, to: routesRootURL)
        await reload()
        return directory
    }

    func deleteRoute(id: UUID) async throws {
        guard let directory = directory(for: id) else { return }
        try fileManager.removeItem(at: directory)
        if lastSelectedRouteID == id {
            lastSelectedRouteID = nil
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
}
