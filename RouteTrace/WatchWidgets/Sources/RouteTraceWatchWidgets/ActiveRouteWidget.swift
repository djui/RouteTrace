import RouteTraceShared
import SwiftUI
import WidgetKit

struct ActiveRouteTimelineEntry: TimelineEntry {
    let date: Date
    let payload: WatchActivityWidgetPayload?
}

struct ActiveRouteTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveRouteTimelineEntry {
        ActiveRouteTimelineEntry(
            date: Date(),
            payload: WatchActivityWidgetPayload(
                routeName: "Morning Loop",
                progressFraction: 0.42,
                distanceRemainingMeters: 4200,
                elapsedSeconds: 1800,
                isPaused: false,
                isOffRoute: false,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveRouteTimelineEntry) -> Void) {
        completion(
            ActiveRouteTimelineEntry(
                date: Date(),
                payload: WatchWidgetStateWriter.readWidgetPayload()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveRouteTimelineEntry>) -> Void) {
        let payload = WatchWidgetStateWriter.readWidgetPayload()
        let entry = ActiveRouteTimelineEntry(date: Date(), payload: payload)
        let refresh = payload == nil ? Date().addingTimeInterval(900) : Date().addingTimeInterval(30)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct ActiveRouteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActiveRouteTimelineEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularView
            case .accessoryCorner:
                cornerView
            case .accessoryInline:
                inlineView
            default:
                rectangularView
            }
        }
        .widgetURL(URL(string: "routetrace://active"))
    }

    private var rectangularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(alignment: .leading, spacing: 2) {
                if let payload = entry.payload {
                    HStack {
                        Text(payload.routeName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if payload.isPaused {
                            Image(systemName: "pause.fill")
                        } else if payload.isOffRoute {
                            Image(systemName: "location.slash")
                        }
                    }
                    ProgressView(value: payload.progressFraction)
                    HStack {
                        Text(RouteFormatting.distance(payload.distanceRemainingMeters))
                        Spacer()
                        Text(RouteFormatting.duration(payload.elapsedSeconds))
                    }
                    .font(.caption2)
                } else {
                    Text("No active route")
                        .font(.caption)
                }
            }
        }
    }

    private var cornerView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let payload = entry.payload {
                Gauge(value: payload.progressFraction) {
                    Image(systemName: payload.isPaused ? "pause" : "figure.run")
                }
                .gaugeStyle(.accessoryCircular)
                .widgetLabel {
                    Text("\(Int(payload.progressFraction * 100))%")
                }
            } else {
                Image(systemName: "map")
                    .widgetLabel {
                        Text("Route")
                    }
            }
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let payload = entry.payload {
                Gauge(value: payload.progressFraction) {
                    Image(systemName: payload.isPaused ? "pause" : "figure.run")
                } currentValueLabel: {
                    Text("\(Int(payload.progressFraction * 100))")
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                Image(systemName: "map")
            }
        }
    }

    private var inlineView: some View {
        if let payload = entry.payload {
            Text("\(payload.routeName) · \(Int(payload.progressFraction * 100))% · \(RouteFormatting.distance(payload.distanceRemainingMeters)) left")
        } else {
            Text("RouteTrace idle")
        }
    }
}

@main
struct ActiveRouteWidget: Widget {
    let kind: String = WatchAppConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveRouteTimelineProvider()) { entry in
            ActiveRouteWidgetView(entry: entry)
        }
        .configurationDisplayName("Route Progress")
        .description("Shows progress for your active route.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}
