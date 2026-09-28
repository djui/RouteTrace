import XCTest
@testable import RouteTraceShared

final class RouteOrderTests: XCTestCase {
    private struct Route {
        let id: UUID
        let name: String
        let importedAt: Date
    }

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private lazy var a = Route(id: UUID(), name: "A", importedAt: base)
    private lazy var b = Route(id: UUID(), name: "B", importedAt: base.addingTimeInterval(10))
    private lazy var c = Route(id: UUID(), name: "C", importedAt: base.addingTimeInterval(20))
    private lazy var d = Route(id: UUID(), name: "D", importedAt: base.addingTimeInterval(30))

    private func names(_ order: RouteOrder, _ routes: [Route]) -> [String] {
        order.sorted(routes, id: \.id, importedAt: \.importedAt).map(\.name)
    }

    private func ids(_ routes: Route...) -> [UUID] {
        routes.map(\.id)
    }

    private func names(of order: RouteOrder) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: [a, b, c, d].map { ($0.id, $0.name) })
        return order.routeIDs.compactMap { byID[$0] }
    }

    // MARK: - Sorting

    func testSortedPutsUnknownRoutesFirstNewestFirst() {
        let order = RouteOrder(routeIDs: ids(a, c))

        XCTAssertEqual(names(order, [a, b, c, d]), ["D", "B", "A", "C"])
    }

    func testSortedIgnoresRoutesThatAreGone() {
        let gone = UUID()
        let order = RouteOrder(routeIDs: [gone, b.id, gone, a.id])

        XCTAssertEqual(names(order, [a, b]), ["B", "A"])
    }

    // MARK: - Moving

    func testMovingDownAndUp() {
        let order = RouteOrder(routeIDs: ids(a, b, c, d))
        let displayed = ids(a, b, c, d)

        XCTAssertEqual(names(of: order.moving([a.id], before: c.id, displayed: displayed)), ["B", "A", "C", "D"])
        XCTAssertEqual(names(of: order.moving([d.id], before: a.id, displayed: displayed)), ["D", "A", "B", "C"])
        XCTAssertEqual(names(of: order.moving([b.id], before: nil, displayed: displayed)), ["A", "C", "D", "B"])
    }

    func testMovingInFrontOfItselfKeepsTheOrder() {
        let order = RouteOrder(routeIDs: ids(a, b, c))

        XCTAssertEqual(names(of: order.moving([b.id], before: b.id, displayed: ids(a, b, c))), ["A", "B", "C"])
    }

    func testMovingSeveralKeepsTheirOrder() {
        let order = RouteOrder(routeIDs: ids(a, b, c, d))

        XCTAssertEqual(names(of: order.moving([d.id, a.id], before: c.id, displayed: ids(a, b, c, d))), ["B", "A", "D", "C"])
    }

    func testMovingKeepsRoutesThisDeviceDoesNotShow() {
        // The watch shows A, B and D; C only exists on the iPhone so far.
        let order = RouteOrder(routeIDs: ids(a, b, c, d))

        let moved = order.moving([d.id], before: a.id, displayed: ids(a, b, d))

        XCTAssertEqual(names(of: moved), ["D", "A", "B", "C"])
    }

    func testListOffsetsBecomeADestination() {
        let displayed = ids(a, b, c)
        XCTAssertEqual(RouteOrder.destination(forListOffset: 1, in: displayed), b.id)
        XCTAssertNil(RouteOrder.destination(forListOffset: 3, in: displayed))
    }

    // MARK: - Sync and storage

    func testRoundTripsThroughUserInfo() throws {
        let order = RouteOrder(routeIDs: ids(c, a), updatedAt: base.addingTimeInterval(0.25))

        let decoded = try XCTUnwrap(RouteOrder(dictionary: order.dictionaryRepresentation))

        XCTAssertEqual(decoded, order)
        XCTAssertNil(RouteOrder(dictionary: ["type": WatchMessageType.routeDeleted]))
    }

    @MainActor
    func testStoreKeepsTheNewerOrder() throws {
        let suite = "RouteOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RouteOrderStore(defaults: defaults)
        XCTAssertEqual(store.sorted([a, b, c], id: \.id, importedAt: \.importedAt).map(\.name), ["C", "B", "A"])

        let local = RouteOrder(routeIDs: ids(a, b, c), updatedAt: base.addingTimeInterval(100))
        store.update(local)
        XCTAssertFalse(store.apply(RouteOrder(routeIDs: ids(c, b, a), updatedAt: base.addingTimeInterval(50))))
        XCTAssertTrue(store.apply(RouteOrder(routeIDs: ids(b, a, c), updatedAt: base.addingTimeInterval(100.5))))

        let reloaded = RouteOrderStore(defaults: defaults)
        XCTAssertEqual(reloaded.sorted([a, b, c], id: \.id, importedAt: \.importedAt).map(\.name), ["B", "A", "C"])
    }
}
