import Foundation
import UniformTypeIdentifiers

enum GPXDocumentSupport {
    static let typeIdentifier = "com.topografix.gpx"

    static var gpxType: UTType {
        UTType(filenameExtension: "gpx")
            ?? UTType(importedAs: typeIdentifier)
    }

    static func isGPX(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "gpx" { return true }
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let type = values.contentType {
            return type.conforms(to: gpxType) || type.conforms(to: .xml)
        }
        return false
    }
}

@MainActor
final class IncomingGPXCoordinator: ObservableObject {
    @Published var pendingImport: IncomingGPXItem?

    func handleIncomingURL(_ url: URL) {
        guard GPXDocumentSupport.isGPX(url) else { return }
        pendingImport = IncomingGPXItem(url: url)
    }

    func clearPending() {
        pendingImport = nil
    }
}

struct IncomingGPXItem: Identifiable {
    let id = UUID()
    let url: URL
}
