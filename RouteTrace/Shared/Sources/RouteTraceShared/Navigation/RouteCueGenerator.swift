import Foundation

public struct RouteCueGenerator {
    public let minimumCueSpacingMeters: Double

    public init(minimumCueSpacingMeters: Double = 40) {
        self.minimumCueSpacingMeters = minimumCueSpacingMeters
    }

    public func generate(route: [RoutePoint]) -> [RouteCue] {
        guard route.count >= 2 else { return [] }

        var cues: [RouteCue] = []
        if let first = route.first, let bearing = first.bearingDegrees {
            cues.append(makeCue(
                at: first,
                kind: .start,
                instruction: "Start route",
                bearingBefore: bearing,
                bearingAfter: bearing
            ))
        }

        var lastCueDistance = -minimumCueSpacingMeters

        for index in 1..<(route.count - 1) {
            guard let before = route[index - 1].bearingDegrees,
                  let after = route[index].bearingDegrees else { continue }

            let delta = MapMath.bearingDelta(from: before, to: after)
            let absDelta = abs(delta)
            let point = route[index]

            guard absDelta >= 20 else { continue }
            guard point.distanceFromStartMeters - lastCueDistance >= minimumCueSpacingMeters else { continue }

            let kind = classifyCue(delta: delta)
            let instruction = instructionText(for: kind, distanceMeters: point.distanceFromStartMeters)
            cues.append(makeCue(
                at: point,
                kind: kind,
                instruction: instruction,
                bearingBefore: before,
                bearingAfter: after
            ))
            lastCueDistance = point.distanceFromStartMeters
        }

        if let last = route.last, let before = route.dropLast().last?.bearingDegrees {
            cues.append(makeCue(
                at: last,
                kind: .finish,
                instruction: "Finish",
                bearingBefore: before,
                bearingAfter: before
            ))
        }

        return cues
    }

    private func classifyCue(delta: Double) -> RouteCueKind {
        let absDelta = abs(delta)
        let isLeft = delta < 0

        switch absDelta {
        case 140...:
            return .uTurn
        case 80..<140:
            return isLeft ? .sharpLeft : .sharpRight
        case 40..<80:
            return isLeft ? .turnLeft : .turnRight
        case 20..<40:
            return isLeft ? .slightLeft : .slightRight
        default:
            return .continue
        }
    }

    private func instructionText(for kind: RouteCueKind, distanceMeters: Double) -> String {
        switch kind {
        case .start: "Start route"
        case .finish: "Finish"
        case .continue: "Continue"
        case .slightLeft: "Slight left"
        case .slightRight: "Slight right"
        case .turnLeft: "Turn left"
        case .turnRight: "Turn right"
        case .sharpLeft: "Sharp left"
        case .sharpRight: "Sharp right"
        case .uTurn: "U-turn"
        }
    }

    private func makeCue(
        at point: RoutePoint,
        kind: RouteCueKind,
        instruction: String,
        bearingBefore: Double,
        bearingAfter: Double
    ) -> RouteCue {
        RouteCue(
            id: UUID(),
            distanceFromStartMeters: point.distanceFromStartMeters,
            coordinate: point.coordinate,
            kind: kind,
            instruction: instruction,
            bearingBefore: bearingBefore,
            bearingAfter: bearingAfter
        )
    }
}
