#if canImport(WatchConnectivity)
import AppIntents
import Foundation
import RouteTraceShared
import SwiftData

/// A route in the library, for Siri and Shortcuts.
struct RouteAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Route"
    static let defaultQuery = RouteAppEntityQuery()

    let id: UUID
    let name: String
    let distanceMeters: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(RouteFormatting.distance(distanceMeters))")
    }

    init(_ route: RouteEntity) {
        id = route.id
        name = route.name
        distanceMeters = route.distanceMeters
    }
}

#if compiler(>=6.4)
/// Route IDs are the same on iPhone and Watch, so a request can move between them.
@available(iOS 27.0, *)
extension RouteAppEntity: SyncableEntity {}
#endif

struct RouteAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [RouteAppEntity] {
        try routes().filter { identifiers.contains($0.id) }.map(RouteAppEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RouteAppEntity] {
        RouteNameMatcher.matches(string, in: try routes(), name: \.name).map(RouteAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RouteAppEntity] {
        try routes().map(RouteAppEntity.init)
    }

    @MainActor
    private func routes() throws -> [RouteEntity] {
        try AppModelContainer.shared.mainContext.fetch(
            FetchDescriptor<RouteEntity>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)])
        )
    }
}

struct StartRouteOnWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Route on Apple Watch"
    static let description = IntentDescription("Opens RouteTrace on your Apple Watch and starts navigating the route.")
    /// The app sets up its Watch connection when it opens.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Route")
    var route: RouteAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$route) on Apple Watch")
    }

    init() {}

    init(route: RouteAppEntity) {
        self.route = route
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = AppServices.shared
        await services.startAndWaitForWatchSession()
        let outcome = try await WatchRouteLauncher.start(
            routeID: route.id,
            routeStore: services.routeStore,
            connectivity: services.connectivity
        )
        switch outcome {
        case .started:
            return .result(dialog: "Starting \(route.name) on your Apple Watch.")
        case .waitingForWatch:
            return .result(dialog: "Open RouteTrace on your Apple Watch to start \(route.name).")
        }
    }
}

struct RouteTraceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRouteOnWatchIntent(),
            phrases: [
                "Start \(\.$route) in \(.applicationName)",
                "Navigate \(\.$route) with \(.applicationName)",
                "Start \(\.$route) on my watch with \(.applicationName)"
            ],
            shortTitle: "Start on Apple Watch",
            systemImageName: "applewatch"
        )
        AppShortcut(
            intent: DownloadOfflineMapIntent(),
            phrases: [
                "Download offline map for \(\.$route) in \(.applicationName)",
                "Get the offline map for \(\.$route) with \(.applicationName)"
            ],
            shortTitle: "Download Offline Map",
            systemImageName: "arrow.down.circle"
        )
    }
}
#endif
