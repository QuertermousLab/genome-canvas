# Genome Canvas

Genome Canvas 是一个面向实验室服务器的自托管基因组和表观基因组浏览器，
包含网页前端、Python 后端以及原生 macOS 客户端。基因组轨道由 IGV.js
渲染，服务器文件无需上传即可直接选择。

## 主要功能

- 支持常用参考基因组以及自定义 FASTA/FAI、2bit
- 支持 BAM、CRAM、VCF、BigWig、BigBed、BED、GFF/GTF、Hi-C、BEDPE、
  GWAS/QTL 等轨道格式
- 自动匹配 BAI、CRAI、TBI、CSI、FAI 索引
- 支持 UCSC/WashU public track hub，以及 ENCODE、GTEx、Roadmap、4DN
- Hi-C 三角热图、半透明信号轨道、自动配色、RefSeq 增强显示
- LocusZoom 风格的区域 Manhattan 图，可选本地 PLINK LD 参考面板
- 支持 gene、坐标和 rsID 搜索
- Workspace 之间分别保存 Favorites、轨道顺序、颜色、大小、位置和 highlight
- 导出 PNG，并生成局域网分享链接
- 原生 AppKit macOS 客户端

## 快速启动

需要 Python 3.8 或更高版本。运行时不需要 npm，也不依赖外网下载 IGV.js。

```bash
git clone <你的仓库地址> genome-canvas
cd genome-canvas
cp genomecanvas.config.example.json genomecanvas.config.json
./start.sh --host 0.0.0.0 --port 8000
```

本机访问 `http://127.0.0.1:8000/`，局域网访问
`http://服务器地址:8000/`。

请编辑 `genomecanvas.config.json`，将 `dataRoots` 改为实际的 track 数据目录。
真实配置、运行日志、workspace 数据库、Favorite、session 和 track 文件都已被
`.gitignore` 排除，不会意外提交到 GitHub。

## Docker

```bash
cp genomecanvas.config.example.json genomecanvas.config.json
GENOME_DATA_DIR=/srv/genome-tracks docker compose up -d --build
```

Workspace、Favorite 和分享 session 默认保存在项目目录下的 `.genomecanvas/`。

## macOS 客户端

```bash
cd macos/GenomeCanvasDesktop
./build.sh
open "dist/Genome Canvas.app"
```

首次启动默认连接 `http://127.0.0.1:8000/`。通过菜单
**Genome Canvas → Server Address…** 修改为实际服务器地址或反向代理路径。

## 迁移和安全

新服务器迁移步骤见 [docs/MIGRATION.md](docs/MIGRATION.md)。Genome Canvas
默认采用无密码 Workspace，适用于可信局域网；不要直接暴露到公网。敏感环境应
使用防火墙、VPN 或带身份验证的反向代理。

## 开源协议

项目采用 [MIT License](LICENSE)。IGV.js 的原始许可证保存在
`vendor/IGV-LICENSE.txt`。
