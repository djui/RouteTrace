import Foundation

public enum ActivityNaming {
    public static func title(
        startedAt: Date,
        activityKind: ActivityKind,
        routeName: String,
        calendar: Calendar = .current
    ) -> String {
        let timePhrase = timeOfDayPhrase(for: startedAt, calendar: calendar)
        let activity = activityKind.informalName
        return "\(timePhrase) \(activity) (\(routeName))"
    }

    public static func timeOfDayPhrase(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<7:
            return "Early morning"
        case 7..<11:
            return "Morning"
        case 11..<13:
            return "Midday"
        case 13..<17:
            return "Afternoon"
        case 17..<20:
            return "Late afternoon"
        case 20..<22:
            return "Evening"
        default:
            return "Night"
        }
    }
}
