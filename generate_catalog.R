#!/usr/bin/env Rscript
# ============================================================
# The Reading Room - build the library catalog, in R
# ------------------------------------------------------------
# HOW TO USE
#   1. Put your .epub files in the "epubs" folder
#      (optionally in sub-folders named by collection,
#       e.g. epubs/Prayer/, epubs/Leadership/).
#   2. Open R/RStudio IN this app folder, or set it as the
#      working directory, then run:
#            source("generate_catalog.R")
#      (or from a terminal in this folder:  Rscript generate_catalog.R )
#   3. It writes books.json and fills the covers/ folder.
#
# Uses ONLY base R - nothing to install.
# ============================================================

root      <- getwd()
epub_dir  <- file.path(root, "epubs")
cover_dir <- file.path(root, "covers")
out_file  <- file.path(root, "books.json")

if (!dir.exists(epub_dir)) {
  stop("No 'epubs' folder found in: ", root,
       "\nOpen R inside the app folder (or setwd() to it) and try again.")
}
if (!dir.exists(cover_dir)) dir.create(cover_dir)

img_ext <- c("image/jpeg"=".jpg","image/jpg"=".jpg","image/png"=".png",
             "image/gif"=".gif","image/webp"=".webp","image/svg+xml"=".svg")

## ---- small helpers ----
read_zip_raw <- function(zip, name) {
  con <- unz(zip, name, open = "rb"); on.exit(close(con))
  out <- raw(0)
  repeat {
    chunk <- readBin(con, "raw", n = 1048576L)
    if (length(chunk) == 0L) break
    out <- c(out, chunk)
  }
  out
}
read_zip_text <- function(zip, name) {
  txt <- rawToChar(read_zip_raw(zip, name)); Encoding(txt) <- "UTF-8"; txt
}
get_attr <- function(tag, name) {
  m <- regexec(paste0(name, "\\s*=\\s*\"([^\"]*)\""), tag, perl = TRUE)
  g <- regmatches(tag, m)[[1]]
  if (length(g) >= 2) g[2] else NA_character_
}
first_tag_text <- function(xml, tag) {
  m <- regexec(paste0("(?s)<", tag, "[^>]*>\\s*(.*?)\\s*</", tag, ">"), xml, perl = TRUE)
  g <- regmatches(xml, m)[[1]]
  if (length(g) >= 2 && nzchar(g[2])) g[2] else NA_character_
}
unescape <- function(s) {
  if (is.na(s)) return(s)
  s <- gsub("&amp;",  "&", s, fixed = TRUE); s <- gsub("&lt;", "<", s, fixed = TRUE)
  s <- gsub("&gt;",   ">", s, fixed = TRUE); s <- gsub("&quot;","\"", s, fixed = TRUE)
  s <- gsub("&#39;",  "'", s, fixed = TRUE); s <- gsub("&apos;","'", s, fixed = TRUE)
  s <- gsub("&#160;", " ", s, fixed = TRUE); s <- gsub("&nbsp;"," ", s, fixed = TRUE)
  s
}
slugify <- function(x) {
  x <- tolower(x); x <- gsub("[^a-z0-9]+", "-", x); x <- gsub("^-+|-+$", "", x)
  if (nchar(x) == 0) "book" else x
}
norm_path <- function(p) {
  parts <- strsplit(p, "/", fixed = TRUE)[[1]]; out <- character(0)
  for (seg in parts) {
    if (seg == "" || seg == ".") next
    else if (seg == "..") { if (length(out)) out <- out[-length(out)] }
    else out <- c(out, seg)
  }
  paste(out, collapse = "/")
}
json_str <- function(s) {
  if (is.na(s)) return("\"\"")
  s <- gsub("\\", "\\\\", s, fixed = TRUE); s <- gsub("\"", "\\\"", s, fixed = TRUE)
  s <- gsub("\r", "", s, fixed = TRUE);     s <- gsub("\n", "\\n", s, fixed = TRUE)
  s <- gsub("\t", "\\t", s, fixed = TRUE)
  paste0("\"", s, "\"")
}

## ---- parse one epub ----
parse_epub <- function(path) {
  container <- read_zip_text(path, "META-INF/container.xml")
  opf_path  <- get_attr(container, "full-path")
  if (is.na(opf_path)) return(NULL)
  opf     <- read_zip_text(path, opf_path)
  opf_dir <- dirname(opf_path); if (opf_dir == ".") opf_dir <- ""

  title  <- unescape(first_tag_text(opf, "dc:title"))
  author <- unescape(first_tag_text(opf, "dc:creator"))

  items <- regmatches(opf, gregexpr("<item\\b[^>]*>", opf, perl = TRUE))[[1]]
  href_by_id <- list(); cover_href <- NA_character_; cover_mt <- NA_character_
  for (it in items) {
    id    <- get_attr(it, "id");  href <- get_attr(it, "href")
    mt    <- get_attr(it, "media-type"); props <- get_attr(it, "properties")
    if (!is.na(id) && !is.na(href)) href_by_id[[id]] <- list(href = href, mt = mt)
    if (!is.na(props) && grepl("cover-image", props) && is.na(cover_href)) {
      cover_href <- href; cover_mt <- mt
    }
  }
  if (is.na(cover_href)) {                       # <meta name="cover" content="ID">
    metas <- regmatches(opf, gregexpr("<meta\\b[^>]*>", opf, perl = TRUE))[[1]]
    for (mt in metas) if (identical(get_attr(mt, "name"), "cover")) {
      cid <- get_attr(mt, "content")
      if (!is.na(cid) && !is.null(href_by_id[[cid]])) {
        cover_href <- href_by_id[[cid]]$href; cover_mt <- href_by_id[[cid]]$mt
      }
    }
  }
  if (is.na(cover_href)) {                        # last resort: an image named "cover"
    for (v in href_by_id) if (!is.na(v$mt) && startsWith(v$mt, "image/") &&
                              grepl("cover", v$href, ignore.case = TRUE)) {
      cover_href <- v$href; cover_mt <- v$mt; break
    }
  }

  cover_bytes <- NULL; cover_ext <- NA_character_
  if (!is.na(cover_href)) {
    full <- if (nzchar(opf_dir)) norm_path(paste0(opf_dir, "/", cover_href)) else norm_path(cover_href)
    cover_bytes <- tryCatch(read_zip_raw(path, full), error = function(e) NULL)
    if (!is.null(cover_bytes)) {
      ext <- tolower(tools::file_ext(cover_href))
      cover_ext <- if (nzchar(ext)) paste0(".", ext)
                   else if (!is.na(cover_mt) && cover_mt %in% names(img_ext)) img_ext[[cover_mt]]
                   else ".jpg"
    }
  }
  list(title = title, author = author, cover_bytes = cover_bytes, cover_ext = cover_ext)
}

## ---- walk the epubs folder ----
files <- list.files(epub_dir, pattern = "\\.epub$", recursive = TRUE,
                    full.names = TRUE, ignore.case = TRUE)
files <- sort(files)
records <- list(); seen <- character(0)

for (f in files) {
  rel_root  <- substring(f, nchar(root) + 2L)            # e.g. epubs/Prayer/x.epub
  rel_epub  <- substring(f, nchar(epub_dir) + 2L)        # e.g. Prayer/x.epub
  parts     <- strsplit(rel_epub, "/", fixed = TRUE)[[1]]
  collection <- if (length(parts) >= 2) parts[1] else "All books"

  base <- tools::file_path_sans_ext(basename(f))
  id <- slugify(base); n <- id; i <- 2
  while (n %in% seen) { n <- paste0(id, "-", i); i <- i + 1 }
  id <- n; seen <- c(seen, id)

  info <- tryCatch(parse_epub(f), error = function(e) { message("  ! Skipped ", basename(f), ": ", conditionMessage(e)); NULL })
  if (is.null(info)) next

  cover_rel <- NA_character_
  if (!is.null(info$cover_bytes)) {
    cover_name <- paste0(id, if (startsWith(info$cover_ext, ".")) info$cover_ext else ".jpg")
    writeBin(info$cover_bytes, file.path(cover_dir, cover_name))
    cover_rel <- paste0("covers/", cover_name)
  }
  title <- if (is.na(info$title)) tools::toTitleCase(gsub("-", " ", base)) else info$title

  records[[length(records) + 1L]] <- list(
    id = id, title = title, author = if (is.na(info$author)) "" else info$author,
    collection = collection, file = rel_root, cover = cover_rel)
  message("  \u2713 ", title, "  (", collection, ")")
}

## ---- sort + write books.json ----
if (length(records)) {
  ord <- order(tolower(vapply(records, `[[`, "", "collection")),
               tolower(vapply(records, `[[`, "", "title")))
  records <- records[ord]
}
obj_json <- function(b) paste0(
  "    {\n",
  "      \"id\": ",         json_str(b$id),         ",\n",
  "      \"title\": ",      json_str(b$title),      ",\n",
  "      \"author\": ",     json_str(b$author),     ",\n",
  "      \"collection\": ", json_str(b$collection), ",\n",
  "      \"file\": ",       json_str(b$file),       ",\n",
  "      \"cover\": ",       if (is.na(b$cover)) "null" else json_str(b$cover), "\n",
  "    }")
body <- paste(vapply(records, obj_json, ""), collapse = ",\n")
writeLines(paste0("{\n  \"books\": [\n", body, "\n  ]\n}"), out_file, useBytes = TRUE)

message("\nDone. ", length(records), " book(s) written to books.json.")
if (!length(records)) message("Tip: put .epub files in the 'epubs' folder, then run this again.")
