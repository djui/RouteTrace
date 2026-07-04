#!/usr/bin/env python3
"""Copy canonical app icon sources into iOS and watchOS asset catalogs."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "RouteTrace/Design"
LIGHT_SOURCE = DESIGN / "AppIcon-Light.png"
DARK_SOURCE = DESIGN / "AppIcon-Dark.png"

IOS_ICONSET = ROOT / "RouteTrace/iOSApp/Assets.xcassets/AppIcon.appiconset"
WATCH_ICONSET = ROOT / "RouteTrace/WatchApp/Assets.xcassets/AppIcon.appiconset"

IOS_LIGHT = IOS_ICONSET / "AppIcon-Light.png"
IOS_DARK = IOS_ICONSET / "AppIcon-Dark.png"
WATCH_ICON = WATCH_ICONSET / "AppIcon.png"

SIZE = 1024


def validate_icon(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing icon source: {path}")
    with Image.open(path) as image:
        if image.size != (SIZE, SIZE):
            raise ValueError(f"Expected {SIZE}x{SIZE} icon at {path}, got {image.size}")


def main() -> int:
    validate_icon(LIGHT_SOURCE)
    validate_icon(DARK_SOURCE)

    IOS_ICONSET.mkdir(parents=True, exist_ok=True)
    WATCH_ICONSET.mkdir(parents=True, exist_ok=True)

    shutil.copy2(LIGHT_SOURCE, IOS_LIGHT)
    shutil.copy2(DARK_SOURCE, IOS_DARK)
    shutil.copy2(LIGHT_SOURCE, WATCH_ICON)

    legacy_ios = IOS_ICONSET / "AppIcon.png"
    if legacy_ios.exists():
        legacy_ios.unlink()

    print(f"Updated {IOS_LIGHT}")
    print(f"Updated {IOS_DARK}")
    print(f"Updated {WATCH_ICON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
