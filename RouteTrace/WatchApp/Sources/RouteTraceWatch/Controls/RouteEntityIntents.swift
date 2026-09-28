import AppIntents
import Foundation
import RouteTraceShared

/// A route on this watch, for Siri and Shortcuts.
struct RouteAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Route"
    static let defaultQuery = RouteAppEntityQuery()

    let id: UUID
    let name: String
    let distanceMeters: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(RouteFormatting.distance(distanceMeters))")
    }

    init(_ route: RoutePackage) {
        id = route.id
        name = route.name
        distanceMeters = route.distanceMeters
    }
}

#if compiler(>=6.4)
/// Route IDs are the same on iPhone and Watch, so a request can move between them.
@available(watchOS 27.0, *)
extension RouteAppEntity: SyncableEntity {}
#endif

struct RouteAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [RouteAppEntity] {
        await routes().filter { identifiers.contains($0.id) }.map(RouteAppEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RouteAppEntity] {
        RouteNameMatcher.matches(string, in: await routes(), name: \.name).map(RouteAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RouteAppEntity] {
        await routes().map(RouteAppEntity.init)
    }

    /// Routes on the watch. An intent can run before the app has loaded them.
    @MainActor
    private func routes() async -> [RoutePackage] {
        let store = WatchRouteStore.shared
        if store.routes.isEmpty {
            await store.reload()
        }
        return store.routes
    }
}

struct StartRouteIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Route"
    static let description = IntentDescription("Start navigating a route.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Route")
    var route: RouteAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$route)")
    }

    init() {}

    init(route: RouteAppEntity) {
        self.route = route
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try RouteStartRequests.shared.request(routeID: route.id)
        return .result()
    }
}
