import Foundation
import os
import SwiftData
import RouteTraceShared

/// A parsed GPX file awaiting confirmation in the import sheet.
struct GPXImportCandidate: Sendable {
    let data: Data
    let fileName: String
    let parsed: ParsedGPX

    /// The name the GPX file gives itself, falling back to the file name.
    var suggestedName: String {
        parsed.importName ?? (fileName as NSString).deletingPathExtension
    }

    /// Reads and parses the file off the main thread.
    static func load(from url: URL) async throws -> GPXImportCandidate {
        try await Task.detached(priority: .userInitiated) {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let parsed = try GPXParser().parse(data: data)
            return GPXImportCandidate(data: data, fileName: url.lastPathComponent, parsed: parsed)
        }.value
    }

    /// Processes the route the way it would be saved, for the preview.
    func previewPackage(activity: ActivityKind, reverseDirection: Bool) async -> RoutePackage {
        let parsed = parsed
        let fileName = fileName
        return await Task.detached(priority: .userInitiated) {
            RouteProcessor().makeRoutePackage(
                from: parsed,
                sourceFileName: fileName,
                activityHint: activity,
                reverseDirection: reverseDirection
            )
        }.value
    }
}

@MainActor
final class RouteImportService {
    private static let signposter = OSSignposter(subsystem: "com.uwe.RouteTrace", category: "Import")

    private let routeStore: RouteStore

    init(routeStore: RouteStore) {
        self.routeStore = routeStore
    }

    /// Saves the route. When requested, the offline map is built in the background afterwards,
    /// with progress shown in the route list and detail screen.
    @discardableResult
    func importRoute(
        _ candidate: GPXImportCandidate,
        name: String,
        activityHint: ActivityKind,
        reverseDirection: Bool,
        buildOfflinePack: Bool
    ) async throws -> RouteEntity {
        let signpostID = Self.signposter.makeSignpostID()
        let importState = Self.signposter.beginInterval("Import route", id: signpostID)
        defer { Self.signposter.endInterval("Import route", importState) }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = candidate.parsed
        let fileName = candidate.fileName
        let package = await Task.detached(priority: .userInitiated) {
            RouteProcessor().makeRoutePackage(
                from: parsed,
                sourceFileName: fileName,
                activityHint: activityHint,
                customName: trimmedName.isEmpty ? nil : trimmedName,
                reverseDirection: reverseDirection
            )
        }.value

        Self.signposter.emitEvent("Processed", id: signpostID, "\(package.route.count) navigation points")
        let entity = try routeStore.saveRoutePackage(package)
        Self.signposter.emitEvent("Saved", id: signpostID)
        let sourceURL = RouteTracePaths.sourceGPXURL(for: package.id)
        if reverseDirection {
            let validPoints = parsed.primaryTrackPoints.filter {
                MapMath.isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            }
            try GPXExporter.writeTrack(
                name: package.name,
                points: Array(validPoints.reversed()),
                to: sourceURL
            )
        } else {
            try candidate.data.write(to: sourceURL, options: .atomic)
        }

        if buildOfflinePack {
            routeStore.startOfflinePackBuild(for: entity)
        }

        return entity
    }
}
