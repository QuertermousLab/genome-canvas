# Genome Canvas — guide for agents and new sessions

Read this before changing anything. It records where the project runs, how to
develop and release it safely, and decisions the maintainer has already made.
User-facing documentation is in `README.md` and `macos/GenomeCanvasDesktop/README.md`.

## What it is

A LAN genome browser built on IGV.js 3.8.5 (`vendor/igv.min.js`) with a
dependency-free Python 3.8+ backend (`server.py`) and a native macOS client
(`macos/GenomeCanvasDesktop`, Objective-C/AppKit + WKWebView). No build step for
the web app: plain HTML, CSS and ES modules.

| Path | Role |
| --- | --- |
| `server.py` | HTTP server: static files (whitelist `STATIC_FILES`), `/data/` byte ranges, `/api/*` (workspaces, files, tracks, hubs, rsID, LD, profiles, sessions), gzip, bundled fonts |
| `workspace_store.py`, `resource_cache.py` | Workspace SQLite store; reference-genome cache and in-memory file cache |
| `index.html`, `styles.css`, `app.js` | Web UI; `app.js` also exposes `window.GenomeCanvasDesktop` for the Mac client |
| `track-colors.mjs`, `signal-style.mjs`, `annotation-style.mjs`, `hic-heatmap.mjs`, `manhattan-style.mjs` | Track coloring and custom IGV renderers |
| `canvas-theme.mjs` | Canvas chrome palette for light/dark and the dark-mode canvas adapter |
| `public-hubs.mjs`, `highlights.mjs`, `reference-resources.mjs` | Hub catalog, highlights, cached reference URLs |
| `tools/` | Offline data prep: reference cache, GWAS LD precomputation |
| `deploy/` | systemd user units and the Apache port-8892 gateway used on the lab server |
| `vendor/fonts/` | Manrope, Fraunces, JetBrains Mono (woff2, SIL OFL) |
| `macos/GenomeCanvasDesktop/` | `Sources/main.m`, `build.sh`, `Resources/` (Info.plist, icon, `Fonts/*.ttf`), `RELEASE_NOTES.md` |

## Where it runs

- **Repository:** https://github.com/QuertermousLab/genome-canvas, branch `main`.
- **Production server ("thor"):** `quanyiz@171.65.68.140`. It serves
  `http://171.65.68.140:8892/genome-canvas/` from `~/baldar/IGV`, which is the
  shared NFS directory `/nfs/baldar/quanyiz/IGV`. That directory **is a git checkout of `main`**
  and is the live deployment: any file changed there is served immediately.
- Backend: user systemd unit `genome-canvas.service` (127.0.0.1:8000). Gateway:
  `genome-canvas-gateway.service` (Apache on 0.0.0.0:8892, `/genome-canvas/` →
  backend, everything else → JupyterLab on 8891). Manage with
  `./genome-canvasctl start|stop|restart|status|logs|access` on thor.
- Lab config `genomecanvas.config.json` is **not** in git (data roots, dbSNP
  path `dbSnpHg38`, 1000 Genomes LD panel `ldReferenceHg19`). Runtime state lives in
  `.genomecanvas/` (workspaces.sqlite3, sessions = share links, profiles =
  Favorites, apache logs) and must never be deleted or committed.
- Other lab machines (e.g. cvmed-loki) see the same NFS directory but have **no
  SSH key for thor** and cannot reach port 8892. Give the user commands to run on
  thor. Thor's Apache logs are readable from NFS at `.genomecanvas/apache/access.log`.
- Temporary deployment while thor is down (see README "Running Temporarily on
  Another Server"): `./start.sh --host 127.0.0.1 --port 8000` plus an SSH tunnel.
  Stop it before thor resumes, because both would write the same SQLite database.

## Development workflow

1. **Do branch work in a separate worktree,** not in the live NFS checkout:
   `git worktree add /tmp/<dir> -b <branch>`. Commit small fixes on `main` only
   when they are ready to go live.
2. Commit identity for this repo: `Genome Canvas Contributors
   <genome-canvas@users.noreply.github.com>` (set in the repo config; do not use a
   personal email). The NFS directory needs `core.fileMode false` (files are 0777 on NFS) and
   `safe.directory /nfs/baldar/quanyiz/IGV` (the directory is owned by another
   account). Set these on each new machine.
3. Run `npm test` (Python unittest + Node test runner, offline). CI runs the same
   suite on Python 3.8 / Node 20, so keep Python syntax 3.8-compatible.
4. Push `main`; the NFS checkout on thor needs `git pull` (or work directly in it
   for live fixes). **Restart the backend on thor after any `server.py` change**
   (`./genome-canvasctl restart`). Example: the old process answered unknown new
   paths with HTTP 409, the module graph failed, and the workspace list looked
   empty.

### Rules when changing the web app

- **Cache busting:** versioned assets are served `immutable` for a day. When
  editing `app.js`, `styles.css` or a module, bump its `?v=` everywhere it
  appears: the `<link rel="modulepreload">`/`<script>` tags in `index.html`, and
  the import specifiers in `app.js` and the modules (`canvas-theme.mjs` is
  imported by several). The preload `href`s must match the import URLs exactly.
- **New static file:** add it to `STATIC_FILES` in `server.py`, to
  `build.sh`'s `LocalBackend` list (the Mac app bundles the web app), and to the
  `Dockerfile` if needed. Then extend the tests that assert these lists.
- `server.py` must stay standard-library only.

## Decisions already made (do not revisit without asking)

- **Track colors never change** in any theme (the user's firmest constraint).
  The only exception the user approved: in dark mode, neutral dark-gray
  features such as RefSeq genes `rgb(69,74,72)` draw light gray (`liftedFeature`
  in `canvas-theme.mjs`). Colored tracks and ideogram bands are untouched.
- **Themes:** Nord "Snow Storm" light (`:root` in `styles.css`) and Nord "Polar
  Night" dark (`html[data-theme="dark"]`), following the OS with a manual toggle
  (saved in `localStorage` key `genome-canvas:theme`). Dark track canvas `#2e3440`.
  **No bright blue and no purple** in the interface.
- **Fonts:** Manrope (UI), Fraunces (headings), JetBrains Mono (loci, code) in
  both themes and in the Mac app.
- **Layout:** classic: top bar, left track library, canvas toolbar row.
- **PNG export is always white/light** regardless of theme
  (`exportPNG` switches to `LIGHT_CANVAS` around `toSVG`).
- **Logo:** `public/favicon.svg` (signal peak + gene row on a teal tile);
  `macos/.../GenomeCanvas-1024.png` is rendered from it.
- The user approved publishing the lab's internal paths and server address in the public repo.
- Show the user visual options (screenshots) before large UI changes; they
  choose from candidates.

## Dark-mode canvas internals

IGV.js paints its ruler, axes, labels and ideogram outline in hard-coded black,
and clears feature tracks and axis columns with white. `installDarkCanvasAdapter()`
(called at the top of `app.js`, before IGV draws) patches
`CanvasRenderingContext2D` so that, in dark mode only:
- near-black neutral text and strokes become light;
- full-width white clears and white axis/sample-column backgrounds become the
  canvas color;
- neutral gray features are lifted.

Renderer-owned chrome (LD legend, Hi-C cells) reads `canvasTheme()` and is drawn
inside `withoutCanvasAdapter()`. IGV's HTML (track labels, menus, drag/gear
columns) is themed through `.genome-canvas-dark` CSS in `TRACK_REORDER_CSS` in
`app.js`. Covered by `tests/test_canvas_theme.mjs`.

## macOS client

- AppKit code (`Sources/main.m`) **only compiles on macOS**. Without a Mac, push a
  branch named `mac-ui-*`: the **macOS UI preview** workflow builds the app,
  launches it in This Mac mode with `GENOME_CANVAS_SNAPSHOT_DIR`, and uploads
  `window-light.png` / `window-dark.png` as artifact `macos-ui-preview`
  (`gh run download <id> -n macos-ui-preview`). Review them before merging.
- The palette is defined with `GC_COLOR(...)` macros that mirror the CSS tokens.
  Custom controls (`GCButton`, `GCCardButton`, `GCTrackRowView`, `GCFillView`)
  draw in `drawRect:` so they follow appearance changes and render in snapshots.
- Appearance: `NSUserDefaults` key `GenomeCanvasAppearance` (`light`/`dark`,
  absent = system). The native app pushes the effective theme to the web canvas
  via the `setTheme` bridge method.
- `normalizedURL` adds `/genome-canvas/` to bare LAN addresses but must not for
  loopback (`127.0.0.1`). The bundled backend is served at `/`. Breaking this caused 1.5.0's
  This Mac 404.
- **Release:** bump `CFBundleShortVersionString`/`CFBundleVersion` in
  `Resources/Info.plist` and the version asserted in `tests/test_macos_desktop.py`,
  update `RELEASE_NOTES.md` (keep the `xattr -dr com.apple.quarantine`
  section; a test enforces it), merge to `main`, then push tag `vX.Y.Z`.
  `release-macos.yml` builds arm64 + x86_64 archives and publishes them.

## Verifying web UI changes

There is no browser on the servers. To screenshot: install Playwright and
Chromium in a temporary directory (`npm i playwright` then
`npx playwright install chromium`), run `python3 server.py --host 127.0.0.1 --port 8000`
against the NFS checkout (it shares the live `.genomecanvas` state, so stop it
afterwards), set the cookie `genome_canvas_workspace` to a workspace id from
`/api/workspaces`, and capture both themes with `colorScheme: "light"|"dark"`.
Wait for the selector `#viewer-loading.hidden` with `state: "attached"`.

## History

- **2026-10:** web UI redesigned (Nord themes, fonts, logo, dark canvas,
  gzip/scandir/preload performance work). The NFS copy, which had diverged from
  GitHub, was merged into the repo and turned into a git checkout. Releases
  1.5.0 and 1.5.1 were published.
- **1.5.0's This Mac mode is broken** (404); 1.5.1 fixes it and adds the native
  Nord redesign.
- Untracked items that were intentionally left in place:
  - `node_modules/`: only needed for `npm run vendor:update`.
  - Apache logs in `.genomecanvas/apache/`: truncate them rather than delete them; Apache keeps them open.
  - `data/.claude/`.
