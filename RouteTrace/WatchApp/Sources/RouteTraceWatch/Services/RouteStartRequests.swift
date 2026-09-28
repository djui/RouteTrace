import Foundation
import Observation
import RouteTraceShared

/// Start requests from Siri, Shortcuts or the iPhone, held until the route list can act on them.
///
/// An intent that opens the app runs before the app's views exist, so a notification posted from
/// it goes unheard on a cold launch. The request waits here instead.
@MainActor
@Observable
final class RouteStartRequests {
    static let shared = RouteStartRequests()

    private(set) var pending: RouteStartRequest?

    private init() {}

    /// True while an activity is recording, paused or waiting in its summary.
    static var isActivityInProgress: Bool {
        guard let phase = ActiveActivityPersistence.load()?.phase else { return false }
        return ["active", "paused", "summary"].contains(phase)
    }

    func request(routeID: UUID) throws {
        guard !Self.isActivityInProgress else { throw RouteIntentError.activityInProgress }
        pending = RouteStartRequest(routeID: routeID)
    }

    func receive(_ request: RouteStartRequest) {
        guard request.isFresh(), !Self.isActivityInProgress else { return }
        pending = request
    }

    /// The route to start now. Keeps the request while its route is still on its way from the
    /// iPhone, and drops it once it's stale.
    func takeRoute(from store: WatchRouteStore, at date: Date = Date()) -> RoutePackage? {
        guard let pending else { return nil }
        guard pending.isFresh(at: date) else {
            self.pending = nil
            return nil
        }
        guard let route = store.route(with: pending.routeID) else { return nil }
        self.pending = nil
        return route
    }

    func cancel() {
        pending = nil
    }
}

enum RouteIntentError: Error, CustomLocalizedStringResourceConvertible {
    case activityInProgress
    case noRoutes

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .activityInProgress: "Finish or discard the current activity first."
        case .noRoutes: "There are no routes on this Apple Watch yet."
        }
    }
}
