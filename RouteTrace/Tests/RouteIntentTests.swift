import XCTest
@testable import RouteTraceShared

final class RouteIntentTests: XCTestCase {
    private let names = ["Sörmland Gravel", "Lac Blanc Trail", "Djurgården Loop", "Loop around the lake", "Gravel Sunday Loop"]

    private func match(_ query: String) -> [String] {
        RouteNameMatcher.matches(query, in: names) { $0 }
    }

    // MARK: - Name matching

    func testMatchingIgnoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(match("sormland gravel"), ["Sörmland Gravel"])
        XCTAssertEqual(match("DJURGARDEN-LOOP"), ["Djurgården Loop"])
    }

    func testBetterMatchesComeFirst() {
        // Whole name, then prefix, then contained, then all words somewhere.
        XCTAssertEqual(match("loop"), ["Loop around the lake", "Djurgården Loop", "Gravel Sunday Loop"])
        XCTAssertEqual(match("gravel"), ["Gravel Sunday Loop", "Sörmland Gravel"])
        XCTAssertEqual(match("sunday gravel"), ["Gravel Sunday Loop"])
    }

    func testExactNameWinsOverLongerNames() {
        let routes = ["Lake Loop Extended", "Lake Loop"]
        XCTAssertEqual(RouteNameMatcher.matches("lake loop", in: routes) { $0 }, ["Lake Loop", "Lake Loop Extended"])
    }

    func testNoMatchOrEmptyQuery() {
        XCTAssertEqual(match("marathon"), [])
        XCTAssertEqual(match("  "), [])
    }

    // MARK: - Start requests

    func testStartRequestRoundTripsThroughUserInfo() throws {
        let request = RouteStartRequest(routeID: UUID(), requestedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let decoded = try XCTUnwrap(RouteStartRequest(dictionary: request.dictionaryRepresentation))

        XCTAssertEqual(decoded, request)
    }

    func testStartRequestIgnoresOtherMessages() {
        XCTAssertNil(RouteStartRequest(dictionary: ["type": WatchMessageType.routeDeleted, "routeId": UUID().uuidString]))
        XCTAssertNil(RouteStartRequest(dictionary: ["type": WatchMessageType.startRoute, "routeId": "not-a-uuid", "requestedAt": 0.0]))
    }

    func testStartRequestExpires() {
        let requestedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let request = RouteStartRequest(routeID: UUID(), requestedAt: requestedAt)

        XCTAssertTrue(request.isFresh(at: requestedAt.addingTimeInterval(30)))
        XCTAssertTrue(request.isFresh(at: requestedAt.addingTimeInterval(-10)), "phone clock slightly ahead")
        XCTAssertFalse(request.isFresh(at: requestedAt.addingTimeInterval(RouteStartRequest.maximumAge + 1)))
        XCTAssertFalse(request.isFresh(at: requestedAt.addingTimeInterval(-RouteStartRequest.maximumAge - 1)))
    }
}
