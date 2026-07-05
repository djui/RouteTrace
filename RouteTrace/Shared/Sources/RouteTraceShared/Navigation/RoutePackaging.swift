import Foundation

private struct RoutePackArchiveIndex: Codable {
    static let currentVersion = 1

    let version: Int
    let routeId: UUID
    let files: [Entry]

    struct Entry: Codable {
        let relativePath: String
        let offset: Int
        let length: Int
    }
}

public enum RoutePackaging {
    public static let routepackExtension = "routepack"
    private static let archiveMagic = Data("RTPK".utf8)

    public static func writeRoutePackage(_ package: RoutePackage, to directory: URL) throws -> URL {
        let routeDirectory = directory.appendingPathComponent(package.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: routeDirectory, withIntermediateDirectories: true)

        let routeURL = routeDirectory.appendingPathComponent("route.json")
        let data = try RouteTracePayloadCoding.encode(package)
        try data.write(to: routeURL, options: .atomic)
        return routeDirectory
    }

    public static func loadRoutePackage(from directory: URL) throws -> RoutePackage {
        let routeURL = directory.appendingPathComponent("route.json")
        let data = try Data(contentsOf: routeURL)
        return try RouteTracePayloadCoding.decode(RoutePackage.self, from: data)
    }

    public static func makeArchiveURL(for package: RoutePackage, in directory: URL) -> URL {
        directory.appendingPathComponent("\(package.id.uuidString).\(routepackExtension)")
    }

    public static func zipRouteDirectory(_ routeDirectory: URL, to archiveURL: URL) throws {
        let package = try loadRoutePackage(from: routeDirectory)
        try createArchive(from: routeDirectory, routeId: package.id, to: archiveURL)
    }

    public static func createArchive(from routeDirectory: URL, routeId: UUID, to archiveURL: URL) throws {
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }

        let routeDirectory = routeDirectory.standardizedFileURL
        var entries: [RoutePackArchiveIndex.Entry] = []
        var payload = Data()

        let relativePaths = try collectPackableFiles(in: routeDirectory)
        for relativePath in relativePaths.sorted() {
            let fileURL = routeDirectory.appendingPathComponent(relativePath, isDirectory: false)
            let fileData = try Data(contentsOf: fileURL)
            entries.append(
                RoutePackArchiveIndex.Entry(
                    relativePath: relativePath,
                    offset: payload.count,
                    length: fileData.count
                )
            )
            payload.append(fileData)
        }

        let index = RoutePackArchiveIndex(version: RoutePackArchiveIndex.currentVersion, routeId: routeId, files: entries)
        let indexData = try RouteTracePayloadCoding.encode(index)

        var archive = Data()
        archive.append(archiveMagic)
        var indexLength = UInt32(indexData.count).bigEndian
        withUnsafeBytes(of: &indexLength) { archive.append(contentsOf: $0) }
        archive.append(indexData)
        archive.append(payload)

        try archive.write(to: archiveURL, options: .atomic)
    }

    public static func installArchive(at archiveURL: URL, to routesRoot: URL) throws -> URL {
        let data = try Data(contentsOf: archiveURL)
        if data.starts(with: archiveMagic) {
            return try installBinaryArchive(data: data, to: routesRoot)
        }
        // Legacy: plain JSON route package
        let package = try RouteTracePayloadCoding.decode(RoutePackage.self, from: data)
        return try writeRoutePackage(package, to: routesRoot)
    }

    @discardableResult
    public static func deleteOfflinePack(from routeDirectory: URL) throws -> RoutePackage {
        let fileManager = FileManager.default
        let tilesDirectory = routeDirectory.appendingPathComponent("tiles", isDirectory: true)
        let manifestURL = routeDirectory.appendingPathComponent("manifest.json")

        if fileManager.fileExists(atPath: tilesDirectory.path) {
            try fileManager.removeItem(at: tilesDirectory)
        }
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        var package = try loadRoutePackage(from: routeDirectory)
        package = RoutePackage(
            id: package.id,
            name: package.name,
            sourceFileName: package.sourceFileName,
            importedAt: package.importedAt,
            activityHint: package.activityHint,
            distanceMeters: package.distanceMeters,
            elevationGainMeters: package.elevationGainMeters,
            elevationLossMeters: package.elevationLossMeters,
            boundingBox: package.boundingBox,
            originalPointCount: package.originalPointCount,
            simplifiedPointCount: package.simplifiedPointCount,
            route: package.route,
            cues: package.cues,
            offlineMapManifest: nil,
            navigationWarning: package.navigationWarning
        )

        let routeURL = routeDirectory.appendingPathComponent("route.json")
        try RouteTracePayloadCoding.encode(package).write(to: routeURL, options: .atomic)
        return package
    }

    public static func archiveNeedsRebuild(routeDirectory: URL, archiveURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: archiveURL.path) else { return true }

        let routeJSON = routeDirectory.appendingPathComponent("route.json")
        guard let routeModified = try? routeJSON.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let archiveModified = try? archiveURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return true
        }

        if routeModified > archiveModified { return true }

        let manifestURL = routeDirectory.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path),
           let manifestModified = try? manifestURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           manifestModified > archiveModified {
            return true
        }

        let tilesDirectory = routeDirectory.appendingPathComponent("tiles", isDirectory: true)
        if fileManager.fileExists(atPath: tilesDirectory.path),
           let tilesModified = try? tilesDirectory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           tilesModified > archiveModified {
            return true
        }

        return false
    }

    private static func collectPackableFiles(in routeDirectory: URL) throws -> [String] {
        let fileManager = FileManager.default
        let routeDirectory = routeDirectory.standardizedFileURL
        var results: [String] = []

        let routeJSON = routeDirectory.appendingPathComponent("route.json")
        if fileManager.fileExists(atPath: routeJSON.path) {
            results.append("route.json")
        }

        let manifestURL = routeDirectory.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            results.append("manifest.json")
        }

        let tilesDirectory = routeDirectory.appendingPathComponent("tiles", isDirectory: true)
        if fileManager.fileExists(atPath: tilesDirectory.path) {
            let enumerator = fileManager.enumerator(
                at: tilesDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let url = enumerator?.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                results.append("tiles/\(url.lastPathComponent)")
            }
        }

        return results
    }

    private static func installBinaryArchive(data: Data, to routesRoot: URL) throws -> URL {
        guard data.count > 8 else {
            throw RoutePackagingError.invalidArchive
        }

        let indexLength = Int(UInt32(bigEndian: data.subdata(in: 4 ..< 8).withUnsafeBytes { $0.load(as: UInt32.self) }))
        let indexStart = 8
        let indexEnd = indexStart + indexLength
        guard indexEnd <= data.count else {
            throw RoutePackagingError.invalidArchive
        }

        let index = try RouteTracePayloadCoding.decode(
            RoutePackArchiveIndex.self,
            from: data.subdata(in: indexStart ..< indexEnd)
        )
        let payloadStart = indexEnd
        let routeDirectory = routesRoot.appendingPathComponent(index.routeId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: routeDirectory, withIntermediateDirectories: true)

        for entry in index.files {
            let start = payloadStart + entry.offset
            let end = start + entry.length
            guard end <= data.count else {
                throw RoutePackagingError.invalidArchive
            }
            let fileData = data.subdata(in: start ..< end)
            let destination = routeDirectory.appendingPathComponent(entry.relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileData.write(to: destination, options: .atomic)
        }

        return routeDirectory
    }
}

public enum RoutePackagingError: Error, LocalizedError {
    case invalidArchive

    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "The route pack archive is invalid or corrupted."
        }
    }
}

public enum RouteFormatting {
    public static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    public static func elevation(_ meters: Double?) -> String {
        guard let meters else { return "—" }
        return String(format: "%.0f m", meters)
    }

    public static func pace(secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "—" }
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    public static func speed(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond > 0 else { return "—" }
        return String(format: "%.1f km/h", metersPerSecond * 3.6)
    }

    public static func speedOrPace(_ metersPerSecond: Double?, mode: SpeedDisplayMode) -> String {
        guard let metersPerSecond, metersPerSecond > 0 else { return "—" }
        switch mode {
        case .pace:
            return pace(secondsPerKm: 1000.0 / metersPerSecond)
        case .speed:
            return speed(metersPerSecond)
        }
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
