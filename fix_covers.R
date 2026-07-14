#!/usr/bin/env Rscript
# ============================================================
# fix_covers.R  —  Re-extract book cover images into covers/
# ------------------------------------------------------------
# Use this if the book covers show as blank tiles in the app.
# It rebuilds the cover images using R's reliable unzip(), and
# does NOT change books.json (your collections stay intact).
#
# RUN (in RStudio): open this file, then
#   Session > Set Working Directory > To Source File Location
#   and click the "Source" button.
# ============================================================

root       <- getwd()
books_json <- file.path(root, "books.json")
cover_dir  <- file.path(root, "covers")
if (!file.exists(books_json)) stop("books.json not found. Open R inside the app folder (the-reading-room).")
if (!dir.exists(cover_dir)) dir.create(cover_dir)

read_zip_text <- function(zip, name) {
  con <- unz(zip, name, open = "rb"); on.exit(close(con))
  out <- raw(0)
  repeat { ch <- readBin(con, "raw", n = 1048576L); if (!length(ch)) break; out <- c(out, ch) }
  txt <- rawToChar(out); Encoding(txt) <- "UTF-8"; txt
}
get_attr <- function(tag, name) {
  m <- regexec(paste0(name, "\\s*=\\s*\"([^\"]*)\""), tag, perl = TRUE)
  g <- regmatches(tag, m)[[1]]; if (length(g) >= 2) g[2] else NA_character_
}
norm_path <- function(p) {
  parts <- strsplit(p, "/", fixed = TRUE)[[1]]; out <- character(0)
  for (s in parts) { if (s == "" || s == ".") next
    else if (s == "..") { if (length(out)) out <- out[-length(out)] } else out <- c(out, s) }
  paste(out, collapse = "/")
}
find_cover_entry <- function(path) {
  container <- tryCatch(read_zip_text(path, "META-INF/container.xml"), error = function(e) NA_character_)
  if (is.na(container)) return(NA_character_)
  opf_path <- get_attr(container, "full-path"); if (is.na(opf_path)) return(NA_character_)
  opf <- read_zip_text(path, opf_path)
  opf_dir <- dirname(opf_path); if (opf_dir == ".") opf_dir <- ""
  items <- regmatches(opf, gregexpr("<item\\b[^>]*>", opf, perl = TRUE))[[1]]
  hrefs <- list(); cover_href <- NA_character_
  for (it in items) {
    id <- get_attr(it, "id"); href <- get_attr(it, "href")
    mt <- get_attr(it, "media-type"); props <- get_attr(it, "properties")
    if (!is.na(id) && !is.na(href)) hrefs[[id]] <- list(href = href, mt = mt)
    if (!is.na(props) && grepl("cover-image", props) && is.na(cover_href)) cover_href <- href
  }
  if (is.na(cover_href)) {
    metas <- regmatches(opf, gregexpr("<meta\\b[^>]*>", opf, perl = TRUE))[[1]]
    for (mt in metas) if (identical(get_attr(mt, "name"), "cover")) {
      cid <- get_attr(mt, "content"); if (!is.na(cid) && !is.null(hrefs[[cid]])) cover_href <- hrefs[[cid]]$href
    }
  }
  if (is.na(cover_href)) for (v in hrefs)
    if (!is.na(v$mt) && startsWith(v$mt, "image/") && grepl("cover", v$href, ignore.case = TRUE)) { cover_href <- v$href; break }
  if (is.na(cover_href)) for (v in hrefs)         # last resort: first image in the book
    if (!is.na(v$mt) && startsWith(v$mt, "image/")) { cover_href <- v$href; break }
  if (is.na(cover_href)) return(NA_character_)
  if (nzchar(opf_dir)) norm_path(paste0(opf_dir, "/", cover_href)) else norm_path(cover_href)
}

txt  <- paste(readLines(books_json, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
objs <- regmatches(txt, gregexpr("\\{[^{}]*\\}", txt, perl = TRUE))[[1]]
n_ok <- 0; n_fail <- 0
for (o in objs) {
  fg <- regmatches(o, regexec('"file"\\s*:\\s*"([^"]*)"',  o, perl = TRUE))[[1]]
  cg <- regmatches(o, regexec('"cover"\\s*:\\s*"([^"]*)"', o, perl = TRUE))[[1]]
  if (length(fg) < 2) next
  epub <- file.path(root, fg[2])
  if (!file.exists(epub)) { n_fail <- n_fail + 1; next }
  entry <- tryCatch(find_cover_entry(epub), error = function(e) NA_character_)
  if (is.na(entry)) { n_fail <- n_fail + 1; next }
  target <- if (length(cg) >= 2 && nzchar(cg[2])) file.path(root, cg[2]) else {
    id <- tools::file_path_sans_ext(basename(fg[2]))
    ext <- tolower(tools::file_ext(entry)); if (!nzchar(ext)) ext <- "jpg"
    file.path(cover_dir, paste0(id, ".", ext))
  }
  tmp <- tempfile("cv"); dir.create(tmp)
  ok  <- tryCatch({ unzip(epub, files = entry, exdir = tmp, junkpaths = TRUE); TRUE },
                  error = function(e) FALSE)
  src <- list.files(tmp, full.names = TRUE)
  if (ok && length(src) >= 1 && file.info(src[1])$size > 0) {
    file.copy(src[1], target, overwrite = TRUE); n_ok <- n_ok + 1
  } else n_fail <- n_fail + 1
  unlink(tmp, recursive = TRUE)
}
message(sprintf("\nCovers extracted: %d    (could not extract: %d)", n_ok, n_fail))
message("Now refresh the app in your browser to see the covers.")
