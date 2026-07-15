/* The Reading Room — offline church library */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const BOOK_CACHE = "reading-room-books-v3";
  let BOOKS = [];
  const BOOK_BY_ID = {};
  let activeCollection = "All";
  let query = "";
  // Apple devices (iPhone/iPad) → open books in Apple Books; desktop → in-app reader
  const IS_APPLE = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
                   (navigator.maxTouchPoints > 1 && /Macintosh|Mac OS X/.test(navigator.userAgent));

  /* ---------- service worker ---------- */
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () =>
      navigator.serviceWorker.register("sw.js").catch(() => {}));
  }
  const setOffline = () => { $("#offlinePill").hidden = navigator.onLine; };
  window.addEventListener("online", setOffline);
  window.addEventListener("offline", setOffline);
  setOffline();

  /* ---------- load catalog ---------- */
  fetch("books.json", { cache: "no-cache" })
    .then((r) => r.json())
    .then((data) => { BOOKS = data.books || []; BOOKS.forEach((b) => (BOOK_BY_ID[b.id] = b)); buildChips(); render(); markSaved(); })
    .catch(() => {
      $("#shelf").innerHTML =
        '<p class="empty">No catalog yet. Add your EPUB files to the <b>epubs</b> folder and run <b>generate_catalog.py</b>.</p>';
    });

  /* ---------- collections ---------- */
  function collections() {
    const set = new Set(BOOKS.map((b) => b.collection || "All books"));
    return ["All", ...[...set].sort((a, b) => a.localeCompare(b))];
  }
  function buildChips() {
    const wrap = $("#chips");
    wrap.innerHTML = "";
    collections().forEach((c) => {
      const btn = document.createElement("button");
      btn.className = "chip";
      btn.role = "tab";
      btn.textContent = c;
      btn.setAttribute("aria-selected", String(c === activeCollection));
      btn.onclick = () => { activeCollection = c; buildChips(); render(); };
      wrap.appendChild(btn);
    });
  }

  /* ---------- render shelf ---------- */
  function matches(b) {
    if (activeCollection !== "All" && (b.collection || "All books") !== activeCollection) return false;
    if (!query) return true;
    const hay = (b.title + " " + (b.author || "") + " " + (b.collection || "")).toLowerCase();
    return hay.includes(query);
  }

  function render() {
    const shelf = $("#shelf");
    shelf.innerHTML = "";
    if (!BOOKS.length) {
      shelf.innerHTML = '<p class="empty">Your library is empty. Add EPUB files to the <b>epubs</b> folder, run <b>generate_catalog.py</b>, and refresh.</p>';
      return;
    }
    const list = BOOKS.filter(matches);
    if (!list.length) {
      shelf.innerHTML = '<p class="empty">No books match that search.</p>';
      return;
    }
    // group by collection only when showing "All" and there is more than one
    const groups = {};
    list.forEach((b) => { (groups[b.collection || "All books"] ||= []).push(b); });
    const names = Object.keys(groups).sort((a, b) => a.localeCompare(b));
    const showHeads = activeCollection === "All" && names.length > 1;

    names.forEach((name) => {
      if (showHeads) {
        const h = document.createElement("div");
        h.className = "group-head";
        h.innerHTML = `<h2>${escapeHtml(name)}</h2>`;
        shelf.appendChild(h);
      }
      groups[name].forEach((b) => shelf.appendChild(card(b)));
    });
    observeCovers();
  }

  // Installed (Home Screen) app has no back button, so never navigate away from the library.
  const isStandalone = () =>
    window.navigator.standalone === true ||
    window.matchMedia("(display-mode: standalone)").matches;

  function card(b) {
    const el = document.createElement(IS_APPLE ? "a" : "button");
    el.className = "book";
    if (IS_APPLE) {
      el.href = encodeURI(b.file);          // iPhone/iPad: hand the EPUB to Apple Books
      el.target = "_blank";                 // open elsewhere so the library stays put
      el.rel = "noopener";
      el.style.textDecoration = "none";
      el.style.color = "inherit";
    } else {
      el.type = "button";
      el.onclick = () => openReader(b);     // desktop: read inside the app
    }
    el.innerHTML =
      `<div class="cover" data-id="${b.id}"><img alt="" hidden><span class="saved-dot"></span></div>` +
      `<p class="b-title">${escapeHtml(b.title)}</p>` +
      (b.author ? `<p class="b-author">${escapeHtml(b.author)}</p>` : "");
    return el;
  }

  /* ---- lazy, self-healing covers ---- */
  const coverObserver = new IntersectionObserver((entries) => {
    entries.forEach((en) => {
      if (!en.isIntersecting) return;
      coverObserver.unobserve(en.target);
      const b = BOOK_BY_ID[en.target.dataset.id];
      if (b) loadCover(en.target, b);
    });
  }, { rootMargin: "500px" });

  function observeCovers() {
    document.querySelectorAll(".cover[data-id]").forEach((el) => {
      if (!el.dataset.loaded) coverObserver.observe(el);
    });
  }

  function loadCover(el, b) {
    el.dataset.loaded = "1";
    const img = el.querySelector("img");
    if (b.cover) {
      img.onload = () => { img.hidden = false; };            // saved cover works → use it
      img.onerror = () => { img.onerror = null; coverFromEpub(el, b, img); };  // missing/empty → dig into the book
      img.src = encodeURI(b.cover);
    } else {
      coverFromEpub(el, b, img);
    }
  }

  async function coverFromEpub(el, b, img) {
    try {
      const bk = ePub(encodeURI(b.file));
      const url = await bk.coverUrl();
      if (url) {
        const blob = await (await fetch(url)).blob();
        const dataUrl = await new Promise((res) => { const fr = new FileReader(); fr.onload = () => res(fr.result); fr.readAsDataURL(blob); });
        img.src = dataUrl; img.hidden = false;
      } else {
        coverFallback(el, b);
      }
      try { bk.destroy(); } catch (_) {}
    } catch (e) {
      coverFallback(el, b);
    }
  }

  function coverFallback(el, b) {
    el.classList.add("fallback");
    if (!el.querySelector("span:not(.saved-dot)")) {
      const s = document.createElement("span");
      s.textContent = b.title;
      el.insertBefore(s, el.firstChild);
    }
  }

  /* ---------- search ---------- */
  $("#search").addEventListener("input", (e) => { query = e.target.value.trim().toLowerCase(); render(); });

  /* ================= READER ================= */
  const reader = $("#reader");
  let book = null, rendition = null, curFont = 108;
  const THEMES = ["day", "sepia", "night"];
  const THEME_CSS = {
    day:   { bg: "#f4efe4", fg: "#22242c" },
    sepia: { bg: "#efe3cc", fg: "#4a3f2c" },
    night: { bg: "#14161c", fg: "#cdd0d6" },
  };
  let themeIdx = Number(localStorage.getItem("rr-theme") || 0);
  if (!(themeIdx >= 0 && themeIdx < THEMES.length)) themeIdx = 0;

  function registerThemes() {
    if (!rendition) return;
    for (const name of THEMES) {
      const c = THEME_CSS[name];
      rendition.themes.register(name, {
        "body": { "background": c.bg + " !important", "color": c.fg + " !important" },
        "p, div, span, li, a, h1, h2, h3, h4, h5, blockquote": { "color": c.fg + " !important" },
      });
    }
  }
  function applyTheme() {
    reader.dataset.theme = THEMES[themeIdx];
    localStorage.setItem("rr-theme", String(themeIdx));
    if (rendition) rendition.themes.select(THEMES[themeIdx]);
  }

  async function openReader(b) {
    reader.hidden = false;
    document.body.style.overflow = "hidden";
    $("#rTitle").textContent = b.title;
    $("#rBooks").href = encodeURI(b.file);
    $("#viewer").innerHTML = "";
    $("#rBar").style.width = "0%";
    try {
      book = ePub(encodeURI(b.file));
      rendition = book.renderTo("viewer", {
        width: "100%", height: "100%", flow: "paginated", spread: "none", manager: "default",
      });
      curFont = Number(localStorage.getItem("rr-font") || 108);
      registerThemes();
      rendition.themes.fontSize(curFont + "%");
      applyTheme();
      const cfi = localStorage.getItem("rr-pos-" + b.id) || undefined;
      await rendition.display(cfi);
      book.ready.then(() => book.locations.generate(1600)).then(() => updateBar());
      rendition.on("relocated", (loc) => {
        localStorage.setItem("rr-pos-" + b.id, loc.start.cfi);
        updateBar(loc);
      });
      // cache this book for offline once opened
      cacheBook(b.file);
    } catch (e) {
      showToast("Sorry — this book could not be opened.");
    }
  }
  function updateBar(loc) {
    try {
      const p = loc && book.locations.length()
        ? book.locations.percentageFromCfi(loc.start.cfi)
        : (book.locations.length() ? rendition.location && book.locations.percentageFromCfi(rendition.location.start.cfi) : 0);
      if (typeof p === "number") $("#rBar").style.width = Math.round(p * 100) + "%";
    } catch (_) {}
  }

  const closeReader = () => {
    reader.hidden = true;
    document.body.style.overflow = "";
    if (rendition) rendition.destroy();
    if (book) book.destroy();
    rendition = book = null;
    markSaved();
  };
  $("#rClose").onclick = closeReader;
  $("#rPrev").onclick = () => rendition && rendition.prev();
  $("#rNext").onclick = () => rendition && rendition.next();
  $("#rFontPlus").onclick = () => setFont(curFont + 12);
  $("#rFontMinus").onclick = () => setFont(curFont - 12);
  $("#rTheme").onclick = () => { themeIdx = (themeIdx + 1) % THEMES.length; applyTheme(); };
  function setFont(v) {
    curFont = Math.max(70, Math.min(180, v));
    localStorage.setItem("rr-font", String(curFont));
    if (rendition) rendition.themes.fontSize(curFont + "%");
  }
  document.addEventListener("keydown", (e) => {
    if (reader.hidden) return;
    if (e.key === "ArrowLeft") rendition && rendition.prev();
    else if (e.key === "ArrowRight") rendition && rendition.next();
    else if (e.key === "Escape") closeReader();
  });
  // swipe
  let tx = 0;
  $("#viewer").addEventListener("touchstart", (e) => (tx = e.changedTouches[0].clientX), { passive: true });
  $("#viewer").addEventListener("touchend", (e) => {
    const dx = e.changedTouches[0].clientX - tx;
    if (Math.abs(dx) > 45 && rendition) dx > 0 ? rendition.prev() : rendition.next();
  }, { passive: true });

  /* ================= OFFLINE SAVING ================= */
  async function cacheBook(url) {
    if (!("caches" in window)) return;
    try {
      const cache = await caches.open(BOOK_CACHE);
      const abs = new URL(url, location.href).href;
      if (!(await cache.match(abs))) await cache.add(abs);
    } catch (_) {}
  }

  async function isSaved(url) {
    if (!("caches" in window)) return false;
    try {
      const cache = await caches.open(BOOK_CACHE);
      return !!(await cache.match(new URL(url, location.href).href));
    } catch (_) { return false; }
  }
  async function markSaved() {
    if (!("caches" in window)) return;
    const cache = await caches.open(BOOK_CACHE);
    for (const b of BOOKS) {
      const el = document.querySelector(`.cover[data-id="${CSS.escape(b.id)}"]`);
      if (!el) continue;
      const saved = await cache.match(new URL(b.file, location.href).href);
      el.classList.toggle("is-saved", !!saved);
    }
  }

  $("#saveAll").addEventListener("click", async () => {
    if (!("caches" in window)) { showToast("Offline saving isn’t supported in this browser."); return; }
    const btn = $("#saveAll");
    btn.disabled = true;
    const cache = await caches.open(BOOK_CACHE);
    let done = 0;
    const total = BOOKS.length;
    const t = showToast(`Saving books… 0 / ${total}`, true);
    for (const b of BOOKS) {
      try {
        const abs = new URL(b.file, location.href).href;
        if (!(await cache.match(abs))) await cache.add(abs);
        if (b.cover) { const c = new URL(b.cover, location.href).href; if (!(await cache.match(c))) await cache.add(c); }
      } catch (_) {}
      done++;
      t.set(done / total, `Saving books… ${done} / ${total}`);
    }
    t.close(`All ${total} books saved. They’ll open with no internet.`);
    btn.disabled = false;
    markSaved();
  });

  /* ---------- toast ---------- */
  function showToast(msg, withBar) {
    const el = $("#toast");
    el.hidden = false;
    el.innerHTML = escapeHtml(msg) + (withBar ? '<div class="bar"><span></span></div>' : "");
    let hideT;
    if (!withBar) hideT = setTimeout(() => (el.hidden = true), 2600);
    return {
      set(p, m) { el.firstChild && (el.childNodes[0].textContent = m); const s = el.querySelector(".bar span"); if (s) s.style.width = Math.round(p * 100) + "%"; },
      close(m) { clearTimeout(hideT); el.textContent = m; setTimeout(() => (el.hidden = true), 2600); },
    };
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  }
})();