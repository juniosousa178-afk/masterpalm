/**
 * Global stock health classifier (pure, unit-testable).
 *
 * Operational stock health EXCLUDES full-product tombstones (exclusao_produto.p=true).
 * C2 LEGACY_SIZE_METADATA does NOT imply physical recount.
 */

export function cellEntries(variacoes) {
  const cells = [];
  if (!variacoes || typeof variacoes !== 'object') return cells;
  for (const [size, colors] of Object.entries(variacoes)) {
    if (!colors || typeof colors !== 'object') continue;
    for (const [color, raw] of Object.entries(colors)) {
      if (color === '__custoUnitario') continue;
      let q = 0;
      if (typeof raw === 'number') q = raw;
      else if (raw && typeof raw === 'object') {
        q = Object.entries(raw)
          .filter(([k]) => k !== '__custoUnitario')
          .reduce((s, [, v]) => s + (typeof v === 'number' ? v : 0), 0);
      }
      cells.push({size, color, qty: q, key: `${size}|${color}`});
    }
  }
  return cells;
}

export function cellSum(variacoes) {
  return cellEntries(variacoes).reduce((s, c) => s + (Number.isFinite(c.qty) ? c.qty : 0), 0);
}

export function sizeAggSum(estoquePorTamanho) {
  if (!estoquePorTamanho || typeof estoquePorTamanho !== 'object') return 0;
  return Object.values(estoquePorTamanho).reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0);
}

export function hasMetadataGradeShape(p) {
  const sizes = Array.isArray(p.tamanhos) && p.tamanhos.length;
  const colors = Array.isArray(p.cores) && p.cores.length;
  const ept = p.estoquePorTamanho && Object.keys(p.estoquePorTamanho).length;
  const epc = p.estoquePorCor && Object.keys(p.estoquePorCor).length;
  return Boolean(sizes || colors || ept || epc);
}

export function hasCanonicalCells(p) {
  return cellEntries(p.variacoes).length > 0;
}

export function hasGradeShape(p) {
  return hasCanonicalCells(p) || hasMetadataGradeShape(p);
}

export function isFullProductTombstone(tomb) {
  return tomb != null && tomb.p === true;
}

/**
 * Sum quantidade only for products that are NOT full-product tombstoned.
 */
export function computeOperationalQty(products, tombsById = new Map()) {
  let operational = 0;
  let archivedQty = 0;
  let archivedCount = 0;
  let allQty = 0;
  for (const p of products) {
    const agg = typeof p.quantidade === 'number' ? p.quantidade : 0;
    allQty += agg;
    const tomb = tombsById.get(p.id) || tombsById.get(p.productId);
    if (isFullProductTombstone(tomb)) {
      archivedQty += agg;
      archivedCount += 1;
      continue;
    }
    operational += agg;
  }
  return {
    REMOTE_ALL_DOCS_QTY: allQty,
    REMOTE_OPERATIONAL_QTY: operational,
    REMOTE_ARCHIVED_TOMBSTONED_QTY: archivedQty,
    REMOTE_ARCHIVED_TOMBSTONED_PRODUCT_COUNT: archivedCount,
  };
}

/**
 * Structural / mismatch classification for a single product.
 * Returns null when no mismatch / not operational interest.
 *
 * Wire classes:
 *   A  = CLASS_A projection repair (aggregate != cell sum, cells valid)
 *   B  = cell/size inconsistency
 *   C1 = valid simple (not emitted as mismatch)
 *   C2 = LEGACY_SIZE_METADATA_ONLY (STRUCTURAL_LEGACY)
 *   C3 = canonical structural corruption / qty unclear
 *   C4 = full tombstone (not operational)
 *   C5 = uncertain
 *   D  = residual unclassified mismatch (legacy bucket → treat as C5-ish)
 */
export function classifyProductStructure(p, tomb = null) {
  const agg = typeof p.quantidade === 'number' ? p.quantidade : 0;
  const cells = cellEntries(p.variacoes);
  const sum = cells.reduce((s, c) => s + c.qty, 0);
  const eptSum = sizeAggSum(p.estoquePorTamanho);

  if (isFullProductTombstone(tomb)) {
    return {
      CLASS: 'C4',
      STRUCTURAL_LABEL: 'OBSOLETE_FULL_TOMBSTONE',
      OPERATIONAL: false,
      PHYSICAL_RECOUNT: false,
      AGGREGATE_QTY: agg,
      CANONICAL_CELL_SUM: sum,
      DELTA: agg - sum,
    };
  }

  // Class A: canonical cells present and aggregate disagrees
  if (cells.length > 0 && sum !== agg) {
    const positive = cells.filter((c) => c.qty > 0);
    // B: size aggregate also disagrees with both
    if (eptSum > 0 && eptSum !== sum && eptSum !== agg && sum !== agg) {
      return {
        CLASS: 'B',
        STRUCTURAL_LABEL: 'CELL_SIZE_INCONSISTENCY',
        OPERATIONAL: true,
        PHYSICAL_RECOUNT: false,
        AGGREGATE_QTY: agg,
        CANONICAL_CELL_SUM: sum,
        DELTA: agg - sum,
        PROJECTION_REPAIR_CANDIDATE: positive.length > 0 || cells.length > 0,
      };
    }
    return {
      CLASS: 'A',
      STRUCTURAL_LABEL: 'CLASS_A_PROJECTION_REPAIR',
      OPERATIONAL: true,
      PHYSICAL_RECOUNT: false,
      AGGREGATE_QTY: agg,
      CANONICAL_CELL_SUM: sum,
      DELTA: agg - sum,
      PROJECTION_REPAIR_CANDIDATE: true,
    };
  }

  // C1: simple stock — aggregate authoritative, cells not required
  if (!hasGradeShape(p) && cells.length === 0) {
    return {
      CLASS: 'C1',
      STRUCTURAL_LABEL: 'VALID_SIMPLE_STOCK',
      OPERATIONAL: true,
      PHYSICAL_RECOUNT: false,
      AGGREGATE_QTY: agg,
      CANONICAL_CELL_SUM: 0,
      DELTA: 0,
    };
  }

  // C2: legacy size/color metadata, no canonical cells, qty still demonstrable
  if (cells.length === 0 && hasMetadataGradeShape(p)) {
    const qtyDemonstrable = agg > 0 || eptSum > 0;
    if (qtyDemonstrable) {
      return {
        CLASS: 'C2',
        STRUCTURAL_LABEL: 'LEGACY_SIZE_METADATA_ONLY',
        OPERATIONAL: true,
        PHYSICAL_RECOUNT: false,
        AGGREGATE_QTY: agg,
        CANONICAL_CELL_SUM: 0,
        DELTA: agg,
        STRUCTURAL_LEGACY: true,
      };
    }
    // metadata present but zero everywhere → uncertain empty grade shell
    return {
      CLASS: 'C5',
      STRUCTURAL_LABEL: 'UNCERTAIN_EMPTY_GRADE_SHELL',
      OPERATIONAL: true,
      PHYSICAL_RECOUNT: false,
      AGGREGATE_QTY: agg,
      CANONICAL_CELL_SUM: 0,
      DELTA: 0,
    };
  }

  // cells present and match aggregate → healthy grade
  if (cells.length > 0 && sum === agg) {
    return {
      CLASS: 'C1',
      STRUCTURAL_LABEL: 'VALID_GRADE_STOCK',
      OPERATIONAL: true,
      PHYSICAL_RECOUNT: false,
      AGGREGATE_QTY: agg,
      CANONICAL_CELL_SUM: sum,
      DELTA: 0,
    };
  }

  // C3: quantity authority unclear (no cells, no usable metadata, non-zero or nonsense)
  if (cells.length === 0 && !hasMetadataGradeShape(p) && !Number.isFinite(agg)) {
    return {
      CLASS: 'C3',
      STRUCTURAL_LABEL: 'CANONICAL_STRUCTURAL_CORRUPTION',
      OPERATIONAL: true,
      PHYSICAL_RECOUNT: true,
      AGGREGATE_QTY: agg,
      CANONICAL_CELL_SUM: 0,
      DELTA: 0,
    };
  }

  return {
    CLASS: 'C5',
    STRUCTURAL_LABEL: 'UNCERTAIN',
    OPERATIONAL: true,
    PHYSICAL_RECOUNT: false,
    AGGREGATE_QTY: agg,
    CANONICAL_CELL_SUM: sum,
    DELTA: agg - sum,
  };
}

/**
 * Whether this structural result should appear in operational mismatch list
 * (drives repair candidates / recount — NOT C1 healthy, NOT C4 archived).
 */
export function isOperationalMismatch(classified) {
  if (!classified || classified.OPERATIONAL === false) return false;
  if (classified.CLASS === 'C1') return false;
  if (classified.CLASS === 'C4') return false;
  // C2 is structural legacy — recorded as informational mismatch, not repair/recount
  if (classified.CLASS === 'A' || classified.CLASS === 'B') return true;
  if (classified.CLASS === 'C2') return true; // listed but not recount
  if (classified.CLASS === 'C3') return true;
  if (classified.CLASS === 'C5' && classified.DELTA !== 0) return true;
  return false;
}

/**
 * PHYSICAL_RECOUNT_REQUIRED only when operational qty cannot be established
 * from any trusted source. C2 must NOT imply recount. C4 excluded.
 */
export function needsPhysicalRecount(classifiedList) {
  return classifiedList.some((c) => c && c.OPERATIONAL !== false && c.PHYSICAL_RECOUNT === true);
}

export function physicalRecountCount(classifiedList) {
  return classifiedList.filter((c) => c && c.OPERATIONAL !== false && c.PHYSICAL_RECOUNT === true).length;
}

/**
 * Sale binding classes (wire).
 * Only UNRECOVERABLE_BINDING / AMBIGUOUS_BINDING raise operational risk.
 */
export function classifySaleBinding(sale, opsById) {
  const saleId = sale.id;
  const bound = String(sale.stockOperationId || '').trim();
  const self = opsById.get(saleId);
  if (bound) {
    const op = opsById.get(bound);
    if (op && op.status === 'applied' && (op.kind === 'sale' || op.kind == null)) {
      return 'MODERN_EXPLICIT_BINDING';
    }
    if (op && op.status === 'applied') return 'MODERN_EXPLICIT_BINDING';
    if (bound === saleId && self && self.status === 'applied') {
      return 'BACKEND_RESOLVABLE_BINDING';
    }
    if (!op) return 'UNRECOVERABLE_BINDING';
    return 'AMBIGUOUS_BINDING';
  }
  if (self && self.status === 'applied' && (self.kind === 'sale' || self.kind == null)) {
    return 'BACKEND_RESOLVABLE_BINDING';
  }
  if (self && self.status === 'applied') return 'LEGACY_NO_EXPLICIT_BINDING_SAFE';
  // No explicit binding and no op doc: legacy pre-protocol — safe historical
  return 'LEGACY_NO_EXPLICIT_BINDING_SAFE';
}

export function saleBindingRaisesOperationalRisk(cls) {
  return cls === 'UNRECOVERABLE_BINDING' || cls === 'AMBIGUOUS_BINDING';
}

/**
 * Lineage: OP_DOC_MISSING is historical info unless marked active dependency.
 */
export function classifyLineageAnomaly(reason, {activeWorkflowDepends = false} = {}) {
  if (reason === 'OP_DOC_MISSING' && !activeWorkflowDepends) {
    return {
      ACTIVE_RISK: false,
      LABEL: 'HISTORICAL_OP_DOC_MISSING',
    };
  }
  if (reason === 'EDITORIAL_STAMPED_AS_STOCK_LINEAGE') {
    return {ACTIVE_RISK: false, LABEL: 'HISTORICAL_EDITORIAL_LINEAGE'};
  }
  if (reason === 'NON_STOCK_EFFECT_KIND_ON_LINEAGE') {
    return {ACTIVE_RISK: false, LABEL: 'HISTORICAL_NON_STOCK_LINEAGE'};
  }
  return {ACTIVE_RISK: true, LABEL: reason || 'ACTIVE_LINEAGE_RISK'};
}

/**
 * Stale T/V tombstones overlapping live positive cells → informational by default
 * (runtime KEEP for positive cells).
 */
export function classifyStaleTombstoneOverlap() {
  return {
    LABEL: 'INFORMATIONAL_HISTORICAL_METADATA',
    ACTIVE_RISK: false,
  };
}

/**
 * Tenant operational health:
 *   HEALTHY | REVIEW | BLOCKED
 */
export function riskForTenant(t) {
  if ((t.CRITICAL_HINTS || []).length) return 'BLOCKED';
  if ((t.TRUE_PHYSICAL_RECOUNT_COUNT || 0) > 0) return 'BLOCKED';
  if ((t.UNRECOVERABLE_BINDING_COUNT || 0) > 0 || (t.AMBIGUOUS_BINDING_COUNT || 0) > 0) {
    return 'BLOCKED';
  }
  // Active pending / active lineage = blocked workflow
  const activePending = (t.PENDING_COUNT || 0) > 0;
  const activeLineage = (t.ACTIVE_LINEAGE_RISK_COUNT || 0) > 0;
  if (activePending || activeLineage) return 'BLOCKED';

  // Class A/B: qty demonstrable via cells but aggregate wrong → REVIEW (repair candidate)
  const hasClassA = (t.CLASS_A_PROJECTION_COUNT || 0) > 0;
  const hasClassB = (t.CLASS_B_COUNT || 0) > 0;
  if (hasClassA || hasClassB) return 'REVIEW';

  // C2 legacy metadata, historical OP_DOC_MISSING, informational stale tombs, C5 without
  // physical-recount flag: quantity remains demonstrable → HEALTHY (not operational risk)
  return 'HEALTHY';
}

/** @deprecated alias — prefer riskForTenant HEALTHY/REVIEW/BLOCKED */
export function legacyRiskLabel(health) {
  switch (health) {
    case 'HEALTHY': return 'CLEAN';
    case 'REVIEW': return 'HISTORICAL_DATA_REVIEW_REQUIRED';
    case 'BLOCKED': return 'PHYSICAL_RECOUNT_REQUIRED';
    default: return health;
  }
}

export function tombstoneKeys(tomb) {
  const keys = [];
  if (!tomb) return keys;
  if (tomb.v && typeof tomb.v === 'object') {
    for (const [k, val] of Object.entries(tomb.v)) {
      if (val === true || val === 1 || val === 'true') keys.push(String(k));
    }
  }
  for (const [k, val] of Object.entries(tomb)) {
    if (k === 'v' || k === 'p' || k === 'productId' || k === 'operationId' || k === 'at' || k === 'deletedAt') continue;
    if (val === true || val === 1) {
      if (k.startsWith('v.') || k.startsWith('T::') || k.startsWith('V::') || k.includes('|')) {
        keys.push(k.replace(/^v\./, ''));
      }
    }
  }
  return keys;
}

export function normalizeTombKey(k) {
  let s = String(k || '').trim();
  if (s.startsWith('V::')) s = s.slice(3);
  if (s.startsWith('T::')) s = s.slice(3);
  return s.toLowerCase().replace(/\s+/g, ' ');
}
