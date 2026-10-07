# Genome Canvas Desktop for macOS

Genome Canvas Desktop is a native AppKit genomics workbench. Its data-source,
workspace, track library, locus search, genome selection, zoom, highlight,
share, and export controls are macOS controls; the embedded `WKWebView` is
limited to the IGV genome canvas and data/profile dialogs. It does not launch
Safari.

It can either start its bundled local backend or connect to a shared Genome
Canvas server. Local mode browses files on the Mac directly and does not need
`/nfs`, uploads, a separate server checkout, or user/workspace switching.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- Python 3 (provided by Xcode Command Line Tools: `xcode-select --install`)
- Network access only when using **Server** mode

## Build

Prebuilt downloads:

- [Apple Silicon (arm64)](https://github.com/QuertermousLab/genome-canvas/releases/latest/download/GenomeCanvasDesktop-macOS-arm64.zip)
- [Intel (x86_64)](https://github.com/QuertermousLab/genome-canvas/releases/latest/download/GenomeCanvasDesktop-macOS-x86_64.zip)

The release archives are ad-hoc signed rather than Apple-notarized. If
Gatekeeper requests confirmation, Control-click the app and choose **Open**.
If macOS still blocks the app after it has been moved to `/Applications`, run:

```bash
xattr -dr com.apple.quarantine "/Applications/Genome Canvas.app"
```

Then open the app again. Only use this command for the app downloaded from this
repository.

To build from source, run these commands on the Mac:

```bash
cd GenomeCanvasDesktop
./build.sh
open "dist/Genome Canvas.app"
```

The script creates:

- `dist/Genome Canvas.app`
- `dist/GenomeCanvasDesktop-macOS.zip`

You can drag `Genome Canvas.app` into `/Applications`. The build uses an ad-hoc
local signature and does not require an Apple Developer account. Because the
app is built locally, macOS should open it normally; if Gatekeeper asks for
confirmation, Control-click the app and choose **Open** once.

The current build uses Objective-C/AppKit rather than Swift, so it does not
depend on the Swift SDK module versions. If the build script reports that the
selected Apple compiler/SDK is inconsistent, update or reinstall Command Line
Tools. If full Xcode is installed at `/Applications/Xcode.app`, the script
selects its bundled compiler automatically.

## Behavior

- Every launch starts in **Server** mode. Enter the server IP/port once with
  **Genome Canvas → Connect to Server…**; the address persists between launches.
- **This Mac** starts the bundled backend on a dynamically assigned
  `127.0.0.1` port, labels the file root **This Mac**, and stops the backend
  when the app exits. It can browse files readable by the current macOS user.
- Local mode uses one local context: it does not scan `/home`, mount `/nfs`, or
  show workspace/profile-user switching. Local Favorites and file history are
  stored under `~/Library/Application Support/Genome Canvas`.
- Use **Genome Canvas → Connect to Server…** to enter a LAN server or
  reverse-proxy URL. Remote mode retains server workspaces and their isolated
  Favorites and automatically stops any local backend started by the app.
  There is no browser-style address bar in the main window.
- Cookies use WebKit's persistent data store, so the selected workspace remains
  selected between launches.
- Workspaces and loaded tracks are shown in the native sidebar. Tracks can be
  reordered by dragging full rows and removed with **Remove Selected Track**.
- The workspace row has native **＋**, delete, and manage controls. **＋** creates
  a temporary/manual project whose Favorites and file history are isolated and
  whose default server location is `/nfs`; Home workspaces cannot be deleted
  with the temporary-project delete button.
- Genome/locus navigation, zoom, highlights, Favorites, share, and PNG export
  are native toolbar actions. Share links are copied to the macOS clipboard.
- PNG and favorite-profile JSON downloads open a native macOS save panel.
- Favorite-profile imports open a native macOS file picker.
- The app enables plain HTTP only inside its WebKit content view because the
  current LAN deployment does not use HTTPS.
- A validated 1024-pixel PNG icon master is included so building does not rely
  on the version-dependent SVG support in `sips`.

The server remains responsible for the IGV renderer, tracks, LD computation,
Favorites, shared views, file access, and public hubs. Updating the server
updates those features on the next reload; rebuilding the app is only necessary
when its native AppKit interface changes.
