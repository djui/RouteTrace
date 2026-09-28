#!/usr/bin/env python3
"""Generate the Icon Composer app icons for the iOS and watchOS apps.

The icon is a loop route, halfway round: the recorded track (green) runs up the
left side into the position marker at the top, and the route ahead (blue)
continues down the right side, as on the Live Map. The marker matches the
Watch's UserHeadingMarker: white ring, blue dot and white heading wedge, in the
same proportions. Both AppIcon.icon bundles are written from the same geometry
so the iPhone and Watch icons stay in sync; the system adds the Liquid Glass
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
# The loop is travelled clockwise from the bottom; the marker sits at the top.
LOOP_CENTER = (512.0, 548.0)
LOOP_RADIUS = 300.0
LINE_WIDTH = 100
MARKER_SIZE = 250  # ring diameter, like UserHeadingMarker's `size`
ROUTE_GAP = 34  # space between the wedge tip and the route ahead


class Palette:
    def __init__(self, route: str, track: str, fill_top: str, fill_bottom: str) -> None:
        self.route = route
        self.track = track
        self.fill_top = fill_top
        self.fill_bottom = fill_bottom


# System blue and green, as used for the route and track in the app.
LIGHT = Palette(route="#007AFF", track="#34C759", fill_top="#F4F7FA", fill_bottom="#D6DEE8")
DARK = Palette(route="#0A84FF", track="#30D158", fill_top="#1E2838", fill_bottom="#07090E")


# MARK: - Geometry


def point(angle: float, radius: float = LOOP_RADIUS) -> tuple[float, float]:
    cx, cy = LOOP_CENTER
    return cx + radius * math.cos(angle), cy + radius * math.sin(angle)


def arc_curves(start: float, end: float, radius: float) -> list[str]:
    """Cubic Béziers along a circle from `start` to `end` (either direction)."""
    steps = max(1, math.ceil(abs(end - start) / (math.pi / 4)))
    span = (end - start) / steps
    k = 4 / 3 * math.tan(span / 4) * radius
    curves = []
    for i in range(steps):
        a0, a1 = start + i * span, start + (i + 1) * span
        (x0, y0), (x1, y1) = point(a0, radius), point(a1, radius)
        c1 = (x0 - k * math.sin(a0), y0 + k * math.cos(a0))
        c2 = (x1 + k * math.sin(a1), y1 - k * math.cos(a1))
        curves.append(f"C{c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {x1:.2f} {y1:.2f}")
    return curves


def band_data(start: float, end: float) -> str:
    """Closed outline of the loop's line between two angles, with square ends.

    A filled outline rather than a stroke: Icon Composer (design generation 26)
    highlights the implicit closing chord of open stroked paths.
    """
    outer, inner = LOOP_RADIUS + LINE_WIDTH / 2, LOOP_RADIUS - LINE_WIDTH / 2
    x0, y0 = point(start, outer)
    x1, y1 = point(end, inner)
    return " ".join(
        [f"M{x0:.2f} {y0:.2f}", *arc_curves(start, end, outer), f"L{x1:.2f} {y1:.2f}", *arc_curves(end, start, inner), "Z"]
    )


BOTTOM = math.pi / 2
TOP = math.pi * 3 / 2


# MARK: - Layers


def svg(body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">{body}</svg>\n'
    )


def wedge_length() -> float:
    return MARKER_SIZE * 0.38


def track_layer(palette: Palette) -> str:
    # Butt end inside the ring band, so the gap between ring and dot stays clear.
    end = TOP - (MARKER_SIZE / 2 - 5) / LOOP_RADIUS
    return svg(f'<path d="{band_data(BOTTOM, end)}" fill="{palette.track}"/>')


def route_layer(palette: Palette) -> str:
    start = TOP + (MARKER_SIZE / 2 + wedge_length() + ROUTE_GAP) / LOOP_RADIUS
    return svg(f'<path d="{band_data(start, BOTTOM + 2 * math.pi)}" fill="{palette.route}"/>')


def ring_layer() -> str:
    x, y = point(TOP)
    width = MARKER_SIZE * 2.5 / 18
    return svg(
        f'<circle cx="{x:g}" cy="{y:g}" r="{MARKER_SIZE / 2:g}" fill="none" stroke="#FFFFFF" '
        f'stroke-width="{width:.2f}"/>'
    )


def dot_layer(palette: Palette) -> str:
    x, y = point(TOP)
    return svg(f'<circle cx="{x:g}" cy="{y:g}" r="{MARKER_SIZE * 0.275:g}" fill="{palette.route}"/>')


def wedge_layer() -> str:
    """Triangle on the ring pointing along the loop (clockwise at the top: right)."""
    x, y = point(TOP)
    base, tip = MARKER_SIZE / 2, MARKER_SIZE / 2 + wedge_length()
    half = wedge_length() * 1.1 / 2
    d = f"M{x + tip:.2f} {y:g} L{x + base:.2f} {y - half:.2f} L{x + base:.2f} {y + half:.2f} Z"
    return svg(f'<path d="{d}" fill="#FFFFFF"/>')


def layers(palette: Palette) -> dict[str, str]:
    return {
        "Dot.svg": dot_layer(palette),
        "Ring.svg": ring_layer(),
        "Wedge.svg": wedge_layer(),
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


def group(name: str, members: list[dict], shadow: float) -> dict:
    return {
        "layers": members,
        "name": name,
        "shadow": {"kind": "neutral", "opacity": shadow},
        "translucency": {"enabled": False, "value": 0.5},
    }


def icon_document(platform: str) -> dict:
    if platform == "iOS":
        # Light by default, like the map; the dark appearance swaps in the Watch palette.
        return {
            "fill-specializations": [{"value": background(LIGHT)}, {"appearance": "dark", "value": background(DARK)}],
            "groups": [
                group("Marker", [layer("Dot", DARK.route), layer("Ring"), layer("Wedge")], 0.5),
                group("Route", [layer("Track", DARK.track), layer("Route", DARK.route)], 0.45),
            ],
            "supported-platforms": {"squares": ["iOS"]},
        }
    return {
        "fill": background(DARK),
        "groups": [
            group("Marker", [layer("Dot"), layer("Ring"), layer("Wedge")], 0.5),
            group("Route", [layer("Track"), layer("Route")], 0.45),
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
