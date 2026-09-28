#if canImport(WatchConnectivity)
import AppIntents
import Foundation
import RouteTraceShared

/// "Download offline map for Sunday Loop": builds the map pack in the background and sends it to
/// the watch, for example from an automation the evening before.
struct DownloadOfflineMapIntent: AppIntent, ProgressReportingIntent {
    static let title: LocalizedStringResource = "Download Offline Map"
    static let description = IntentDescription(
        "Downloads the map along a route for use without a connection and sends it to your Apple Watch."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Route")
    var route: RouteAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Download offline map for \(\.$route)")
    }

    init() {}

    init(route: RouteAppEntity) {
        self.route = route
    }

    /// Not main-actor isolated, so the build closure doesn't cross isolation on its way to the
    /// background task; the build itself runs on the main actor with the route store.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppServices.shared.startAndWaitForWatchSession()
        let routeID = route.id
        let progress = progress

        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            // Large maps take minutes; this keeps the build running past the usual 30 seconds.
            try await performBackgroundTask {
                try await Self.build(routeID: routeID, progress: progress)
            }
            return .result(dialog: "\(await Self.completionMessage(routeName: route.name))")
        }
        #endif
        try await Self.build(routeID: routeID, progress: progress)
        return .result(dialog: "\(await Self.completionMessage(routeName: route.name))")
    }

    @MainActor
    private static func build(routeID: UUID, progress: Progress) async throws {
        let store = AppServices.shared.routeStore
        guard let entity = try store.fetchRoute(id: routeID) else { throw OfflineMapIntentError.routeNotFound }

        progress.totalUnitCount = 100
        progress.localizedDescription = String(localized: "Downloading the map for \(entity.name)")
        try await store.buildOfflinePackForShortcut(for: entity) { update in
            progress.completedUnitCount = Int64((update.fractionComplete * 100).rounded())
        }
        progress.completedUnitCount = 100
    }

    /// The finished pack goes to the watch on its own when one is connected.
    @MainActor
    private static func completionMessage(routeName: String) -> String {
        if AppServices.shared.connectivity.canTransferToWatch {
            return String(localized: "The offline map for \(routeName) is ready and on its way to your Apple Watch.")
        }
        return String(localized: "The offline map for \(routeName) is ready.")
    }
}

#if compiler(>=6.4)
@available(iOS 27.0, *)
extension DownloadOfflineMapIntent: LongRunningIntent {}
#endif

enum OfflineMapIntentError: Error, CustomLocalizedStringResourceConvertible {
    case routeNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .routeNotFound: "That route isn’t in your library anymore."
        }
    }
}
#endif
