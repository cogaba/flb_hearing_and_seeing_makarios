/* The Reading Room — service worker (offline support) */
const SHELL = "reading-room-shell-v1";
const BOOKS = "reading-room-books-v1";
const SHELL_FILES = [
  "./",
  "index.html",
  "styles.css",
  "app.js",
  "books.json",
  "manifest.webmanifest",
  "vendor/epub.min.js",
  "vendor/jszip.min.js",
  "icons/icon-192.png",
  "icons/icon-512.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(SHELL)
      .then((c) => Promise.allSettled(SHELL_FILES.map((f) => c.add(f))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => ![SHELL, BOOKS].includes(k)).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  // Catalog: network-first so newly added books show up; fall back to cache offline
  if (url.pathname.endsWith("books.json")) {
    e.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(SHELL).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match(req))
    );
    return;
  }

  const isBook = /\.epub$/i.test(url.pathname);
  const isCover = url.pathname.includes("/covers/");

  // Books & covers: cache-first, store on first fetch (offline afterwards)
  if (isBook || isCover) {
    e.respondWith(
      caches.open(BOOKS).then(async (cache) => {
        const hit = await cache.match(req);
        if (hit) return hit;
        try {
          const res = await fetch(req);
          if (res.ok) cache.put(req, res.clone());
          return res;
        } catch (err) {
          return hit || Response.error();
        }
      })
    );
    return;
  }

  // App shell: cache-first, fall back to network, then to cached index
  e.respondWith(
    caches.match(req).then((hit) =>
      hit ||
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(SHELL).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match("index.html"))
    )
  );
});
