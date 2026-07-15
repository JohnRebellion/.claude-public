#!/usr/bin/env python3
"""Shared image-safety inspection for the Claude Code image guard.

Decides whether an image is safe to enter the API conversation. The
"image could not be processed and was removed" error is triggered by the
API rejecting an image at validation time; that rejection forces a full
re-send of the conversation on retry, which is the real token cost. This
module centralizes the limits so the PreToolUse hook and the CLI helper
agree on what "safe" means.

Limits (conservative, matched to Anthropic image constraints):
  - Max bytes (raw file): 5 MB. Base64 inflates ~33%, and the API limit is
    ~5MB on the encoded payload, so we gate the raw file well under that.
  - Max dimension: 8000 px on either side (hard API limit).
  - Max megapixels: 3.75 MP for high-res tiers; above this the image is
    downscaled by the API and large ones risk rejection.
  - Allowed formats: PNG, JPEG, GIF, WEBP (the API-supported set). Anything
    else (AVIF/HEIC/BMP/TIFF/SVG) must be converted first.

Exit-code contract when run as a script with a file path arg:
  0  -> safe
  2  -> unsafe (reasons printed to stdout, one per line)
  3  -> not an image / cannot inspect (caller should allow; not our concern)
"""
from __future__ import annotations

import sys
from pathlib import Path

MAX_BYTES = 5 * 1024 * 1024
MAX_DIM = 8000
MAX_MEGAPIXELS = 3.75
ALLOWED_FORMATS = {"PNG", "JPEG", "GIF", "WEBP"}

# Extensions we treat as "this is meant to be an image". Used by the hook to
# decide whether a Read even needs inspecting.
IMAGE_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp",
    ".bmp", ".tif", ".tiff", ".avif", ".heic", ".heif", ".svg",
}


def inspect(path: str) -> tuple[bool, list[str]]:
    """Return (safe, reasons). reasons is empty when safe.

    On any inability to read the file as an image, returns (True, []) so the
    caller does not block legitimate non-image reads — fail open, never
    block work over an inspection glitch.
    """
    p = Path(path)
    if not p.is_file():
        return True, []

    try:
        size = p.stat().st_size
    except OSError:
        return True, []

    reasons: list[str] = []

    # Bytes check works even if PIL can't open the file.
    if size > MAX_BYTES:
        reasons.append(
            f"file is {size / 1024 / 1024:.1f} MB (limit {MAX_BYTES // 1024 // 1024} MB)"
        )

    try:
        import warnings

        from PIL import Image

        # We intentionally inspect very large images (that's the whole point);
        # disable the decompression-bomb guard and its warning so PIL reports
        # real dimensions instead of refusing or printing to our output.
        Image.MAX_IMAGE_PIXELS = None
        warnings.simplefilter("ignore", Image.DecompressionBombWarning)
    except ImportError:
        # No Pillow: fall back to the bytes check only.
        return (len(reasons) == 0), reasons

    try:
        with Image.open(p) as im:
            fmt = (im.format or "").upper()
            w, h = im.size
    except Exception:
        # Not a decodable image (truncated/corrupt/mislabeled). If the
        # extension claims it is an image, that's exactly the poison case.
        if p.suffix.lower() in IMAGE_EXTS:
            reasons.append(
                "file is not a decodable image (corrupt, truncated, or "
                "mislabeled format) — the API will reject it"
            )
            return False, reasons
        return True, []

    if fmt and fmt not in ALLOWED_FORMATS:
        reasons.append(
            f"format {fmt} is not API-supported (allowed: "
            f"{', '.join(sorted(ALLOWED_FORMATS))}) — convert to PNG/JPEG"
        )
    if w > MAX_DIM or h > MAX_DIM:
        reasons.append(
            f"dimensions {w}x{h} exceed {MAX_DIM}px on the longest side"
        )
    megapixels = (w * h) / 1_000_000
    if megapixels > MAX_MEGAPIXELS:
        reasons.append(
            f"resolution {megapixels:.1f} MP exceeds {MAX_MEGAPIXELS} MP — "
            "downscale before sharing"
        )

    return (len(reasons) == 0), reasons


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: inspect.py <image-path>", file=sys.stderr)
        return 3
    safe, reasons = inspect(sys.argv[1])
    if safe:
        return 0
    for r in reasons:
        print(r)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
