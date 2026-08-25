import assert from "node:assert/strict";
import test from "node:test";

import {
  GENOME_WIDE_THRESHOLD,
  LD_COLORS,
  SIGNIFICANCE_P_VALUE,
  installManhattanRenderer,
  manhattanPointStyle,
  manhattanShape,
  manhattanValue,
  normalizedManhattanRange,
} from "../manhattan-style.mjs";

test("converts GWAS p values to -log10 values", () => {
  assert.equal(manhattanValue({ valueProperty: "value" }, { value: 1e-8 }), 8);
  assert.ok(Number.isNaN(manhattanValue({ valueProperty: "value" }, { value: 0 })));
});

test("uses the corrected 5e-8 genome-wide significance threshold", () => {
  assert.equal(SIGNIFICANCE_P_VALUE, 5e-8);
  assert.equal(GENOME_WIDE_THRESHOLD, -Math.log10(5e-8));
  assert.ok(Math.abs(GENOME_WIDE_THRESHOLD - 7.30103) < 0.00001);
  const range = normalizedManhattanRange({ min: 2, max: 4 });
  assert.equal(range.min, 0);
  assert.ok(range.max > GENOME_WIDE_THRESHOLD);
});

test("maps real LD r squared bins to the LocusZoom-style palette", () => {
  assert.equal(manhattanPointStyle(0.95).fill, LD_COLORS.high);
  assert.equal(manhattanPointStyle(0.75).fill, LD_COLORS.mediumHigh);
  assert.equal(manhattanPointStyle(0.55).fill, LD_COLORS.medium);
  assert.equal(manhattanPointStyle(0.35).fill, LD_COLORS.lowMedium);
  assert.equal(manhattanPointStyle(0.1).fill, LD_COLORS.low);
  assert.equal(manhattanPointStyle(Number.NaN).fill, LD_COLORS.missing);
  assert.equal(manhattanPointStyle(1, true).fill, LD_COLORS.reference);
});

test("uses beta direction for point shapes and a diamond for the LD reference", () => {
  const feature = (beta) => ({ line: `chr6\t1\trs1\t1e-9\t9\tA\tG\t${beta}`, columns: ["chromosome", "position", "rsid", "pvalue", "neg_log_pvalue", "ref", "alt", "beta"] });
  assert.equal(manhattanShape(feature("0.2")), "triangle-up");
  assert.equal(manhattanShape(feature("-0.2")), "triangle-down");
  assert.equal(manhattanShape(feature(".")), "circle");
  assert.equal(manhattanShape(feature("0.2"), true), "diamond");
});

test("installs only on GWAS tracks", () => {
  const gwas = { type: "gwas", config: {}, dataRange: { min: 1, max: 2 }, draw() {} };
  assert.equal(installManhattanRenderer(gwas), true);
  assert.equal(gwas.__genomeCanvasManhattanRenderer, true);
  assert.ok(gwas.dataRange.max > GENOME_WIDE_THRESHOLD);
  assert.equal(installManhattanRenderer(gwas), false);
  assert.equal(installManhattanRenderer({ type: "wig", config: {}, draw() {} }), false);
});
