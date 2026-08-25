export const SIGNIFICANCE_P_VALUE = 5e-8;
export const GENOME_WIDE_THRESHOLD = -Math.log10(SIGNIFICANCE_P_VALUE);

export const LD_COLORS = Object.freeze({
  reference: "#9632b8",
  missing: "#b8b8b8",
  low: "#357ebd",
  lowMedium: "#46b8da",
  medium: "#5cb85c",
  mediumHigh: "#eea236",
  high: "#d43f3a",
});

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function featureFields(feature) {
  if (feature?.__genomeCanvasFieldMap) return feature.__genomeCanvasFieldMap;
  const result = new Map();
  if (feature?.line && Array.isArray(feature.columns)) {
    const values = feature.line.split("\t");
    feature.columns.forEach((column, index) => result.set(String(column).toLowerCase(), values[index]));
  }
  if (feature) feature.__genomeCanvasFieldMap = result;
  return result;
}

function featureField(feature, names) {
  const fields = featureFields(feature);
  for (const name of names) {
    const value = fields.get(String(name).toLowerCase());
    if (value !== undefined && value !== "") return value;
  }
  return undefined;
}

function numericFeatureField(feature, names) {
  const value = Number(featureField(feature, names));
  return Number.isFinite(value) ? value : Number.NaN;
}

export function manhattanValue(track, feature) {
  const property = track?.valueProperty || "value";
  const raw = Number(feature?.[property]);
  if (!Number.isFinite(raw)) return Number.NaN;
  if (track?.posteriorProbability) return raw;
  if (raw <= 0) return Number.NaN;
  return -Math.log10(raw);
}

export function manhattanPointStyle(rSquared, isReference = false) {
  if (isReference) return { fill: LD_COLORS.reference, stroke: "#642477", radius: 5.2 };
  if (!Number.isFinite(rSquared)) return { fill: LD_COLORS.missing, stroke: "#7f7f7f", radius: 3.8 };
  if (rSquared >= 0.8) return { fill: LD_COLORS.high, stroke: "#922c29", radius: 4.4 };
  if (rSquared >= 0.6) return { fill: LD_COLORS.mediumHigh, stroke: "#a96e1e", radius: 4.2 };
  if (rSquared >= 0.4) return { fill: LD_COLORS.medium, stroke: "#39743a", radius: 4 };
  if (rSquared >= 0.2) return { fill: LD_COLORS.lowMedium, stroke: "#287b91", radius: 3.9 };
  return { fill: LD_COLORS.low, stroke: "#28577e", radius: 3.8 };
}

export function manhattanShape(feature, isReference = false) {
  if (isReference) return "diamond";
  const beta = numericFeatureField(feature, ["beta", "effect", "effect_size", "estimate"]);
  if (!Number.isFinite(beta) || beta === 0) return "circle";
  return beta > 0 ? "triangle-up" : "triangle-down";
}

export function normalizedManhattanRange(dataRange) {
  const observedMaximum = Number(dataRange?.max);
  return {
    min: 0,
    max: Math.max(GENOME_WIDE_THRESHOLD + 0.7, Number.isFinite(observedMaximum) ? observedMaximum : 0),
  };
}

function featureR2(feature) {
  if (Number.isFinite(feature?.genomeCanvasR2)) return feature.genomeCanvasR2;
  return numericFeatureField(feature, ["r2", "r_squared", "ld_r2", "ld", "correlation"]);
}

function featureOriginalLocus(feature) {
  const value = featureField(feature, ["hg19_locus", "grch37_locus"]);
  const match = String(value || "").match(/^(?:chr)?([0-9]+|X|Y):(\d+)$/i);
  if (!match) return null;
  return { chromosome: match[1].toUpperCase(), position: Number(match[2]) };
}

function featureAlleles(feature) {
  return {
    ref: String(featureField(feature, ["ref", "reference_allele"]) || ""),
    alt: String(featureField(feature, ["alt", "alternate_allele", "effect_allele"]) || ""),
  };
}

function allelesMatch(first, second) {
  if (!first?.ref || !first?.alt || !second?.ref || !second?.alt) return true;
  const normalized = (pair) => [pair.ref.toUpperCase(), pair.alt.toUpperCase()].sort().join("/");
  if (normalized(first) === normalized(second)) return true;
  const complement = (value) => value.toUpperCase().replace(/[ACGT]/g, (base) => ({ A: "T", C: "G", G: "C", T: "A" })[base]);
  return normalized({ ref: complement(first.ref), alt: complement(first.alt) }) === normalized(second);
}

function augmentPopup(feature, label) {
  if (!feature || feature.__genomeCanvasLDPopup || typeof feature.popupData !== "function") return;
  const originalPopup = feature.popupData;
  feature.popupData = function popupData(...args) {
    const originalResult = originalPopup.apply(this, args);
    const result = Array.isArray(originalResult) ? originalResult : [];
    const rSquared = featureR2(this);
    if (Number.isFinite(rSquared)) {
      result.push({ name: `LD r² (${label})`, value: rSquared.toFixed(3) });
    } else {
      result.push({ name: "LD r²", value: "Not available" });
    }
    if (this.genomeCanvasIsLDReference) result.push({ name: "LD reference", value: this.genomeCanvasLDId || "Yes" });
    return result;
  };
  feature.__genomeCanvasLDPopup = true;
}

function endpointURL(endpoint, parameters) {
  const base = typeof document === "undefined" ? "http://localhost/" : document.baseURI;
  const url = new URL(String(endpoint || "api/gwas-ld").replace(/^\/+/, ""), base);
  for (const [name, value] of Object.entries(parameters)) url.searchParams.set(name, value);
  return url;
}

async function fetchLDForFeatures(track, features) {
  if (!features?.length) return features;
  const embedded = features.some((feature) => Number.isFinite(featureR2(feature)));
  if (embedded) {
    track.__genomeCanvasLDStatus = { available: true, label: track.config?.ldLabel || "embedded LD" };
    for (const feature of features) augmentPopup(feature, track.__genomeCanvasLDStatus.label);
    return features;
  }

  const candidates = features
    .map((feature) => ({ feature, locus: featureOriginalLocus(feature), value: manhattanValue(track, feature) }))
    .filter((item) => item.locus && Number.isFinite(item.value));
  if (!candidates.length || !track.config?.ldEndpoint) {
    track.__genomeCanvasLDStatus = { available: false, label: track.config?.ldLabel || "LD", reason: "No compatible LD coordinates" };
    return features;
  }
  candidates.sort((first, second) => second.value - first.value);
  const lead = candidates[0];
  const chromosome = lead.locus.chromosome;
  const sameChromosome = candidates.filter((item) => item.locus.chromosome === chromosome);
  const start = Math.min(...sameChromosome.map((item) => item.locus.position));
  const end = Math.max(...sameChromosome.map((item) => item.locus.position));
  const maxWindow = Number(track.config.ldMaxWindow) || 2_000_000;
  if (end - start > maxWindow) {
    track.__genomeCanvasLDStatus = { available: false, label: track.config?.ldLabel || "LD", reason: `Zoom to ≤${maxWindow / 1_000_000} Mb` };
    return features;
  }

  const alleles = featureAlleles(lead.feature);
  const key = [chromosome, start, end, lead.locus.position, alleles.ref, alleles.alt].join(":");
  track.__genomeCanvasLDCache ||= new Map();
  let payload = track.__genomeCanvasLDCache.get(key);
  if (!payload) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 22000);
    try {
      const response = await fetch(endpointURL(track.config.ldEndpoint, {
        chrom: chromosome,
        start,
        end,
        lead: lead.locus.position,
        ref: alleles.ref,
        alt: alleles.alt,
      }), { credentials: "same-origin", signal: controller.signal });
      if (!response.ok) throw new Error(`LD request returned ${response.status}`);
      payload = await response.json();
      if (track.__genomeCanvasLDCache.size >= 8) {
        track.__genomeCanvasLDCache.delete(track.__genomeCanvasLDCache.keys().next().value);
      }
      track.__genomeCanvasLDCache.set(key, payload);
    } catch (error) {
      payload = { available: false, label: track.config?.ldLabel || "LD", reason: error.name === "AbortError" ? "LD request timed out" : error.message };
    } finally {
      clearTimeout(timeout);
    }
  }

  track.__genomeCanvasLDStatus = payload;
  if (!payload.available) return features;
  const byPosition = new Map();
  for (const variant of payload.variants || []) {
    if (!byPosition.has(Number(variant.position))) byPosition.set(Number(variant.position), []);
    byPosition.get(Number(variant.position)).push(variant);
  }
  for (const item of sameChromosome) {
    const matches = byPosition.get(item.locus.position) || [];
    const allelesForFeature = featureAlleles(item.feature);
    const match = matches.find((variant) => allelesMatch(allelesForFeature, variant)) || matches[0];
    if (match && Number.isFinite(Number(match.r2))) item.feature.genomeCanvasR2 = Number(match.r2);
    if (
      payload.reference
      && item.locus.position === Number(payload.reference.position)
      && allelesMatch(allelesForFeature, payload.reference)
    ) {
      item.feature.genomeCanvasIsLDReference = true;
      item.feature.genomeCanvasR2 = 1;
      item.feature.genomeCanvasLDId = payload.reference.id;
    }
    augmentPopup(item.feature, payload.label || track.config.ldLabel || "LD");
  }
  return features;
}

function ensureTrackRange(track) {
  const normalized = normalizedManhattanRange(track.dataRange);
  if (track.dataRange?.min !== normalized.min || track.dataRange?.max !== normalized.max) {
    track.dataRange = normalized;
  }
  return normalized;
}

function drawHorizontalGuides(context, width, height, dataRange) {
  const minimum = Number(dataRange?.min);
  const maximum = Number(dataRange?.max);
  if (!Number.isFinite(minimum) || !Number.isFinite(maximum) || maximum <= minimum) return;

  const yFor = (value) => height - ((value - minimum) / (maximum - minimum)) * height;
  const interval = maximum > 30 ? 10 : maximum > 12 ? 5 : 2;
  context.save();
  context.lineWidth = 1;
  context.setLineDash?.([3, 5]);
  context.strokeStyle = "rgba(104, 112, 116, 0.16)";
  for (let value = Math.ceil(minimum / interval) * interval; value < maximum; value += interval) {
    const y = yFor(value);
    context.beginPath();
    context.moveTo(0, y);
    context.lineTo(width, y);
    context.stroke();
  }

  const y = yFor(GENOME_WIDE_THRESHOLD);
  context.setLineDash?.([7, 5]);
  context.strokeStyle = "rgba(157, 94, 99, 0.78)";
  context.beginPath();
  context.moveTo(0, y);
  context.lineTo(width, y);
  context.stroke();
  context.setLineDash?.([]);
  context.fillStyle = "rgba(116, 72, 76, 0.95)";
  context.font = "600 10px Arial, sans-serif";
  context.textAlign = "right";
  const labelX = width >= 210 ? width - 128 : width - 7;
  context.fillText("P = 5×10⁻⁸", Math.max(72, labelX), Math.max(11, y - 4));
  context.restore();
}

function symbolPath(context, x, y, radius, shape) {
  context.beginPath();
  if (shape === "diamond") {
    context.moveTo(x, y - radius * 1.25);
    context.lineTo(x + radius, y);
    context.lineTo(x, y + radius * 1.25);
    context.lineTo(x - radius, y);
    context.closePath();
  } else if (shape === "triangle-up") {
    context.moveTo(x, y - radius * 1.25);
    context.lineTo(x + radius * 1.12, y + radius);
    context.lineTo(x - radius * 1.12, y + radius);
    context.closePath();
  } else if (shape === "triangle-down") {
    context.moveTo(x - radius * 1.12, y - radius);
    context.lineTo(x + radius * 1.12, y - radius);
    context.lineTo(x, y + radius * 1.25);
    context.closePath();
  } else {
    context.arc(x, y, radius, 0, Math.PI * 2);
  }
}

function drawPoint(context, x, y, style, shape, alpha) {
  context.save();
  context.globalAlpha = clamp(alpha, 0.15, 1);
  symbolPath(context, x, y, style.radius, shape);
  context.fillStyle = style.fill;
  context.fill();
  context.globalAlpha = clamp(alpha + 0.08, 0.2, 1);
  context.strokeStyle = style.stroke;
  context.lineWidth = 0.85;
  context.stroke();
  context.restore();
}

function featureLabel(feature) {
  if (feature?.genomeCanvasLDId) return feature.genomeCanvasLDId;
  const label = featureField(feature, ["rsid", "snp", "variant", "name"]);
  if (label && label !== ".") return label;
  return feature?.chr && Number.isFinite(feature?.start) ? `${feature.chr}:${feature.start + 1}` : "";
}

function drawLeadLabel(context, feature, value, width) {
  const label = featureLabel(feature);
  if (!label || value < GENOME_WIDE_THRESHOLD) return;
  const maximumX = width >= 210 ? width - 148 : width - 42;
  const x = clamp(feature.px, 42, Math.max(42, maximumX));
  const y = Math.max(13, feature.py - 9);
  context.save();
  context.font = "600 11px Arial, sans-serif";
  context.textAlign = "center";
  context.lineWidth = 3;
  context.strokeStyle = "rgba(255, 255, 255, 0.94)";
  context.strokeText(label, x, y);
  context.fillStyle = "#292d30";
  context.fillText(label, x, y);
  context.restore();
}

function drawLDLegend(context, width, status) {
  if (width < 210) return;
  const boxWidth = 114;
  const boxHeight = 192;
  const x = width - boxWidth - 8;
  const y = 8;
  const colors = [LD_COLORS.high, LD_COLORS.mediumHigh, LD_COLORS.medium, LD_COLORS.lowMedium, LD_COLORS.low];
  context.save();
  context.fillStyle = "rgba(255, 255, 255, 0.93)";
  context.strokeStyle = "rgba(49, 52, 54, 0.82)";
  context.lineWidth = 1;
  context.fillRect(x, y, boxWidth, boxHeight);
  context.strokeRect(x + 0.5, y + 0.5, boxWidth - 1, boxHeight - 1);
  context.fillStyle = "#202427";
  context.font = "600 12px Arial, sans-serif";
  context.textAlign = "left";
  context.fillText("LD (r²)", x + 10, y + 17);
  context.fillStyle = "#6f7477";
  context.font = "9px Arial, sans-serif";
  context.fillText(status?.available ? "1000G Phase 3 ALL" : "LD unavailable", x + 10, y + 30);
  const barX = x + 14;
  const barY = y + 39;
  const segmentHeight = 14;
  colors.forEach((color, index) => {
    context.fillStyle = color;
    context.fillRect(barX, barY + index * segmentHeight, 19, segmentHeight + 0.5);
  });
  context.strokeStyle = "#313437";
  context.strokeRect(barX + 0.5, barY + 0.5, 18, segmentHeight * 5 - 1);
  context.fillStyle = "#272b2e";
  context.font = "11px Arial, sans-serif";
  ["1", "0.8", "0.6", "0.4", "0.2", "0"].forEach((label, index) => {
    context.fillText(label, barX + 25, barY + index * segmentHeight + 4);
  });
  drawPoint(context, x + 18, y + 126, manhattanPointStyle(1, true), "diamond", 1);
  context.fillStyle = "#272b2e";
  context.font = "11px Arial, sans-serif";
  context.fillText("LD ref", x + 31, y + 130);
  drawPoint(context, x + 17, y + 148, { fill: "#777", stroke: "#555", radius: 3.5 }, "triangle-up", 1);
  context.fillText("β > 0", x + 29, y + 152);
  drawPoint(context, x + 17, y + 166, { fill: "#777", stroke: "#555", radius: 3.5 }, "triangle-down", 1);
  context.fillText("β < 0", x + 29, y + 170);
  drawPoint(context, x + 17, y + 184, { fill: "#777", stroke: "#555", radius: 3.5 }, "circle", 1);
  context.fillText("no β", x + 29, y + 188);
  context.restore();
}

function drawManhattan(track, options) {
  const context = options.context;
  const height = Math.max(1, options.pixelHeight - 1);
  const range = ensureTrackRange(track);
  const minimum = range.min;
  const maximum = range.max;

  if (track.background) {
    context.save();
    context.fillStyle = track.background;
    context.fillRect(0, 0, options.pixelWidth, options.pixelHeight);
    context.restore();
  }
  drawHorizontalGuides(context, options.pixelWidth, height, range);

  const bpEnd = options.bpStart + options.pixelWidth * options.bpPerPixel + 1;
  let leadFeature;
  let leadValue = Number.NEGATIVE_INFINITY;
  for (const feature of options.features || []) {
    if (feature.start < options.bpStart) continue;
    if (feature.start > bpEnd) break;
    const value = manhattanValue(track, feature);
    if (!Number.isFinite(value)) continue;
    const x = Math.round((feature.start - options.bpStart) / options.bpPerPixel);
    const rSquared = featureR2(feature);
    const isReference = feature.genomeCanvasIsLDReference === true;
    const style = manhattanPointStyle(rSquared, isReference);
    const y = clamp(height - ((value - minimum) / (maximum - minimum)) * height, style.radius + 1, height - style.radius);
    drawPoint(context, x, y, style, manhattanShape(feature, isReference), Number.isFinite(options.alpha) ? options.alpha : 0.92);
    feature.px = x;
    feature.py = y;
    if (value > leadValue) {
      leadFeature = feature;
      leadValue = value;
    }
  }

  if (leadFeature) drawLeadLabel(context, leadFeature, leadValue, options.pixelWidth);
  context.save();
  context.strokeStyle = "rgba(96, 104, 108, 0.34)";
  context.lineWidth = 1;
  context.beginPath();
  context.moveTo(0, height);
  context.lineTo(options.pixelWidth, height);
  context.stroke();
  context.restore();
  drawLDLegend(context, options.pixelWidth, track.__genomeCanvasLDStatus);
}

export function installManhattanRenderer(track) {
  const format = String(track?.format || track?.config?.format || "").toLowerCase();
  if ((track?.type !== "gwas" && format !== "gwas") || track.__genomeCanvasManhattanRenderer) return false;
  if (typeof track.draw !== "function") return false;

  const originalAutoscale = track.doAutoscale;
  if (typeof originalAutoscale === "function") {
    track.doAutoscale = function doAutoscale(features) {
      const range = originalAutoscale.call(this, features);
      this.dataRange = normalizedManhattanRange(range);
      return this.dataRange;
    };
  }
  const originalGetFeatures = track.getFeatures;
  if (typeof originalGetFeatures === "function" && track.config?.ldEndpoint) {
    track.getFeatures = async function getFeatures(...args) {
      const features = await originalGetFeatures.apply(this, args);
      return fetchLDForFeatures(this, features);
    };
  }
  track.dataRange = normalizedManhattanRange(track.dataRange);
  track.draw = function draw(options) {
    return drawManhattan(this, options);
  };
  track.__genomeCanvasManhattanRenderer = true;
  if (track.config) track.config.genomeCanvasManhattan = true;
  return true;
}
