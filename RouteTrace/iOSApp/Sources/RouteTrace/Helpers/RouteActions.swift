import Foundation
import RouteTraceShared
import SwiftUI

enum RouteActions {
    static func exportGPXURL(for package: RoutePackage, routeID: UUID) throws -> URL {
        let gpx = GPXExporter.exportRoute(package)
        let url = RouteTracePaths.routesRoot
            .appendingPathComponent("\(routeID.uuidString)-export.gpx")
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func exportActivityGPXURL(for recording: ActivityRecording, route: RoutePackage?) throws -> URL {
        let gpx = GPXExporter.exportActivity(recording, route: route)
        let url = RouteTracePaths.activitiesRoot
            .appendingPathComponent("\(recording.id.uuidString).gpx")
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func cleanupExport(at url: URL?) {
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func offlineMapActionLabel(for status: OfflinePackStatus) -> String {
        status == .missing ? "Build Offline Map" : "Rebuild Offline Map"
    }

    static func offlineMapBuildErrorMessage(for error: Error) -> String {
        if let buildError = error as? OfflinePackBuilder.BuildError {
            return buildError.localizedDescription
        }
        if (error as NSError).domain == NSCocoaErrorDomain,
           (error as NSError).code == NSFileReadNoSuchFileError {
            return "Failed to package the offline map for Watch transfer. Try building again."
        }
        return error.localizedDescription
    }
}

struct RouteActionMenuItems: View {
    let route: RouteEntity
    var routePackage: RoutePackage?
    var isExporting: Bool = false
    var isBuildingOfflinePack: Bool = false
    var isSendingToWatch: Bool = false
    var onRebuildOfflineMap: () -> Void
    var onSendToWatch: (() -> Void)?
    var onRename: (() -> Void)?
    var onShare: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button {
            onRebuildOfflineMap()
        } label: {
            Label(
                RouteActions.offlineMapActionLabel(for: route.offlineStatus),
                systemImage: "map.fill"
            )
        }
        .disabled(isBuildingOfflinePack)

        #if canImport(WatchConnectivity)
        if let onSendToWatch {
            Button {
                onSendToWatch()
            } label: {
                Label("Send to Apple Watch", systemImage: "applewatch.and.arrow.forward")
            }
            .disabled(isSendingToWatch)
        }
        #endif

        if let onRename {
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }

        Divider()

        Button {
            onShare()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(isExporting || routePackage == nil)

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
