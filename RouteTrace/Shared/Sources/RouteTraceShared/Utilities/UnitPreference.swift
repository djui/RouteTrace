import Foundation
import Observation

/// The unit setting a person picks: follow the region, or force metric or imperial.
public enum UnitSystem: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic
    case metric
    case imperial

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }
}

/// The units screens actually use once `automatic` is resolved against the region.
public struct DisplayUnits: Equatable, Sendable {
    public enum Distance: Sendable { case kilometers, miles }
    public enum Elevation: Sendable { case meters, feet }

    public var distance: Distance
    public var elevation: Elevation

    public static let metric = DisplayUnits(distance: .kilometers, elevation: .meters)
    public static let imperial = DisplayUnits(distance: .miles, elevation: .feet)

    public static let metersPerMile = 1609.344
    public static let metersPerFoot = 0.3048

    public init(distance: Distance, elevation: Elevation) {
        self.distance = distance
        self.elevation = elevation
    }

    /// `automatic` follows local conventions: miles and feet in the US; miles for distance but
    /// metres for heights in the UK, as on its road signs and Ordnance Survey maps; metric elsewhere.
    public init(system: UnitSystem, locale: Locale = .current) {
        switch system {
        case .metric:
            self = .metric
        case .imperial:
            self = .imperial
        case .automatic:
            switch locale.measurementSystem {
            case .us: self = .imperial
            case .uk: self = DisplayUnits(distance: .miles, elevation: .meters)
            default: self = .metric
            }
        }
    }

    /// Meters in one unit of `distance` (a kilometre or a mile).
    public var metersPerDistanceUnit: Double {
        distance == .miles ? Self.metersPerMile : 1000
    }

    /// Meters in one unit of `elevation` (a metre or a foot).
    public var metersPerElevationUnit: Double {
        elevation == .feet ? Self.metersPerFoot : 1
    }
}

/// The unit setting shared by every screen of an app and its widgets.
///
/// Reading `system` or `units` inside a SwiftUI body, directly or through `RouteFormatting`,
/// re-renders that view when the setting changes. The value is stored in the app group so a
/// widget extension reads the same setting; call `reload()` there before rendering.
public final class UnitPreference: Observable, @unchecked Sendable {
    public static let shared = UnitPreference(
        defaults: UserDefaults(suiteName: WatchAppConstants.appGroupIdentifier) ?? .standard
    )

    static let storageKey = "units.system"

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private let defaults: UserDefaults
    private var storedSystem: UnitSystem

    init(defaults: UserDefaults) {
        self.defaults = defaults
        storedSystem = Self.load(from: defaults)
    }

    public var system: UnitSystem {
        get {
            registrar.access(self, keyPath: \.system)
            return lock.withLock { storedSystem }
        }
        set {
            guard newValue != lock.withLock({ storedSystem }) else { return }
            registrar.withMutation(of: self, keyPath: \.system) {
                lock.withLock { storedSystem = newValue }
            }
            defaults.set(newValue.rawValue, forKey: Self.storageKey)
        }
    }

    public var units: DisplayUnits {
        DisplayUnits(system: system)
    }

    /// Picks up a change another process (the app, for a widget) saved to the app group.
    public func reload() {
        system = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> UnitSystem {
        defaults.string(forKey: storageKey).flatMap(UnitSystem.init(rawValue:)) ?? .automatic
    }
}
