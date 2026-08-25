# Genome Canvas

Self-hosted genome and epigenome browser for laboratory servers, with a web UI
and a native macOS client. Genome Canvas uses
[IGV.js](https://github.com/igvteam/igv.js) for genomic rendering and adds
server-side file browsing, workspace-isolated Favorites, public track hubs,
Hi-C heatmaps, regional association plots, PNG export, and LAN share links.

[中文说明](README.zh-CN.md) · [Migration guide](docs/MIGRATION.md) ·
[Security](SECURITY.md)

## Highlights

- Reference assemblies: hg38, hg19, mm39, mm10, rn7, danRer11, dm6, sacCer3,
  plus custom FASTA/FAI and 2bit references
- Server-side file selection without browser uploads
- BAM, CRAM, VCF, BCF, BigWig, BigBed, BED, BEDGraph, WIG, GFF/GTF, Hi-C,
  BEDPE, SEG, MAF, GWAS/QTL and other IGV.js-supported formats
- Automatic index pairing for BAI, CRAI, TBI, CSI and FAI files
- UCSC and WashU public track hubs, including curated ENCODE, GTEx, Roadmap
  and 4DN entries
- Translucent signal tracks, sample-aware colors, enhanced RefSeq rendering,
  highlights, track reordering and right-click settings
- LocusZoom-style regional association tracks with an optional local PLINK LD
  reference panel
- Password-free Home/manual workspaces with isolated Favorites and file history
- Native AppKit macOS client with native controls and an embedded genome canvas
- Python standard-library backend; no database server is required

## Quick start

Requirements: Python 3.8 or newer. IGV.js is vendored, so the application does
not need npm or internet access at runtime.

```bash
git clone https://github.com/zhaoshuoxp/genome-canvas.git
cd genome-canvas
cp genomecanvas.config.example.json genomecanvas.config.json
./start.sh --host 0.0.0.0 --port 8000
```

Open `http://127.0.0.1:8000/` locally or
`http://YOUR_LAN_HOST:8000/` from another computer.

Edit `genomecanvas.config.json` before deployment. In particular, replace the
example `dataRoots` with directories that contain your genomic tracks. The
configuration file, runtime state, logs and track data are intentionally
ignored by Git.

## Docker

```bash
cp genomecanvas.config.example.json genomecanvas.config.json
GENOME_DATA_DIR=/srv/genome-tracks docker compose up -d --build
```

The container exposes port 8000 by default. Set `GENOME_CANVAS_PORT` to change
the host port. Runtime sessions, workspaces and Favorites are persisted in
`.genomecanvas/`.

## Configuration

```json
{
  "appName": "Genome Canvas",
  "host": "0.0.0.0",
  "port": 8000,
  "defaultGenome": "hg38",
  "defaultLocus": "chr8:127,728,000-127,742,000",
  "homeRoot": "/home",
  "dbSnpHg38": "/srv/references/hg38.dbsnp156.gz",
  "dataRoots": [
    { "label": "Shared tracks", "path": "/srv/genome-tracks" }
  ]
}
```

Optional environment variables override common deployment settings:

- `GENOME_CANVAS_HOST`: bind address
- `GENOME_CANVAS_PORT`: backend port
- `GENOME_DATA_ROOTS`: colon-separated permitted data roots

The rsID resolver can use a local bgzip/tabix dbSNP file through `dbSnpHg38`.
Without it, supported human rsIDs fall back to the public NCBI variation API.
Regional LD is optional; see `ldReferenceHg19` in the example configuration.

## Workspaces and server files

Immediate subdirectories beneath `homeRoot` become Home workspaces. Manual
workspaces can be created in the web UI or macOS app. Each workspace has its
own Favorites and file-browser history. Manual workspaces begin at the first
configured shared root; Home workspaces additionally expose their matching Home
directory.

Only configured roots and Home roots are browsable. Path traversal is blocked.
Symbolic links beneath an allowed root may target files elsewhere on the server;
their data and index companions are served through the controlled data endpoint.

## Native macOS client

The source in `macos/GenomeCanvasDesktop` builds a macOS 13+ AppKit application.
The native shell provides workspace/project controls, track reordering,
genome/locus navigation, highlights, sharing and export. WebKit is limited to
the IGV rendering surface and server-backed dialogs.

```bash
cd macos/GenomeCanvasDesktop
./build.sh
open "dist/Genome Canvas.app"
```

The client initially points to `http://127.0.0.1:8000/`. Choose
**Genome Canvas → Server Address…** to enter a LAN hostname or a reverse-proxy
path such as `http://genome-canvas.example.internal/genome-canvas/`.

## Production and migration

Portable systemd, environment and Nginx examples are in `deploy/`. See
[docs/MIGRATION.md](docs/MIGRATION.md) for moving configuration and workspace
state to another server.

Genome Canvas is designed for trusted LANs. It is not an internet-facing
authentication system. Put it behind a firewall, VPN, or authenticated reverse
proxy if the configured tracks are sensitive.

## Development and tests

```bash
npm install
npm test
```

The test suite uses Python's standard library and Node.js's built-in test
runner. The production frontend uses the vendored IGV.js build in `vendor/`.

## License

Genome Canvas is released under the [MIT License](LICENSE). Vendored IGV.js is
also MIT-licensed; its license is preserved in `vendor/IGV-LICENSE.txt`.
