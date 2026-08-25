# Track data

Place local track files and their indexes here, or configure other directories in `genomecanvas.config.json`.

Examples: `sample.bam` + `sample.bam.bai`, `variants.vcf.gz` + `variants.vcf.gz.tbi`, or `signal.bigWig`.

# Manhattan / regional association tracks

Genome Canvas recognizes `.gwas`, `.gwas.gz`, and `.gwas.bgz` files. For
large studies, use BGZF compression plus a Tabix index. The first row must be
a tab-delimited header containing chromosome, position, and raw p-value
columns, for example:

```text
chromosome  position  rsid  pvalue  beta  stderr_beta
chr1        123456    rs1   1e-9    0.12  0.03
```

Index a coordinate-sorted file whose first row is the header with:

```bash
bgzip study.hg38.gwas
tabix -S 1 -s 1 -b 2 -e 2 study.hg38.gwas.gz
```

Files loaded in the website are assumed to already match the selected genome
assembly. Liftover is intentionally an offline preparation step.
