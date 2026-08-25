# Genome Canvas Desktop for macOS

Genome Canvas Desktop is a native AppKit genomics workbench. Its workspace,
track library, locus search, genome selection, zoom, highlight, share, and
export controls are macOS controls; the embedded `WKWebView` is limited to the
IGV genome canvas and the server-backed data/profile dialogs. It does not
launch Safari or duplicate the genome-browser backend.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- Xcode Command Line Tools (`xcode-select --install`)
- Network access to your Genome Canvas server

## Build

Prebuilt downloads:

- [Apple Silicon (arm64)](https://github.com/zhaoshuoxp/genome-canvas/releases/latest/download/GenomeCanvasDesktop-macOS-arm64.zip)
- [Intel (x86_64)](https://github.com/zhaoshuoxp/genome-canvas/releases/latest/download/GenomeCanvasDesktop-macOS-x86_64.zip)

The release archives are ad-hoc signed rather than Apple-notarized. If
Gatekeeper requests confirmation, Control-click the app and choose **Open**.

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

- The default server is `http://127.0.0.1:8000/`. Use **Genome Canvas →
  Server Address…** to enter a LAN server or reverse-proxy URL.
- Change the saved server from **Genome Canvas → Server Address…**. There is no
  browser-style address bar in the main window.
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
