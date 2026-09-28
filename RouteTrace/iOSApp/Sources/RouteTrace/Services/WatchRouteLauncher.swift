#if canImport(WatchConnectivity)
import Foundation
import HealthKit
import RouteTraceShared

/// The route library and Watch connection, set up once per process for the app and its intents.
/// A Shortcut can run in the background without the app's views ever appearing.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let routeStore: RouteStore
    let connectivity: PhoneConnectivityManager
    private let watchAutoTransfer: RouteWatchAutoTransfer
    private var isStarted = false

    private init() {
        let context = AppModelContainer.shared.mainContext
        routeStore = RouteStore(context: context)
        connectivity = PhoneConnectivityManager(context: context, routeStore: routeStore)
        watchAutoTransfer = RouteWatchAutoTransfer(routeStore: routeStore, connectivityManager: connectivity)
    }

    /// Loads settings and activates the Watch session. Safe to call more than once.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        _ = try? routeStore.loadSettings()
        watchAutoTransfer.registerWithRouteStore()
        connectivity.onSessionActivated = { [weak self] in
            self?.watchAutoTransfer.transferPendingRoutes()
        }
        connectivity.activate()
    }

    /// Starts the services and waits briefly for the Watch session. Without a watch it may never
    /// activate; callers then find out why from the session state.
    func startAndWaitForWatchSession(timeout: Duration = .seconds(5)) async {
        start()
        let deadline = ContinuousClock.now + timeout
        while !connectivity.isActivated, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
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
    case routeNotFound
    case watchNotPaired
    case watchAppNotInstalled
    case transferFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .routeNotFound: "That route isn’t in your library anymore."
        case .watchNotPaired: "No Apple Watch is paired with this iPhone."
        case .watchAppNotInstalled: "RouteTrace isn’t installed on your Apple Watch."
        case .transferFailed(let message): "\(message)"
        }
    }
}
#endif
