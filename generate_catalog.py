#!/usr/bin/env python3
"""
Build the library catalog from your EPUB files.

HOW TO USE
----------
1. Put your .epub files inside the "epubs" folder.
   - To group them into collections (Prayer, Leadership, Marriage, ...),
     make sub-folders and drop the books inside, e.g.:
         epubs/Prayer/how-to-pray.epub
         epubs/Leadership/the-art-of-leadership.epub
     The sub-folder name becomes the collection shown in the app.
   - Books placed directly in "epubs" (no sub-folder) go under "All books".
2. Run:  python3 generate_catalog.py
3. It writes books.json and fills the covers/ folder. That's it.

Only the Python standard library is used - nothing to install.
"""

import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.abspath(__file__))
EPUB_DIR = os.path.join(ROOT, "epubs")
COVER_DIR = os.path.join(ROOT, "covers")
OUT = os.path.join(ROOT, "books.json")

IMG_EXT = {"image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png",
           "image/gif": ".gif", "image/webp": ".webp", "image/svg+xml": ".svg"}


def local(tag):
    return tag.rsplit("}", 1)[-1].lower()


def slugify(name):
    s = re.sub(r"[^a-zA-Z0-9]+", "-", name).strip("-").lower()
    return s or "book"


def find_opf_path(z):
    with z.open("META-INF/container.xml") as f:
        root = ET.parse(f).getroot()
    for el in root.iter():
        if local(el.tag) == "rootfile" and el.get("full-path"):
            return el.get("full-path")
    return None


def parse_epub(path):
    """Return (title, author, cover_bytes, cover_ext) - any may be None."""
    with zipfile.ZipFile(path) as z:
        opf_path = find_opf_path(z)
        if not opf_path:
            return None, None, None, None
        opf_dir = os.path.dirname(opf_path)
        with z.open(opf_path) as f:
            opf = ET.parse(f).getroot()

        title = author = None
        cover_id = None
        manifest = {}          # id -> (href, media_type, properties)
        href_by_props = None

        for el in opf.iter():
            t = local(el.tag)
            if t == "title" and title is None and (el.text or "").strip():
                title = el.text.strip()
            elif t == "creator" and author is None and (el.text or "").strip():
                author = el.text.strip()
            elif t == "meta" and el.get("name") == "cover":
                cover_id = el.get("content")
            elif t == "item":
                iid = el.get("id"); href = el.get("href")
                mt = (el.get("media-type") or "").lower()
                props = (el.get("properties") or "").lower()
                if iid and href:
                    manifest[iid] = (href, mt, props)
                    if "cover-image" in props:
                        href_by_props = (href, mt)

        # resolve cover href, in priority order
        cover_href = cover_mt = None
        if href_by_props:
            cover_href, cover_mt = href_by_props
        elif cover_id and cover_id in manifest:
            cover_href, cover_mt, _ = manifest[cover_id]
        else:
            for href, mt, props in manifest.values():
                if mt.startswith("image/") and "cover" in href.lower():
                    cover_href, cover_mt = href, mt
                    break

        cover_bytes = cover_ext = None
        if cover_href:
            full = os.path.normpath(os.path.join(opf_dir, cover_href)).replace("\\", "/")
            try:
                cover_bytes = z.read(full)
                cover_ext = IMG_EXT.get(cover_mt) or os.path.splitext(full)[1] or ".jpg"
            except KeyError:
                cover_bytes = None
        return title, author, cover_bytes, cover_ext


def main():
    if not os.path.isdir(EPUB_DIR):
        print("No 'epubs' folder found. Create it and add your .epub files.")
        sys.exit(1)
    os.makedirs(COVER_DIR, exist_ok=True)

    books = []
    seen = set()
    for dirpath, _, files in os.walk(EPUB_DIR):
        for fn in sorted(files):
            if not fn.lower().endswith(".epub"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            # collection = immediate sub-folder under epubs/, else "All books"
            inside = os.path.relpath(dirpath, EPUB_DIR).replace("\\", "/")
            collection = "All books" if inside in (".", "") else inside.split("/")[0]

            base = os.path.splitext(fn)[0]
            bid = slugify(base)
            n = bid
            i = 2
            while n in seen:
                n = f"{bid}-{i}"; i += 1
            bid = n; seen.add(bid)

            try:
                title, author, cover_bytes, cover_ext = parse_epub(full)
            except Exception as e:
                print(f"  ! Skipped {fn}: {e}")
                continue

            cover_rel = None
            if cover_bytes:
                cover_name = bid + (cover_ext if cover_ext.startswith(".") else ".jpg")
                with open(os.path.join(COVER_DIR, cover_name), "wb") as cf:
                    cf.write(cover_bytes)
                cover_rel = "covers/" + cover_name

            books.append({
                "id": bid,
                "title": title or base.replace("-", " ").title(),
                "author": author or "",
                "collection": collection,
                "file": rel,
                "cover": cover_rel,
            })
            print(f"  \u2713 {books[-1]['title']}  ({collection})")

    books.sort(key=lambda b: (b["collection"].lower(), b["title"].lower()))
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"books": books}, f, ensure_ascii=False, indent=2)
    print(f"\nDone. {len(books)} book(s) written to books.json.")
    if not books:
        print("Tip: put .epub files inside the 'epubs' folder, then run this again.")


if __name__ == "__main__":
    main()
