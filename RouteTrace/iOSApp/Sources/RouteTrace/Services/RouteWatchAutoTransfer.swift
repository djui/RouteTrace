#if canImport(WatchConnectivity)
import Foundation
import RouteTraceShared

@MainActor
final class RouteWatchAutoTransfer {
    private let routeStore: RouteStore
    private let connectivityManager: PhoneConnectivityManager

    init(routeStore: RouteStore, connectivityManager: PhoneConnectivityManager) {
        self.routeStore = routeStore
        self.connectivityManager = connectivityManager
    }

    func registerWithRouteStore() {
        routeStore.onRoutePackageSaved = { [weak self] routeID in
            self?.queueTransfer(for: routeID)
        }
    }

    func queueTransfer(for routeID: UUID) {
        guard connectivityManager.canTransferToWatch else { return }
        do {
            try connectivityManager.transferRouteToWatch(routeID: routeID)
        } catch {
            // Auto-transfer is best-effort; manual Send to Watch remains available.
        }
    }

    func transferPendingRoutes() {
        guard connectivityManager.canTransferToWatch else { return }
        guard let routes = try? routeStore.fetchRoutes() else { return }

        for route in routes where route.transferState != .installed {
            queueTransfer(for: route.id)
        }
    }
}
#endif
