import Foundation
import SwiftData
import RouteTraceShared

@MainActor
final class RouteImportService {
    private let routeStore: RouteStore
    private let parser = GPXParser()
    private let processor = RouteProcessor()

    init(routeStore: RouteStore) {
        self.routeStore = routeStore
    }

    func importGPX(
        data: Data,
        fileName: String,
        customName: String?,
        activityHint: ActivityKind,
        buildOfflinePack: Bool = false,
        onOfflineBuildProgress: ((OfflinePackBuildProgress) -> Void)? = nil
    ) async throws -> RouteEntity {
        let parsed = try parser.parse(data: data)
        let package = processor.makeRoutePackage(
            from: parsed,
            sourceFileName: fileName,
            activityHint: activityHint,
            customName: customName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        let entity = try routeStore.saveRoutePackage(package)
        let sourceURL = RouteTracePaths.sourceGPXURL(for: package.id)
        try data.write(to: sourceURL, options: .atomic)

        if buildOfflinePack {
            return try await routeStore.buildOfflinePack(
                for: entity,
                onProgress: onOfflineBuildProgress
            )
        }

        return entity
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
