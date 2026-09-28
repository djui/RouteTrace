import Foundation
import RouteTraceShared
import SwiftUI

enum RouteActions {
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

extension GPXDocument {
    /// Exports the stored route lazily; used where the package isn't loaded (list context menus).
    static func storedRoute(id: UUID, name: String) -> GPXDocument {
        let directory = RouteTracePaths.routeDirectory(for: id)
        return GPXDocument(fileName: name) {
            let package = try RoutePackaging.loadRoutePackage(from: directory)
            return GPXExporter.exportRoute(package.renamed(to: name))
        }
    }

    /// Exports a stored activity lazily from its JSON copy on disk.
    static func storedActivity(id: UUID, title: String) -> GPXDocument {
        let url = RouteTracePaths.activitiesRoot.appendingPathComponent("\(id.uuidString).json")
        return GPXDocument(fileName: title) {
            let recording = try RouteTracePayloadCoding.decode(ActivityRecording.self, from: Data(contentsOf: url))
            return GPXExporter.exportActivity(recording.renamed(to: title), route: nil)
        }
    }
}

/// Actions for a route, shared by the list's context menu and the detail screen's menu.
struct RouteActionMenuItems: View {
    let route: RouteEntity
    var isBusy = false
    var onActivityKindChange: (ActivityKind) -> Void
    var onReverseDirection: () -> Void
    var onSendToWatch: (() -> Void)?
    var onRename: () -> Void
    var showsShare = true
    var onDelete: () -> Void

    var body: some View {
        Section {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }

            Menu {
                ForEach(ActivityKind.allCases) { kind in
                    Button {
                        onActivityKindChange(kind)
                    } label: {
                        if kind == route.activityHint {
                            Label(kind.displayName, systemImage: "checkmark")
                        } else {
                            Label(kind.displayName, systemImage: kind.systemImage)
                        }
                    }
                    .disabled(kind == route.activityHint)
                }
            } label: {
                Label("Activity: \(route.activityHint.displayName)", systemImage: route.activityHint.systemImage)
            }
            .disabled(isBusy)

            Button(action: onReverseDirection) {
                Label("Reverse Direction", systemImage: "arrow.left.arrow.right")
            }
            .disabled(isBusy)
        }

        Section {
            if let onSendToWatch {
                Button(action: onSendToWatch) {
                    Label("Send to Apple Watch", systemImage: "applewatch.and.arrow.forward")
                }
                .disabled(!route.transferState.canSend)
            }

            if showsShare {
                ShareLink(
                    item: GPXDocument.storedRoute(id: route.id, name: route.name),
                    preview: SharePreview(route.name)
                ) {
                    Label("Share GPX", systemImage: "square.and.arrow.up")
                }
            }
        }

        Section {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
