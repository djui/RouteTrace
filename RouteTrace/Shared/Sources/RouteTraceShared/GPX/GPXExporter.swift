import Foundation

public enum GPXExporter {
    private static let header = #"<?xml version="1.0" encoding="UTF-8"?>"#
    private static let gpxOpenTag = #"<gpx version="1.1" creator="RouteTrace" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">"#

    public static func exportTrack(name: String, points: [ParsedGPXPoint]) -> String {
        var lines: [String] = [
            header,
            gpxOpenTag,
            "  <metadata>",
            "    <name>\(escape(name))</name>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(name))</name>",
            "    <trkseg>"
        ]
        lines.reserveCapacity(lines.count + points.count * 3 + 3)

        for point in points {
            lines.append("      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">")
            if let elevation = point.elevationMeters {
                lines.append("        <ele>\(elevation)</ele>")
            }
            lines.append("      </trkpt>")
        }

        lines += [
            "    </trkseg>",
            "  </trk>",
            "</gpx>"
        ]

        return lines.joined(separator: "\n")
    }

    public static func writeTrack(name: String, points: [ParsedGPXPoint], to url: URL) throws {
        let gpx = exportTrack(name: name, points: points)
        try gpx.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func exportRoute(_ package: RoutePackage) -> String {
        exportTrack(
            name: package.name,
            points: package.route.map {
                ParsedGPXPoint(
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    elevationMeters: $0.elevationMeters,
                    timestamp: nil
                )
            }
        )
    }

    public static func exportActivity(_ activity: ActivityRecording, route: RoutePackage?) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            header,
            gpxOpenTag,
            "  <metadata>",
            "    <name>\(escape(activity.displayTitle))</name>",
            "    <time>\(formatter.string(from: activity.startedAt))</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(activity.displayTitle))</name>",
            "    <type>\(activity.activityKind.gpxTypeName)</type>"
        ]

        let segments = TrackSegmentSplitter.continuousSegments(from: activity.trackPoints)
        for segment in segments {
            lines.append("    <trkseg>")
            for point in segment {
                lines.append("      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">")
                if let altitude = point.altitudeMeters {
                    lines.append("        <ele>\(altitude)</ele>")
                }
                lines.append("        <time>\(formatter.string(from: point.timestamp))</time>")
                if let heartRate = point.heartRateBPM, heartRate > 0 {
                    lines.append("        <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(Int(heartRate.rounded()))</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>")
                }
                lines.append("      </trkpt>")
            }
            lines.append("    </trkseg>")
        }

        lines += [
            "  </trk>",
            "</gpx>"
        ]

        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

extension ActivityKind {
    /// Activity type names understood by Strava, Garmin Connect and most GPX importers.
    var gpxTypeName: String {
        switch self {
        case .running: "running"
        case .trailRunning: "trail_running"
        case .roadCycling: "cycling"
        case .gravelCycling: "gravel_cycling"
        }
    }
}
