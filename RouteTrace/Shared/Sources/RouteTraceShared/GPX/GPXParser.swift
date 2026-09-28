import Foundation

public struct ParsedGPXPoint: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let elevationMeters: Double?
    public let timestamp: Date?

    public init(latitude: Double, longitude: Double, elevationMeters: Double?, timestamp: Date?) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
        self.timestamp = timestamp
    }
}

public struct ParsedGPXTrack: Sendable {
    public let name: String?
    public let segments: [[ParsedGPXPoint]]

    public init(name: String?, segments: [[ParsedGPXPoint]]) {
        self.name = name
        self.segments = segments
    }
}

public struct ParsedGPXRoute: Sendable {
    public let name: String?
    public let points: [ParsedGPXPoint]
}

public struct ParsedGPXWaypoint: Sendable, Identifiable {
    public let id = UUID()
    public let name: String?
    public let point: ParsedGPXPoint
}

public struct ParsedGPX: Sendable {
    public let metadataName: String?
    public let tracks: [ParsedGPXTrack]
    public let routes: [ParsedGPXRoute]
    public let waypoints: [ParsedGPXWaypoint]
    public let warnings: [String]
    public let invalidPointCount: Int

    public init(
        metadataName: String?,
        tracks: [ParsedGPXTrack],
        routes: [ParsedGPXRoute],
        waypoints: [ParsedGPXWaypoint],
        warnings: [String],
        invalidPointCount: Int
    ) {
        self.metadataName = metadataName
        self.tracks = tracks
        self.routes = routes
        self.waypoints = waypoints
        self.warnings = warnings
        self.invalidPointCount = invalidPointCount
    }

    public var primaryTrackPoints: [ParsedGPXPoint] {
        let trackPoints = tracks.flatMap(\.segments).flatMap { $0 }
        if !trackPoints.isEmpty {
            return trackPoints
        }
        return routes.flatMap(\.points)
    }

    public var usablePointCount: Int {
        primaryTrackPoints.count
    }

    public var importName: String? {
        if let metadata = Self.meaningfulName(metadataName) {
            return metadata
        }
        let trackNames = tracks.compactMap { Self.meaningfulName($0.name) }
        if !trackNames.isEmpty {
            return trackNames.joined(separator: ", ")
        }
        let routeNames = routes.compactMap { Self.meaningfulName($0.name) }
        if !routeNames.isEmpty {
            return routeNames.joined(separator: ", ")
        }
        return nil
    }

    private static let genericMetadataNames: Set<String> = [
        "activity",
        "untitled",
        "route",
        "track",
    ]

    private static func meaningfulName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard !genericMetadataNames.contains(trimmed.lowercased()) else {
            return nil
        }
        return trimmed
    }
}

public enum GPXParserError: Error, LocalizedError {
    case noUsablePoints
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .noUsablePoints:
            "This GPX file has no usable route points."
        case .invalidData:
            "Unable to read GPX data."
        }
    }
}

public struct GPXParser {
    public init() {}

    public func parse(data: Data) throws -> ParsedGPX {
        let delegate = GPXXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw GPXParserError.invalidData
        }
        let parsed = delegate.buildParsedGPX()
        if parsed.usablePointCount == 0 {
            throw GPXParserError.noUsablePoints
        }
        return parsed
    }
}

private final class GPXXMLParserDelegate: NSObject, XMLParserDelegate {
    private var metadataName: String?
    private var tracks: [ParsedGPXTrack] = []
    private var routes: [ParsedGPXRoute] = []
    private var waypoints: [ParsedGPXWaypoint] = []
    private let warnings: [String] = []
    private var invalidPointCount = 0

    private var elementStack: [String] = []
    private var textBuffer = ""
    private var currentTrackName: String?
    private var currentRouteName: String?
    private var currentWaypointName: String?
    private var trackSegments: [[ParsedGPXPoint]] = []
    private var currentSegment: [ParsedGPXPoint] = []
    private var currentRoutePoints: [ParsedGPXPoint] = []
    private var currentPointLat: Double?
    private var currentPointLon: Double?
    private var currentPointEle: Double?
    private var currentPointTime: Date?

    // Creating ISO8601DateFormatter per <time> element dominated parse time for large files.
    private let timestampFormatter = ISO8601DateFormatter()
    private let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func buildParsedGPX() -> ParsedGPX {
        ParsedGPX(
            metadataName: metadataName,
            tracks: tracks,
            routes: routes,
            waypoints: waypoints,
            warnings: warnings,
            invalidPointCount: invalidPointCount
        )
    }

    /// Strips an XML namespace prefix (`gpx:trkpt` → `trkpt`).
    private static func localName(_ elementName: String) -> String {
        guard let colon = elementName.lastIndex(of: ":") else { return elementName }
        return String(elementName[elementName.index(after: colon)...])
    }

    /// The element that directly contains the element currently being closed.
    private var parentElement: String? {
        elementStack.count >= 2 ? elementStack[elementStack.count - 2] : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = Self.localName(elementName)
        elementStack.append(name)
        textBuffer = ""

        switch name {
        case "trk":
            currentTrackName = nil
            trackSegments = []
            currentSegment = []
        case "trkseg":
            currentSegment = []
        case "trkpt", "rtept", "wpt":
            currentPointLat = Double(attributeDict["lat"]?.trimmingCharacters(in: .whitespaces) ?? "")
            currentPointLon = Double(attributeDict["lon"]?.trimmingCharacters(in: .whitespaces) ?? "")
            currentPointEle = nil
            currentPointTime = nil
            if name == "wpt" {
                currentWaypointName = nil
            }
        case "rte":
            currentRouteName = nil
            currentRoutePoints = []
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let name = Self.localName(elementName)
        defer {
            _ = elementStack.popLast()
            textBuffer = ""
        }

        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "name":
            assignName(text)
        case "ele":
            if isInsidePoint, let elevation = Double(text) {
                currentPointEle = elevation
            }
        case "time":
            if isInsidePoint {
                currentPointTime = parseTimestamp(text)
            }
        case "trkpt":
            appendCurrentPoint(to: &currentSegment)
        case "trkseg":
            if !currentSegment.isEmpty {
                trackSegments.append(currentSegment)
            }
            currentSegment = []
        case "trk":
            if !currentSegment.isEmpty {
                trackSegments.append(currentSegment)
            }
            if !trackSegments.isEmpty {
                tracks.append(ParsedGPXTrack(name: currentTrackName, segments: trackSegments))
            }
            currentTrackName = nil
            trackSegments = []
            currentSegment = []
        case "rtept":
            appendCurrentPoint(to: &currentRoutePoints)
        case "rte":
            if !currentRoutePoints.isEmpty {
                routes.append(ParsedGPXRoute(name: currentRouteName, points: currentRoutePoints))
            }
            currentRouteName = nil
            currentRoutePoints = []
        case "wpt":
            if let point = makeCurrentPoint() {
                waypoints.append(ParsedGPXWaypoint(name: currentWaypointName, point: point))
            } else {
                invalidPointCount += 1
            }
            currentWaypointName = nil
            resetCurrentPoint()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // XMLParser may deliver an element's text in several chunks.
        textBuffer += string
    }

    private var isInsidePoint: Bool {
        guard let parent = parentElement else { return false }
        return parent == "trkpt" || parent == "rtept" || parent == "wpt"
    }

    /// Only a `<name>` that is a direct child of metadata/trk/rte/wpt names that element.
    /// Author names (`metadata > author > name`) and route-point names (`rtept > name`)
    /// must not overwrite the route's own name.
    private func assignName(_ name: String) {
        guard !name.isEmpty, let parent = parentElement else { return }
        switch parent {
        case "metadata":
            metadataName = name
        case "trk":
            currentTrackName = name
        case "rte":
            currentRouteName = name
        case "wpt":
            currentWaypointName = name
        default:
            break
        }
    }

    private func parseTimestamp(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return timestampFormatter.date(from: text) ?? fractionalTimestampFormatter.date(from: text)
    }

    private func appendCurrentPoint(to array: inout [ParsedGPXPoint]) {
        if let point = makeCurrentPoint() {
            array.append(point)
        } else {
            invalidPointCount += 1
        }
        resetCurrentPoint()
    }

    private func makeCurrentPoint() -> ParsedGPXPoint? {
        guard let lat = currentPointLat,
              let lon = currentPointLon,
              MapMath.isValidCoordinate(latitude: lat, longitude: lon),
              // Devices write 0,0 for lost fixes; one such point wrecks bounds and distance.
              !(lat == 0 && lon == 0) else {
            return nil
        }
        return ParsedGPXPoint(
            latitude: lat,
            longitude: lon,
            elevationMeters: currentPointEle,
            timestamp: currentPointTime
        )
    }

    private func resetCurrentPoint() {
        currentPointLat = nil
        currentPointLon = nil
        currentPointEle = nil
        currentPointTime = nil
    }
}
