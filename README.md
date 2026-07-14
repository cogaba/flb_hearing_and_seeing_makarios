# The Reading Room — offline church book library

A simple web app that holds a collection of EPUB books so church members can
**tap a cover and start reading**, even with no internet. It installs to the
Home Screen like a normal app, and each book also has an **Open in Apple Books**
button for anyone who prefers Apple's reader.

You host it for free on **GitHub Pages** and share one link.

---

## Before you start: a one-line permission note

These books are © Dag Heward-Mills, and the source site says "all rights
reserved" even though it offers them free to download. Since you're distributing
copies through this app, get a quick written **"yes, this is fine for our church
app"** from the pastor or the ministry office and keep it on file. It's a
five-minute email and it protects you and the church. You likely already have
this relationship — just make it explicit.

---

## What you do (about 20 minutes, no coding)

### 1. Add the books
Download the EPUB files from the source site and put them in the **`epubs`**
folder.

To sort them into collections (the filter buttons at the top of the app), make
sub-folders named after each collection — matching the site's categories works
well:

```
epubs/
  Prayer/
    how-to-pray.epub
    everything-by-prayer.epub
  Leadership/
    the-art-of-leadership.epub
  Marriage/
    model-marriage.epub
  loyalty-and-disloyalty.epub      <- a book with no folder shows under "All books"
```

### 2. Build the catalog
Open a terminal in this folder and run **one** of these — whichever you have:

```
python3 generate_catalog.py      # if you have Python (built in on Macs)
```
```
Rscript generate_catalog.R       # if you have R
```

In **RStudio** you can instead open `generate_catalog.R`, use
*Session → Set Working Directory → To Source File Location*, then click
**Source**.

Either one reads every EPUB, pulls out its title, author, and cover, and writes
`books.json` plus the images in `covers/`. Re-run it any time you add or remove
books. Both scripts do the same thing and need **no extra packages**.

### 3. Put it on GitHub
1. Create a free GitHub account and a new **public** repository.
2. Upload everything in this folder (drag-and-drop works on github.com:
   `index.html`, `app.js`, `styles.css`, `sw.js`, `manifest.webmanifest`,
   `books.json`, and the `epubs/`, `covers/`, `vendor/`, `icons/` folders).
3. In the repo, go to **Settings → Pages**, set **Source** to
   *Deploy from a branch*, pick **main** / **/(root)**, and save.
4. After a minute GitHub gives you a link like
   `https://yourname.github.io/reading-room/`. That's the app.

### 4. Share it and install it
Send members the link. On an iPhone/iPad, open it in **Safari**, tap the
**Share** button, then **Add to Home Screen**. It now opens full-screen like an
app.

### 5. Make it work with no internet
Open the app once on Wi-Fi and tap **Save all books for offline** at the bottom.
After that, books open with no connection. (Books also save automatically the
first time each one is opened.)

---

## Customising

- **Rename the library:** open `index.html` and change "The Reading Room" and
  the subtitle line. Change the same name in `manifest.webmanifest`.
- **Colors/app icon:** edit the palette at the top of `styles.css`; replace the
  images in `icons/` if you want a different icon.

---

## Good to know

- **iPad/iPhone storage:** Apple limits how much a web app can store offline.
  A large library (hundreds of books) may not *all* fit via "Save all"; opening
  a book always saves that one. This is an Apple limit, not a bug.
- **Open in Apple Books** downloads that single EPUB and hands it to Apple Books,
  where it joins the member's personal library.
- **Nothing here needs installing** except Python (already on Macs) to run the
  catalog script. The reader library is included in `vendor/` — no internet
  dependency.

---

## Folders

| Item | What it is |
|------|------------|
| `index.html`, `app.js`, `styles.css` | the app |
| `sw.js`, `manifest.webmanifest` | makes it installable and offline-capable |
| `generate_catalog.py` | builds `books.json` + covers from your EPUBs |
| `epubs/` | **you add EPUB files here** |
| `covers/`, `books.json` | created for you by the script |
| `vendor/` | the bundled EPUB reader (epub.js + JSZip) |
| `icons/` | Home Screen icons |
