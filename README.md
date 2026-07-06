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

## TestFlight

Release builds archive the **RouteTrace** scheme (iOS app with embedded Watch app and widget extension) and upload to TestFlight via [Fastlane](https://fastlane.tools).

### Prerequisites (one-time)

1. Create an app record in [App Store Connect](https://appstoreconnect.apple.com) for bundle ID `com.uwe.RouteTrace`.
2. In the [Apple Developer portal](https://developer.apple.com/account), enable these capabilities on the App IDs:
   - HealthKit
   - iCloud (CloudKit)
   - App Groups (`group.com.uwe.RouteTrace`)
3. Create an [App Store Connect API key](https://appstoreconnect.apple.com/access/integrations/api) with **Admin** or **App Manager** role.
4. Add these GitHub repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|--------|-------|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from App Store Connect |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from App Store Connect |
| `APP_STORE_CONNECT_API_KEY` | Base64-encoded `.p8` key file (`base64 -i AuthKey_XXXX.p8 \| pbcopy`) |

The first TestFlight upload may prompt for export compliance and privacy answers in App Store Connect. HealthKit and background location usage may require additional review context.

### CI (GitHub Actions)

The [TestFlight workflow](.github/workflows/testflight.yml) runs on:

- **Manual trigger** — Actions → TestFlight → Run workflow (optional build number override)
- **Version tags** — pushing a tag like `v0.1.0` triggers an upload

### Local build and upload

Requires Xcode 26 on macOS:

```bash
bundle install

# Export an App Store IPA without uploading
bundle exec fastlane build

# Build and upload to TestFlight (requires API key env vars)
export APP_STORE_CONNECT_API_KEY_ID="..."
export APP_STORE_CONNECT_ISSUER_ID="..."
export APP_STORE_CONNECT_API_KEY="$(base64 -i AuthKey_XXXX.p8)"
bundle exec fastlane beta
```

Optional: set `BUILD_NUMBER` to override the auto-incremented build number.
