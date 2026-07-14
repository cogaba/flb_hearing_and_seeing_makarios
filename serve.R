# ============================================================
# serve.R  —  Preview "The Reading Room" on your own computer
# ------------------------------------------------------------
# Double-clicking index.html does NOT work (browsers block it).
# This starts a tiny local web address so the app loads properly.
#
# HOW TO RUN (in RStudio):
#   1. Open this file (serve.R).
#   2. Menu:  Session > Set Working Directory > To Source File Location
#   3. Click the "Source" button (top-right of the editor).
#   4. A browser tab opens with your library. Keep RStudio running.
#      To stop, click the red STOP sign in the R console.
# ============================================================

if (!requireNamespace("servr", quietly = TRUE)) {
  message("First time only: installing a small helper (servr)…")
  install.packages("servr", repos = "https://cloud.r-project.org")
}

message("\nStarting your library at a local web address…")
message("A browser tab should open automatically.")
message("If you see a list of files instead of the library, click 'index.html'.")
message("Keep this window open while you use it. Press the red STOP sign to end.\n")

servr::httd(dir = ".", port = 4321, browser = TRUE)
