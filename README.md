# RouteTrace

GPX route navigation for iPhone and Apple Watch.

## Requirements

- Xcode 26 (iOS 26 / watchOS 26 SDKs)
- iPhone simulator or device for the iOS app
- Paired Apple Watch simulator or device for full Watch connectivity testing

## Project layout

```
WatchMap/
├── Package.swift                 # RouteTraceShared Swift package
├── RouteTrace.xcodeproj/         # Canonical Xcode project
├── RouteTrace/
│   ├── Shared/Sources/RouteTraceShared/
│   ├── iOSApp/Sources/RouteTrace/
│   ├── WatchApp/Sources/RouteTraceWatch/
│   └── Tests/
└── Scripts/generate_xcodeproj.py
```

## Targets

| Target | Platform | Bundle ID |
|--------|----------|-----------|
| **RouteTrace** | iOS 26 | `com.uwe.RouteTrace` |
| **RouteTraceWatch** | watchOS 26 | `com.uwe.RouteTrace.watchkitapp` |
| **RouteTraceTests** | iOS 26 (unit tests) | `com.uwe.RouteTraceTests` |

The iPhone app embeds the Watch app. Shared logic lives in the local Swift package `RouteTraceShared` (from `Package.swift`) and is linked by all three targets.

## Build (command line)

From the repository root:

```bash
# Regenerate project.pbxproj after adding/removing source files
python3 Scripts/generate_xcodeproj.py

# Build iOS app (also builds embedded Watch app)
xcodebuild -scheme RouteTrace \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

If `iPhone 16` is not installed locally, list simulators with `xcrun simctl list devices available` and substitute (e.g. `iPhone 17` on Xcode 26).

```bash
# Run unit tests
xcodebuild -scheme RouteTrace \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

## Build (Xcode)

1. Open `RouteTrace.xcodeproj`.
2. Select the **RouteTrace** scheme.
3. Choose an iPhone simulator (e.g. iPhone 16 or iPhone 17).
4. Press **Run** (⌘R).

For Watch-only iteration, use the **RouteTraceWatch** scheme with a watchOS simulator.

## Capabilities

Both apps declare:

- **HealthKit** — workout recording and heart-rate during navigation
- **App Groups** — `group.com.uwe.RouteTrace`
- **Location** — route preview (iOS) and live navigation (Watch)

Set your development team under **Signing & Capabilities** for device builds. Simulator builds use automatic signing without a team in most setups.

## Shared package tests

You can also run shared-module tests via Swift Package Manager:

```bash
swift test
```
