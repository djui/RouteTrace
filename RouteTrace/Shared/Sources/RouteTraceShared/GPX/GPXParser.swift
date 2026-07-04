import Foundation

public struct ParsedGPXPoint: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let elevationMeters: Double?
    public let timestamp: Date?
}

public struct ParsedGPXTrack: Sendable {
    public let name: String?
    public let segments: [[ParsedGPXPoint]]
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

    public var primaryTrackPoints: [ParsedGPXPoint] {
        if let longest = tracks.flatMap(\.segments).max(by: { $0.count < $1.count }), !longest.isEmpty {
            return longest
        }
        return routes.max(by: { $0.points.count < $1.points.count })?.points ?? []
    }

    public var usablePointCount: Int {
        primaryTrackPoints.count
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
    private var pendingName: String?

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

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        pendingName = nil

        switch elementName {
        case "trk":
            currentTrackName = nil
            trackSegments = []
            currentSegment = []
        case "trkseg":
            currentSegment = []
        case "trkpt", "rtept", "wpt":
            currentPointLat = Double(attributeDict["lat"] ?? "")
            currentPointLon = Double(attributeDict["lon"] ?? "")
            currentPointEle = nil
            currentPointTime = nil
            if elementName == "wpt" {
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
        defer { _ = elementStack.popLast() }

        switch elementName {
        case "name":
            assignPendingName()
        case "ele":
            break
        case "time":
            break
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
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let current = elementStack.last else { return }

        switch current {
        case "name":
            pendingName = (pendingName ?? "") + trimmed
        case "ele":
            currentPointEle = Double(trimmed)
        case "time":
            currentPointTime = ISO8601DateFormatter().date(from: trimmed)
        default:
            break
        }
    }

    private func assignPendingName() {
        guard let name = pendingName, !name.isEmpty else { return }
        if elementStack.contains("metadata") {
            metadataName = name
        } else if elementStack.contains("trk") {
            currentTrackName = name
        } else if elementStack.contains("rte") {
            currentRouteName = name
        } else if elementStack.contains("wpt") {
            currentWaypointName = name
        }
        pendingName = nil
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
              MapMath.isValidCoordinate(latitude: lat, longitude: lon) else {
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
