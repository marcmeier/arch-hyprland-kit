#!/usr/bin/env python3
"""thumbs.py DIR: the folder's images, newest first, as "image<TAB>thumbnail" lines.

Thumbnails (small PNGs for walker's wallpaper menu) are made once and kept in
~/.cache/theme/thumbs, keyed by path and modification time; thumbnails of images that are gone
are removed. Names with a quote, tab or newline are left out: the menu hands the path to a shell
command in single quotes.
"""

import hashlib
import sys
from pathlib import Path

from PIL import Image, ImageOps

CACHE = Path.home() / ".cache" / "theme" / "thumbs"
SIZE = (192, 108)
IMAGES = {".png", ".jpg", ".jpeg", ".webp"}


def thumbnail(image):
    stat = image.stat()
    key = hashlib.sha1(f"{image}\0{stat.st_mtime_ns}".encode()).hexdigest()
    thumb = CACHE / f"{key}.png"
    if not thumb.exists():
        small = ImageOps.fit(Image.open(image).convert("RGB"), SIZE, Image.LANCZOS)
        tmp = thumb.with_name(thumb.name + ".tmp")
        small.save(tmp, "PNG")
        tmp.replace(thumb)
    return thumb


def main(folder):
    CACHE.mkdir(parents=True, exist_ok=True)
    images = [
        p
        for p in Path(folder).iterdir()
        if p.is_file() and p.suffix.lower() in IMAGES and not any(c in str(p) for c in "'\t\n")
    ]
    images.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    used = set()
    for image in images:
        try:
            thumb = thumbnail(image)
        except OSError:
            continue
        used.add(thumb)
        print(f"{image}\t{thumb}")
    for old in CACHE.glob("*.png"):
        if old not in used:
            old.unlink(missing_ok=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__))
