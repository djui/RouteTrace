import Foundation
import Observation

/// Someone's own order of their routes.
///
/// Kept on each device rather than in the CloudKit store, and synced between iPhone and Watch;
/// the newer order wins. Routes the order doesn't know yet (new imports) go on top.
public struct RouteOrder: Codable, Equatable, Sendable {
    public let routeIDs: [UUID]
    public let updatedAt: Date

    public init(routeIDs: [UUID], updatedAt: Date = Date()) {
        self.routeIDs = routeIDs
        self.updatedAt = updatedAt
    }

    /// Routes in this order, after the ones it doesn't know yet, which stay newest first.
    public func sorted<Route>(_ routes: [Route], id: (Route) -> UUID, importedAt: (Route) -> Date) -> [Route] {
        var positions: [UUID: Int] = [:]
        for (position, routeID) in routeIDs.enumerated() where positions[routeID] == nil {
            positions[routeID] = position
        }
        let unknown = routes
            .filter { positions[id($0)] == nil }
            .sorted { importedAt($0) > importedAt($1) }
        let known = routes
            .compactMap { route in positions[id(route)].map { (position: $0, route: route) } }
            .sorted { $0.position < $1.position }
            .map(\.route)
        return unknown + known
    }

    /// The order after moving `sources` in front of `destination`, or to the end when it's nil,
    /// in the list as shown. Routes this device doesn't show keep their order, after the others.
    public func moving(_ sources: [UUID], before destination: UUID?, displayed: [UUID], at date: Date = Date()) -> RouteOrder {
        let movingSet = Set(sources)
        let moving = displayed.filter { movingSet.contains($0) }

        // Dropping a route in front of itself (or of another dragged one) leaves it in place.
        var anchor = destination
        if let destination, movingSet.contains(destination), let start = displayed.firstIndex(of: destination) {
            anchor = displayed[(start + 1)...].first { !movingSet.contains($0) }
        }

        var reordered = displayed.filter { !movingSet.contains($0) }
        let insertion = anchor.flatMap { reordered.firstIndex(of: $0) } ?? reordered.endIndex
        reordered.insert(contentsOf: moving, at: insertion)

        let shown = Set(displayed)
        let notShown = routeIDs.filter { !shown.contains($0) }
        return RouteOrder(routeIDs: reordered + notShown, updatedAt: date)
    }

    /// `List.onMove` offsets as a move in front of a route.
    public static func destination(forListOffset offset: Int, in displayed: [UUID]) -> UUID? {
        displayed.indices.contains(offset) ? displayed[offset] : nil
    }

    // MARK: - Sync

    public var dictionaryRepresentation: [String: Any] {
        [
            "type": WatchMessageType.routeOrder,
            "routeIds": routeIDs.map(\.uuidString),
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
    }

    public init?(dictionary: [String: Any]) {
        guard dictionary["type"] as? String == WatchMessageType.routeOrder,
              let ids = dictionary["routeIds"] as? [String],
              let timestamp = dictionary["updatedAt"] as? TimeInterval else {
            return nil
        }
        self.init(routeIDs: ids.compactMap(UUID.init(uuidString:)), updatedAt: Date(timeIntervalSince1970: timestamp))
    }
}

/// The route order on this device, persisted in user defaults.
@MainActor
@Observable
public final class RouteOrderStore {
    public static let shared = RouteOrderStore()

    public private(set) var order: RouteOrder?

    private let defaults: UserDefaults
    private static let key = "routeOrder"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Stored like the sync payload, which keeps sub-second timestamps for "newer wins".
        order = defaults.dictionary(forKey: Self.key).flatMap(RouteOrder.init(dictionary:))
    }

    /// Routes in the saved order, or newest first until someone reorders them.
    public func sorted<Route>(_ routes: [Route], id: (Route) -> UUID, importedAt: (Route) -> Date) -> [Route] {
        guard let order else { return routes.sorted { importedAt($0) > importedAt($1) } }
        return order.sorted(routes, id: id, importedAt: importedAt)
    }

    /// Saves a reorder made on this device.
    public func update(_ newOrder: RouteOrder) {
        order = newOrder
        persist()
    }

    /// Applies an order from the other device if it's newer. Returns whether it was applied.
    @discardableResult
    public func apply(_ incoming: RouteOrder) -> Bool {
        if let order, order.updatedAt >= incoming.updatedAt {
            return false
        }
        order = incoming
        persist()
        return true
    }

    private func persist() {
        guard let order else { return }
        defaults.set(order.dictionaryRepresentation, forKey: Self.key)
    }
}
