#!/usr/bin/env python3
"""Generate the Icon Composer app icons for the iOS and watchOS apps.

The icon is the Live Map reduced to its essentials: the recorded track (green)
leads into the position marker, and the route ahead continues as a dashed blue
line. The marker mirrors the Watch's UserHeadingMarker: white ring, blue dot,
heading wedge. Both AppIcon.icon bundles are written from the same geometry so
the iPhone and Watch icons stay in sync; the system adds the Liquid Glass
treatment and derives the Clear and Tinted appearances from the layers.

Preview a rendition with Icon Composer's command line tool, e.g.:

    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \\
        RouteTrace/iOSApp/AppIcon.icon --export-image --output-file AppIcon.png \\
        --platform iOS --rendition Dark --width 1024 --height 1024 --scale 1
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS_ICON = ROOT / "RouteTrace/iOSApp/AppIcon.icon"
WATCH_ICON = ROOT / "RouteTrace/WatchApp/AppIcon.icon"

CANVAS = 1024
MARKER = (512.0, 512.0)
# Cubic Béziers meeting at the marker in the icon centre.
TRACK = [(250.0, 1130.0), (300.0, 900.0), (400.0, 640.0), MARKER]
ROUTE = [MARKER, (610.0, 400.0), (770.0, 280.0), (1100.0, 120.0)]

TRACK_WIDTH = 136
ROUTE_WIDTH = 80
DASH_LENGTH = 124  # visible length, round caps included
DASH_GAP = 48
RING_RADIUS = 112
RING_WIDTH = 32
DOT_RADIUS = 62
WEDGE_LENGTH = 80
WEDGE_WIDTH = 96
WEDGE_CORNER = 10

Point = tuple[float, float]
Curve = list[Point]


class Palette:
    def __init__(self, route: str, track: str, wedge: str, fill_top: str, fill_bottom: str) -> None:
        self.route = route
        self.track = track
        self.wedge = wedge
        self.fill_top = fill_top
        self.fill_bottom = fill_bottom


# System blue and green, as used for the route and track in the app.
LIGHT = Palette(route="#007AFF", track="#34C759", wedge="#007AFF", fill_top="#FBFCFE", fill_bottom="#DFE6EF")
DARK = Palette(route="#0A84FF", track="#30D158", wedge="#FFFFFF", fill_top="#1E2838", fill_bottom="#07090E")


# MARK: - Geometry


def point_at(curve: Curve, t: float) -> Point:
    mt = 1 - t
    return (
        mt**3 * curve[0][0] + 3 * mt**2 * t * curve[1][0] + 3 * mt * t**2 * curve[2][0] + t**3 * curve[3][0],
        mt**3 * curve[0][1] + 3 * mt**2 * t * curve[1][1] + 3 * mt * t**2 * curve[2][1] + t**3 * curve[3][1],
    )


def split(curve: Curve, t: float) -> tuple[Curve, Curve]:
    def lerp(a: Point, b: Point) -> Point:
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    a, b, c = lerp(curve[0], curve[1]), lerp(curve[1], curve[2]), lerp(curve[2], curve[3])
    d, e = lerp(a, b), lerp(b, c)
    f = lerp(d, e)
    return [curve[0], a, d, f], [f, e, c, curve[3]]


def segment(curve: Curve, t0: float, t1: float) -> Curve:
    _, tail = split(curve, t0)
    head, _ = split(tail, (t1 - t0) / (1 - t0))
    return head


def t_at_distance(curve: Curve, distance: float, anchor: Point) -> float:
    """Parameter where the curve is `distance` away from `anchor` (one of its end points)."""
    from_start = anchor == curve[0]
    lo, hi = 0.0, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        x, y = point_at(curve, mid)
        farther = math.hypot(x - anchor[0], y - anchor[1]) > distance
        if from_start:
            lo, hi = (lo, mid) if farther else (mid, hi)
        else:
            lo, hi = (mid, hi) if farther else (lo, mid)
    return (lo + hi) / 2


def arc_length_table(curve: Curve, steps: int = 800) -> list[float]:
    lengths, previous = [0.0], point_at(curve, 0)
    for i in range(1, steps + 1):
        current = point_at(curve, i / steps)
        lengths.append(lengths[-1] + math.hypot(current[0] - previous[0], current[1] - previous[1]))
        previous = current
    return lengths


def t_at_length(table: list[float], length: float) -> float:
    steps = len(table) - 1
    for i in range(1, steps + 1):
        if table[i] >= length:
            span = table[i] - table[i - 1]
            return (i - 1 + (length - table[i - 1]) / span) / steps if span else i / steps
    return 1.0


def path_data(curve: Curve) -> str:
    x0, y0 = curve[0]
    (x1, y1), (x2, y2), (x3, y3) = curve[1:]
    return f"M{x0:.2f} {y0:.2f} C{x1:.2f} {y1:.2f} {x2:.2f} {y2:.2f} {x3:.2f} {y3:.2f}"


# MARK: - Layers


def svg(body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n'
    )


def ring_outer_radius() -> float:
    return RING_RADIUS + RING_WIDTH / 2


def track_layer(palette: Palette) -> str:
    # Butt end inside the ring band, so the gap between ring and dot stays clear.
    t = t_at_distance(TRACK, RING_RADIUS - 6, anchor=MARKER)
    visible, _ = split(TRACK, t)
    return svg(
        f'<path d="{path_data(visible)}" fill="none" stroke="{palette.track}" '
        f'stroke-width="{TRACK_WIDTH}" stroke-linecap="butt"/>'
    )


def route_layer(palette: Palette) -> str:
    # One sub-path per dash: Icon Composer draws hairlines across stroke-dasharray gaps.
    wedge_tip = ring_outer_radius() + 4 + WEDGE_LENGTH
    start = t_at_distance(ROUTE, wedge_tip + 26 + ROUTE_WIDTH / 2, anchor=MARKER)
    _, ahead = split(ROUTE, start)
    table = arc_length_table(ahead)
    dash = DASH_LENGTH - ROUTE_WIDTH
    dashes, offset = [], 0.0
    while offset < table[-1]:
        t0, t1 = t_at_length(table, offset), t_at_length(table, min(offset + dash, table[-1]))
        dashes.append(path_data(segment(ahead, t0, t1)))
        offset += DASH_LENGTH + DASH_GAP
    return svg(
        f'<path d="{" ".join(dashes)}" fill="none" stroke="{palette.route}" '
        f'stroke-width="{ROUTE_WIDTH}" stroke-linecap="round"/>'
    )


def ring_layer() -> str:
    x, y = MARKER
    return svg(f'<circle cx="{x:g}" cy="{y:g}" r="{RING_RADIUS}" fill="none" stroke="#FFFFFF" stroke-width="{RING_WIDTH}"/>')


def dot_layer(palette: Palette) -> str:
    x, y = MARKER
    return svg(f'<circle cx="{x:g}" cy="{y:g}" r="{DOT_RADIUS}" fill="{palette.route}"/>')


def wedge_layer(palette: Palette) -> str:
    """Rounded triangle just outside the ring, pointing along the route."""
    x, y = MARKER
    dx, dy = ROUTE[1][0] - x, ROUTE[1][1] - y
    heading = math.degrees(math.atan2(dx, -dy))
    base = ring_outer_radius() + 4
    tip = base + WEDGE_LENGTH
    r = WEDGE_CORNER
    half = WEDGE_WIDTH / 2 - r * 1.2
    corners = [(0.0, -(tip - r)), (-half, -(base + r)), (half, -(base + r))]
    d = "M" + " L".join(f"{cx:.2f} {cy:.2f}" for cx, cy in corners) + " Z"
    return svg(
        f'<g transform="translate({x:g} {y:g}) rotate({heading:.2f})">'
        f'<path d="{d}" fill="{palette.wedge}" stroke="{palette.wedge}" stroke-width="{2 * r}" '
        f'stroke-linejoin="round"/></g>'
    )


def layers(palette: Palette) -> dict[str, str]:
    return {
        "Dot.svg": dot_layer(palette),
        "Ring.svg": ring_layer(),
        "Wedge.svg": wedge_layer(palette),
        "Track.svg": track_layer(palette),
        "Route.svg": route_layer(palette),
    }


# MARK: - icon.json


def color(hex_value: str) -> str:
    h = hex_value.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def background(palette: Palette) -> dict:
    return {
        "linear-gradient": [color(palette.fill_top), color(palette.fill_bottom)],
        "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}},
    }


def layer(name: str, dark: str | None = None) -> dict:
    entry: dict = {"glass": True, "image-name": f"{name}.svg", "name": name}
    if dark:
        entry["fill-specializations"] = [{"appearance": "dark", "value": {"solid": color(dark)}}]
    return entry


def group(name: str, members: list[dict]) -> dict:
    return {
        "layers": members,
        "name": name,
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": False, "value": 0.5},
    }


def icon_document(platform: str) -> dict:
    if platform == "iOS":
        # Light by default; the dark appearance swaps in the Watch palette.
        return {
            "fill-specializations": [{"value": background(LIGHT)}, {"appearance": "dark", "value": background(DARK)}],
            "groups": [
                group("Marker", [layer("Dot", DARK.route), layer("Ring"), layer("Wedge", DARK.wedge)]),
                group("Route", [layer("Track", DARK.track), layer("Route", DARK.route)]),
            ],
            "supported-platforms": {"squares": ["iOS"]},
        }
    return {
        "fill": background(DARK),
        "groups": [
            group("Marker", [layer("Dot"), layer("Ring"), layer("Wedge")]),
            group("Route", [layer("Track"), layer("Route")]),
        ],
        "supported-platforms": {"circles": ["watchOS"]},
    }


def write_icon(bundle: Path, platform: str, palette: Palette) -> None:
    if bundle.exists():
        shutil.rmtree(bundle)
    assets = bundle / "Assets"
    assets.mkdir(parents=True)
    for name, content in layers(palette).items():
        (assets / name).write_text(content)
    document = json.dumps(icon_document(platform), indent=2, separators=(",", " : "), sort_keys=True)
    (bundle / "icon.json").write_text(document + "\n")
    print(f"Wrote {bundle.relative_to(ROOT)}")


def main() -> int:
    write_icon(IOS_ICON, "iOS", LIGHT)
    write_icon(WATCH_ICON, "watchOS", DARK)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
