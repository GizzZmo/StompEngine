#!/usr/bin/env python3
"""Generate AppIcon set, marketing screenshots, and CI preview frames."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "StompEngine" / "Assets.xcassets" / "AppIcon.appiconset"
SCREEN_DIR = ROOT / "docs" / "screenshots"
PREVIEW_DIR = ROOT / "docs" / "preview"
ARTIFACT_DIR = ROOT / "build" / "generated-assets"


def font(size: int, bold: bool = False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/System/Library/Fonts/Menlo.ttc",
        "/Library/Fonts/SF-Mono-Bold.otf" if bold else "/Library/Fonts/SF-Mono-Regular.otf",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def rounded_rect(draw, box, radius: int, fill, outline=None, width: int = 1) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (8, 8, 8, 255))
    draw = ImageDraw.Draw(img)
    margin = max(2, size // 18)
    rounded_rect(
        draw,
        (margin, margin, size - margin, size - margin),
        radius=max(8, size // 6),
        fill=(18, 18, 18, 255),
        outline=(255, 140, 0, 255),
        width=max(2, size // 32),
    )
    cx = cy = size // 2
    r = size // 5
    draw.ellipse((cx - r, cy - r - size // 10, cx + r, cy + r - size // 10), fill=(200, 32, 32, 255))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((cx - r - 4, cy - r - size // 10 - 4, cx + r + 4, cy + r - size // 10 + 4), fill=(255, 60, 40, 80))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(radius=max(1, size // 24))))
    draw = ImageDraw.Draw(img)
    label = "SE"
    f = font(max(10, size // 5), bold=True)
    bbox = draw.textbbox((0, 0), label, font=f)
    tw = bbox[2] - bbox[0]
    draw.text(((size - tw) / 2, size * 0.68), label, font=f, fill=(255, 140, 0, 255))
    return img


def write_appicon() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    master = make_icon(1024)
    master.save(ASSET_DIR / "AppIcon-1024.png")
    contents = {
        "images": [
            {
                "filename": "AppIcon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (ASSET_DIR / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    catalog = ASSET_DIR.parent / "Contents.json"
    catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def slider_row(draw, y: int, w: int, label: str, value: str, frac: float) -> None:
    pad = 48
    draw.text((pad, y), label, font=font(22, bold=True), fill=(160, 160, 160, 255))
    vb = draw.textbbox((0, 0), value, font=font(22, bold=True))
    draw.text((w - pad - (vb[2] - vb[0]), y), value, font=font(22, bold=True), fill=(255, 140, 0, 255))
    track_y = y + 36
    draw.rounded_rectangle((pad, track_y, w - pad, track_y + 8), radius=4, fill=(50, 50, 50, 255))
    filled = pad + int((w - 2 * pad) * frac)
    draw.rounded_rectangle((pad, track_y, filled, track_y + 8), radius=4, fill=(255, 140, 0, 255))
    draw.ellipse((filled - 10, track_y - 6, filled + 10, track_y + 14), fill=(255, 180, 80, 255))


def make_screenshot(width: int, height: int, running: bool, title_suffix: str) -> Image.Image:
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    draw.text((width // 2, 72), "STOMP ENGINE", font=font(36, bold=True), fill=(255, 140, 0, 255), anchor="mm")
    draw.text((width // 2, 112), "USB-C  •  MEASUREMENT I/O", font=font(16, bold=True), fill=(140, 140, 140, 255), anchor="mm")
    box = (32, 140, width - 32, 250)
    rounded_rect(draw, box, 14, fill=(18, 18, 18, 255), outline=(255, 140, 0, 180 if running else 50), width=2)
    lines = [
        ("IN", "USB Audio Device"),
        ("OUT", "USB Audio Device"),
        ("I/O", "48000 Hz  •  64 frames  •  1.33 ms  •  2->2 ch"),
    ]
    yy = 158
    for lab, val in lines:
        draw.text((48, yy), lab, font=font(16, bold=True), fill=(255, 140, 0, 255))
        draw.text((88, yy), val, font=font(16), fill=(220, 220, 220, 255))
        yy += 28
    knobs = [
        ("INPUT", "1.00", 0.44),
        ("DRIVE", "4.00", 0.22),
        ("TONE", "0.35", 0.33),
        ("DELAY MS", "300", 0.32),
        ("FDBK", "0.40", 0.43),
        ("MIX", "0.30", 0.30),
        ("LEVEL", "0.55", 0.44),
    ]
    y = 270
    for label, value, frac in knobs:
        slider_row(draw, y, width, label, value, frac)
        y += 68
    by = height - 160
    rounded_rect(draw, (32, by, width - 180, by + 56), 10, fill=(28, 28, 28, 255))
    draw.text((width // 2 - 90, by + 28), "EFFECT", font=font(20, bold=True), fill=(50, 220, 90, 255), anchor="mm")
    rounded_rect(draw, (width - 168, by, width - 108, by + 56), 10, fill=(28, 28, 28, 255))
    draw.text((width - 138, by + 28), "CH0", font=font(18, bold=True), fill=(240, 240, 240, 255), anchor="mm")
    cx, cy, r = width - 70, by + 28, 34
    color = (220, 40, 40, 255) if running else (90, 90, 90, 255)
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
    draw.text((cx, cy), "PWR", font=font(14, bold=True), fill=(255, 255, 255, 255), anchor="mm")
    draw.text((width // 2, height - 36), title_suffix, font=font(14), fill=(120, 120, 120, 255), anchor="mm")
    return img


def write_screenshots():
    SCREEN_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    frames = [
        ("iphone-15-pro-idle.png", 1290, 2796, False, "idle • effect armed"),
        ("iphone-15-pro-engaged.png", 1290, 2796, True, "engaged • 64-frame I/O"),
        ("iphone-landscape.png", 2796, 1290, True, "landscape • USB-C interface"),
    ]
    written = []
    for name, w, h, running, suffix in frames:
        path = SCREEN_DIR / name
        make_screenshot(w, h, running, suffix).save(path, optimize=True)
        written.append(path)
        thumb = Image.open(path)
        thumb.thumbnail((400, 800))
        tpath = PREVIEW_DIR / name.replace(".png", "-thumb.png")
        thumb.save(tpath)
        written.append(tpath)
    return written


def bundle_artifacts() -> None:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    for src in [ASSET_DIR / "AppIcon-1024.png", *SCREEN_DIR.glob("*.png"), *PREVIEW_DIR.glob("*.png")]:
        if src.exists():
            dest = ARTIFACT_DIR / src.name
            dest.write_bytes(src.read_bytes())
    manifest = {
        "appicon": "AppIcon-1024.png",
        "screenshots": sorted(p.name for p in SCREEN_DIR.glob("*.png")),
        "thumbs": sorted(p.name for p in PREVIEW_DIR.glob("*.png")),
    }
    (ARTIFACT_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def main() -> None:
    write_appicon()
    write_screenshots()
    bundle_artifacts()
    print(f"icons -> {ASSET_DIR}")
    print(f"screenshots -> {SCREEN_DIR}")
    print(f"artifacts -> {ARTIFACT_DIR}")


if __name__ == "__main__":
    main()
