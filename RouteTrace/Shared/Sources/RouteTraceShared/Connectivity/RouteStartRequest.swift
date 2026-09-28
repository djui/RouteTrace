import Foundation

/// A request to start navigating a route right away, from Siri or Shortcuts.
///
/// Requests expire: one queued while the watch was out of reach must not start a route when it
/// finally arrives, possibly hours later.
public struct RouteStartRequest: Equatable, Sendable {
    public static let maximumAge: TimeInterval = 120

    public let routeID: UUID
    public let requestedAt: Date

    public init(routeID: UUID, requestedAt: Date = Date()) {
        self.routeID = routeID
        self.requestedAt = requestedAt
    }

    /// Tolerates the phone's clock running a little ahead of the watch's.
    public func isFresh(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(requestedAt)
        return age <= Self.maximumAge && age >= -Self.maximumAge
    }

    public var dictionaryRepresentation: [String: Any] {
        [
            "type": WatchMessageType.startRoute,
            "routeId": routeID.uuidString,
            "requestedAt": requestedAt.timeIntervalSince1970
        ]
    }

    public init?(dictionary: [String: Any]) {
        guard dictionary["type"] as? String == WatchMessageType.startRoute,
              let idString = dictionary["routeId"] as? String,
              let routeID = UUID(uuidString: idString),
              let timestamp = dictionary["requestedAt"] as? TimeInterval else {
            return nil
        }
        self.init(routeID: routeID, requestedAt: Date(timeIntervalSince1970: timestamp))
    }
}
