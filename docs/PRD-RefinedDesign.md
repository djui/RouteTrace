Below is a copy-paste implementation brief for another coding tool.

---

# Apple Watch Route Companion — Refined Concept 1: Map-first Carousel

Implement a dark, map-first Apple Watch route companion app for following a GPX route during running, hiking, or cycling.

The visual style should be based on **Concept 1**, but remove the persistent bottom toolbar/dock entirely. Replace it with a lightweight horizontal carousel using **page dots**. The app should feel native to watchOS: low chrome, glanceable, high contrast, and optimized for quick wrist interactions.

Confidence: **0.91**

---

## 1. Core design direction

Build the watch app as a **five-page horizontal carousel**.

The five views are:

1. **Route Map**
2. **Follow Route**
3. **Live Map**
4. **Altitude**
5. **Metrics**

The user switches between views by swiping horizontally. Each view shows a small row of page dots near the bottom center. The active page dot is highlighted.

Do **not** use a bottom tab bar, toolbar, icon dock, or persistent segmented control. The carousel should feel like swiping through lightweight cards/screens, not navigating tabs.

---

## 2. Navigation model

### Default mode: Browse Mode

Browse Mode is the normal state of the app.

Behavior:

```text
Swipe left/right = move between the five views
Page dots = show current page position
Digital Crown = does not switch pages by default

```

The Digital Crown should not duplicate horizontal swiping. This avoids confusion because the Crown is needed for zooming maps and scrolling/scrubbing content.

### Map Focus Mode

Map pages can become interactive, but only after the user explicitly enters Map Focus Mode.

Map Focus Mode applies to:

```text
Route Map
Live Map

```

Entry behavior:

```text
Tap the map, or tap a small target/focus button on the map

```

Focused behavior:

```text
Drag = pan map
Digital Crown = zoom in/out
Tap Done = exit Map Focus Mode

```

When Map Focus Mode is active, disable horizontal page swiping until the user exits. This prevents conflicts between swiping to change views and dragging the map.

---

## 3. Shared screen chrome

Every screen should use the same shared chrome.

### Top-left

Use a circular floating back button.

```text
Position: top-left
Style: translucent black material circle
Icon: chevron.left
Size: about 40–44 px watch-equivalent tap target

```

### Top-right

Show compact activity/time status.

```text
Small green running icon
Current time

```

Example:

```text
🏃 14:49

```

Use SF Symbols where possible:

```text
figure.run

```

### Bottom-center

Show horizontal page dots.

```text
Five dots total
One active dot
Inactive dots: low-opacity gray
Active dot: white, blue, or green depending on view

```

Suggested active colors:

```text
Route Map: blue or white
Follow Route: green
Live Map: blue
Altitude: blue
Metrics: white

```

The page dots should be subtle. They should not look like tappable tabs.

---

## 4. Global visual style

Use a dark watchOS-native visual language.

### Colors

```text
Background: #000000 or near-black
Map route blue: vivid system blue
Success/on-route green: system green
Text primary: white
Text secondary: soft gray
Cards/overlays: translucent black with material blur
Separators: low-opacity white
Warning/orange only for off-route states

```

### Typography

Use watchOS system font.

Suggested hierarchy:

```text
Primary value: large, semibold
Section title: medium, semibold
Labels: small, gray
Status text: medium, regular/semibold

```

Avoid long paragraphs. Each screen should be understandable in under one second.

### Layout principles

```text
Content first
Minimal controls
Large touch targets
No persistent tab/dock
No crowded header
Use rounded cards only when they clarify information
Avoid decorative UI

```

---

# 5. Screen-by-screen implementation

---

## Screen 1 — Route Map

Purpose: show the full route overview, especially when offline tiles are missing or unavailable.

### Layout

```text
Full-screen dark map background
Blue GPX route polyline centered and fitted to view
Floating back button top-left
Activity/time top-right
Offline status pill lower-left or lower-middle
Optional small Map Focus target button near lower-right
Page dots bottom-center

```

### Content

Show:

```text
Blue route outline
Offline status pill
Current page dots

```

Offline pill examples:

```text
Offline
Route only

```

or:

```text
No offline tiles
Showing route only

```

Keep the offline message short. Do not cover too much of the route.

### Interaction

```text
Tap map or target icon = enter Map Focus Mode
In Map Focus Mode:
  drag = pan
  Digital Crown = zoom
  Done button = exit

```

### Implementation note

In Browse Mode, the map should not intercept horizontal swipes. Let horizontal swipe navigate between carousel pages.

---

## Screen 2 — Follow Route

Purpose: give a quick status confirmation: “Am I on route?”

### Layout

```text
Black background
Back button top-left
Activity/time top-right
Large centered status icon
Primary message
Small secondary message
Divider
Two metric columns
Page dots bottom-center

```

### Normal/on-route state

```text
Large green checkmark circle
Title: On Route
Subtitle: You’re on track.

```

Metrics:

```text
Remaining: 14.3 km
Elapsed: 0:13:26

```

### Off-route state

Use a warning style only when needed.

```text
Large orange warning icon
Title: Off Route
Subtitle: Return to the blue route.

```

Possible metrics:

```text
Distance from route: 42 m
Elapsed: 0:13:26

```

### Interaction

No map interaction here.

Digital Crown may do nothing, or optionally scroll if the screen becomes vertically longer in future versions.

---

## Screen 3 — Live Map

Purpose: show live position and route progress.

### Layout

```text
Dark map background
Blue route polyline
Green current-position dot
Optional heading arrow
Back button top-left
Activity/time top-right
Two bottom metric cards
Page dots bottom-center

```

### Content

Map:

```text
Blue route line
Green current position dot
Optional location label
Optional heading triangle

```

Bottom cards:

```text
Progress: 2.7 km
Remaining: 11.6 km

```

Cards should be translucent black with rounded corners.

### Interaction

```text
Tap map = enter Map Focus Mode
In Map Focus Mode:
  drag = pan
  Digital Crown = zoom
  Done = exit

```

In Browse Mode, keep the live map mostly passive.

---

## Screen 4 — Altitude

Purpose: show elevation profile and current altitude context.

### Layout

```text
Black background
Back button top-left
Activity/time top-right
Title: Altitude
Elevation line chart
Optional current-position marker on chart
Two bottom metrics
Page dots bottom-center

```

### Content

Chart:

```text
Blue elevation line
Subtle grid or dotted baseline
Optional highlighted point for current route position

```

Metrics:

```text
Gain: 323 m
Current: 810 m

```

### Digital Crown behavior

Preferred:

```text
Digital Crown scrubs along altitude profile

```

When the user rotates the Crown:

```text
Move current-position marker along the elevation chart
Show distance/elevation at selected point
After timeout, return marker to current live position

```

Simpler MVP behavior:

```text
Digital Crown does nothing on this view

```

Do not use the Crown to switch pages here.

---

## Screen 5 — Metrics

Purpose: show detailed stats in a compact vertical list.

### Layout

```text
Black background
Back button top-left
Activity/time top-right
Vertically stacked metric rows
Optional scroll indicator on right
Page dots bottom-center

```

### Metric rows

Use simple SF Symbols and two-level text.

Example rows:

```text
Remaining
14.3 km

Speed
16.1 km/h

Elevation Gain
4 m

Heart Rate
63 bpm

Off Route Events
1

```

Suggested icons:

```text
Remaining: arrow.right
Speed: speedometer
Elevation Gain: arrow.up.right
Heart Rate: heart.fill
Off Route Events: location.slash or exclamationmark.triangle

```

### Digital Crown behavior

On this screen, the Digital Crown should scroll the list if the content exceeds the visible area.

---

# 6. Carousel behavior

Use a paged horizontal container.

Conceptually:

```swift
TabView(selection: $selectedPage) {
    RouteMapView()
        .tag(0)

    FollowRouteView()
        .tag(1)

    LiveMapView()
        .tag(2)

    AltitudeView()
        .tag(3)

    MetricsView()
        .tag(4)
}
.tabViewStyle(.page(indexDisplayMode: .never))

```

Render custom page dots instead of the system page indicator.

Pseudo-structure:

```swift
ZStack {
    currentPageContent

    VStack {
        Spacer()
        PageDots(
            count: 5,
            selectedIndex: selectedPage
        )
        .padding(.bottom, 10)
    }
}

```

When `mapFocusMode == true`, disable carousel paging gestures if possible, or ensure map gestures take priority.

---

# 7. Map Focus Mode

Map Focus Mode should feel like a temporary focused interaction state.

### Entering focus

User taps:

```text
Map surface
or small target icon

```

Then show:

```text
Done button
Optional “Map Focus” label
Optional zoom indicator

```

### In focus

```text
Drag = pan
Digital Crown = zoom
Horizontal carousel swipe disabled

```

### Exiting focus

User taps:

```text
Done

```

Then return to Browse Mode.

### Focus UI

In focus mode, add a small top-right or bottom-right button:

```text
Done

```

Use blue text or a small rounded translucent button.

Avoid showing multiple map controls. Keep it light.

---

# 8. State model

Suggested state:

```swift
enum RoutePage: Int, CaseIterable {
    case routeMap
    case followRoute
    case liveMap
    case altitude
    case metrics
}

enum InteractionMode {
    case browse
    case mapFocus
}

struct RouteProgressState {
    var routeName: String
    var activityType: ActivityType
    var isOfflineReady: Bool
    var hasOfflineTiles: Bool
    var isOnRoute: Bool
    var remainingDistance: Measurement<UnitLength>
    var elapsedTime: TimeInterval
    var progressDistance: Measurement<UnitLength>
    var currentSpeed: Measurement<UnitSpeed>
    var elevationGain: Measurement<UnitLength>
    var currentAltitude: Measurement<UnitLength>
    var heartRate: Int?
    var offRouteEvents: Int
}

```

Key behavior:

```text
selectedPage controls the carousel
interactionMode controls whether maps are passive or interactive
Digital Crown behavior depends on selectedPage + interactionMode

```

---

# 9. Digital Crown behavior rules

Use this logic:

```text
If interactionMode == mapFocus:
    Digital Crown zooms map

Else if selectedPage == metrics:
    Digital Crown scrolls metric list

Else if selectedPage == altitude:
    Digital Crown optionally scrubs altitude profile

Else:
    Digital Crown does nothing

```

Do not use Digital Crown for horizontal page navigation in this refined concept.

---

# 10. Visual implementation details

### Floating controls

Back button:

```text
Shape: circle
Background: black material / translucent dark
Icon: white chevron

```

Offline pill:

```text
Shape: capsule
Background: black translucent
Icon: offline/cloud/map icon
Text: white

```

Metric cards:

```text
Shape: rounded rectangle
Background: black translucent
Border: subtle white opacity

```

Page dots:

```text
Dot size: 5–6 px
Spacing: 6–8 px
Inactive opacity: 0.25–0.35
Active opacity: 1.0

```

### Map style

```text
Dark map
Subtle roads/terrain
Blue route line
Green current location dot
Avoid heavy labels

```

### Animation

Use lightweight transitions:

```text
Horizontal page swipe: native smooth paging
Page dot transition: fade/scale active dot
Map Focus entry: subtle fade-in of Done button
Status changes: soft opacity/scale transition

```

---

# 11. What to remove from the previous concept

Remove these:

```text
Persistent bottom icon dock
Persistent top segmented control
Five visible navigation icons
Toolbar-like glass tab bar
Duplicate Crown navigation
Large decorative controls

```

Keep these:

```text
Dark map-first style
Blue route line
Green success state
Floating circular back button
Compact overlays
Five core views
Map Focus mode

```

---

# 12. Final desired feel

The app should feel like this:

```text
A dark, focused Apple Watch route companion.
The route and current state are always the hero.
Navigation is lightweight horizontal paging.
The map becomes interactive only when explicitly focused.
No persistent toolbar competes with the content.
Every view is glanceable while running.

```


| Area                      | Decision                                           | Confidence |
| ------------------------- | -------------------------------------------------- | ---------- |
| Navigation                | Horizontal swipe carousel with page dots           | 0.92       |
| Digital Crown             | Reserved for zoom/scroll/scrub, not page switching | 0.89       |
| Map interaction           | Explicit Map Focus Mode                            | 0.91       |
| Visual style              | Concept 1 dark map-first style, minus dock         | 0.94       |
| Implementation complexity | Moderate, mostly state/gesture separation          | 0.82       |


