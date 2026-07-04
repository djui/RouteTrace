import Foundation

/// Copies WCSession inbox files synchronously before async handling.
/// WCSession may delete `file.fileURL` after the delegate returns.
public enum WCSessionFileInbox {
    public static func copyToTemporaryURL(from sourceURL: URL, prefix: String = "wc-inbox") throws -> URL {
        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
