#if canImport(WatchConnectivity)
import Foundation
import HealthKit
import RouteTraceShared

/// The route library and Watch connection the root view sets up, for intents that need them.
@MainActor
final class AppServices {
    static let shared = AppServices()

    struct Ready {
        let routeStore: RouteStore
        let connectivity: PhoneConnectivityManager
    }

    private var services: Ready?

    private init() {}

    func register(routeStore: RouteStore, connectivity: PhoneConnectivityManager) {
        services = Ready(routeStore: routeStore, connectivity: connectivity)
    }

    /// Waits for the app to finish opening and its Watch session to activate. Without a watch the
    /// session may never activate; the caller then gets the services and reports why.
    func ready(timeout: Duration = .seconds(5)) async -> Ready? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let services, services.connectivity.isActivated {
                return services
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return services
    }
}

enum WatchRouteLauncher {
    enum Outcome {
        case started
        /// The watch couldn't be opened (locked, out of range); the start request waits there.
        case waitingForWatch
    }

    /// Sends the route to the watch if it isn't there yet, asks the watch to start it, and opens
    /// RouteTrace on the watch. The watch drops the request if it isn't opened within two minutes.
    @MainActor
    static func start(
        routeID: UUID,
        routeStore: RouteStore,
        connectivity: PhoneConnectivityManager
    ) async throws -> Outcome {
        guard let route = try routeStore.fetchRoute(id: routeID) else { throw StartOnWatchError.routeNotFound }

        connectivity.refreshSessionState()
        guard connectivity.isWatchPaired else { throw StartOnWatchError.watchNotPaired }
        guard connectivity.isWatchAppInstalled else { throw StartOnWatchError.watchAppNotInstalled }

        do {
            if route.transferState != .installed {
                try connectivity.transferRouteToWatch(routeID: routeID)
            }
            try connectivity.requestRouteStart(routeID)
        } catch {
            throw StartOnWatchError.transferFailed(error.localizedDescription)
        }

        do {
            try await HKHealthStore().startWatchApp(toHandle: workoutConfiguration(for: route.activityHint))
            return .started
        } catch {
            return .waitingForWatch
        }
    }

    static func workoutConfiguration(for activityKind: ActivityKind) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityKind.speedCategory == .cycling ? .cycling : .running
        configuration.locationType = .outdoor
        return configuration
    }
}

enum StartOnWatchError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case routeNotFound
    case watchNotPaired
    case watchAppNotInstalled
    case transferFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: "RouteTrace couldn’t reach your Apple Watch. Try again."
        case .routeNotFound: "That route isn’t in your library anymore."
        case .watchNotPaired: "No Apple Watch is paired with this iPhone."
        case .watchAppNotInstalled: "RouteTrace isn’t installed on your Apple Watch."
        case .transferFailed(let message): "\(message)"
        }
    }
}
#endif
