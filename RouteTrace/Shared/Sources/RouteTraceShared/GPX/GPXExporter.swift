import Foundation

public enum GPXExporter {
    public static func exportRoute(_ package: RoutePackage) -> String {
        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="RouteTrace">"#,
            "  <metadata>",
            "    <name>\(escape(package.name))</name>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(package.name))</name>",
            "    <trkseg>"
        ]

        for point in package.route {
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

    public static func exportActivity(_ activity: ActivityRecording, route: RoutePackage?) -> String {
        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="RouteTrace">"#,
            "  <metadata>",
            "    <name>\(escape(activity.displayTitle))</name>",
            "    <time>\(iso8601(activity.startedAt))</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(activity.displayTitle))</name>"
        ]

        let segments = TrackSegmentSplitter.continuousSegments(from: activity.trackPoints)
        for segment in segments {
            lines.append("    <trkseg>")
            for point in segment {
                lines.append("      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">")
                if let altitude = point.altitudeMeters {
                    lines.append("        <ele>\(altitude)</ele>")
                }
                lines.append("        <time>\(iso8601(point.timestamp))</time>")
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

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
