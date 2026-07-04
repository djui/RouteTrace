# PRD: GPX Route Navigator for Apple Watch + iPhone

**Working name:** RouteTrace  
**Target platforms:** iOS 26.0+ companion app, watchOS 26.0+ Apple Watch app  
**Primary use case:** Load a GPX route on iPhone, transfer it to Apple Watch, then run or ride with a real map view showing planned route, current position, completed track, off-route warnings, route overview, directions mode, and altitude profile.

See the full PRD in the project plan at `.cursor/plans/routetrace_gpx_navigator_89b4a79d.plan.md` and the original conversation for complete specifications including user stories, UX, data models, acceptance criteria, and implementation tasks 1–15.

## Key decisions

| Area | Decision |
|------|----------|
| Primary device | Apple Watch |
| Companion device | iPhone |
| Minimum OS | iOS 26 + watchOS 26 only |
| Online map | MapKit for SwiftUI |
| Offline map | MapKit snapshot corridor pack (iPhone builds, Watch renders) |
| GPX transfer | WatchConnectivity file transfer |
| Workout recording | HealthKit + workout route builder |
| Battery saver | Directions mode with reduced map redraw |
