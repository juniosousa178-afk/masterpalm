/** Pure legacy metadata bootstrap for consignment eligibility.
 * Writes only stockKind / stockRevision / stock_catalog_dependencies.
 * Never mutates quantities, prices, names, identities, sales, or finance.
 * Does not activate stock_catalog_control.
 */
import {inferStockKind, isMap, quantity, normalizeStock} from './catalogStockProjection.js';
import {classifyConsignmentProduct, evaluateConsignmentPickerEligibility} from './consignmentStock.js';
import {CODES} from './consignmentProtocol.js';

export const CLASSES = Object.freeze({
  ALREADY_SAFE: 'A',
  LEGACY_SIMPLE_BOOTSTRAPPABLE: 'B',
  LEGACY_VARIATION_BOOTSTRAPPABLE: 'C',
  UNSAFE_AMBIGUOUS: 'D',
  GRADE: 'E',
  COMBO: 'F',
  INVALID_STOCK: 'G',
  CONFLICT: 'H',
  ZERO_STOCK: 'I',
  OTHER_UNSUPPORTED: 'J',
});

const nonempty = (v) => isMap(v) && Object.keys(v).length > 0;

function asNonNegInt(value) {
  if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) return value;
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    const n = Number(value);
    if (Number.isSafeInteger(n) && n >= 0) return n;
  }
  return null;
}

function snapshotQty(stock) {
  return {
    quantidade: stock?.quantidade ?? null,
    variacoes: structuredClone(stock?.variacoes ?? null),
    estoquePorTamanho: structuredClone(stock?.estoquePorTamanho ?? null),
    estoquePorCor: structuredClone(stock?.estoquePorCor ?? null),
  };
}

function qtySnapshotsEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function hasValidDependency(dep) {
  return !!dep && Array.isArray(dep.comboIds);
}

function hasValidRevision(stock) {
  try {
    quantity(stock?.stockRevision);
    return true;
  } catch {
    return false;
  }
}

function projectedStock(stock, kind, revision) {
  return {...stock, stockKind: kind, stockRevision: revision};
}

/**
 * Classify one product for consignment legacy bootstrap.
 * @returns {{classification:string, reason:string, kind?:string, bootstrappable:boolean, alreadySafe:boolean, zeroStock:boolean, writes:object|null, qtyBefore:object}}
 */
export function classifyLegacyConsignmentProduct({
  lojaId,
  productId,
  stock,
  draft,
  dependency,
  tombstone,
} = {}) {
  const qtyBefore = snapshotQty(stock);
  const base = {
    productId,
    lojaId,
    classification: CLASSES.OTHER_UNSUPPORTED,
    reason: '',
    kind: null,
    bootstrappable: false,
    alreadySafe: false,
    zeroStock: false,
    writes: null,
    qtyBefore,
  };

  if (!stock || !productId) {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'PRODUCT_NOT_FOUND'};
  }
  const claimed = String(stock.lojaId || stock.storeId || draft?.lojaId || draft?.storeId || '').trim();
  if (claimed && claimed !== lojaId) {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'CROSS_STORE'};
  }
  if (tombstone?.p === true || stock.pendingSoftDelete === true) {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'TOMBSTONE'};
  }
  if (stock.ativo === false) {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'INACTIVE'};
  }
  if (stock.pendingStockOperationId || stock.stockConflict === true) {
    return {...base, classification: CLASSES.CONFLICT, reason: 'PENDING_OR_CONFLICT'};
  }
  if (!draft) {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'MISSING_DRAFT'};
  }

  // Combo signals before inference
  if (stock.tipoProduto === 'combo' || (Array.isArray(stock.itensCombo) && stock.itensCombo.length)
      || stock.stockKind === 'combo') {
    return {...base, classification: CLASSES.COMBO, reason: 'COMBO', kind: 'combo'};
  }

  let inferred;
  try {
    inferred = stock.stockKind && ['simple', 'variation', 'combo'].includes(stock.stockKind)
      ? stock.stockKind
      : inferStockKind(stock);
  } catch {
    return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: 'INFER_KIND_FAILED'};
  }

  if (inferred === 'combo') {
    return {...base, classification: CLASSES.COMBO, reason: 'COMBO', kind: 'combo'};
  }

  const revisionMissing = stock.stockRevision == null;
  let revision;
  if (revisionMissing) {
    revision = 0;
  } else {
    try {
      revision = quantity(stock.stockRevision);
    } catch {
      return {...base, classification: CLASSES.INVALID_STOCK, reason: 'INVALID_STOCK_REVISION'};
    }
  }

  // Attempt classification with projected metadata (no qty rewrite in plan).
  const candidate = projectedStock(stock, inferred, revision);
  let classified;
  try {
    classified = classifyConsignmentProduct(candidate);
  } catch (error) {
    const code = error?.consignmentCode || '';
    const msg = String(error?.message || '');
    if (code === CODES.CONSIGNMENT_GRADE_NOT_SUPPORTED || /grade/i.test(msg)) {
      return {...base, classification: CLASSES.GRADE, reason: 'GRADE', kind: 'grade'};
    }
    if (/combo/i.test(msg)) {
      return {...base, classification: CLASSES.COMBO, reason: 'COMBO', kind: 'combo'};
    }
    if (/ambiguous|variation data|Canonical variacoes|Unsupported stock/i.test(msg)) {
      return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: msg || 'AMBIGUOUS'};
    }
    if (/Invalid canonical|quantity|migration required/i.test(msg)) {
      return {...base, classification: CLASSES.INVALID_STOCK, reason: msg || 'INVALID_STOCK'};
    }
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: msg || 'CLASSIFY_FAILED'};
  }

  // Prove authoritative qty without rewriting stock document body.
  let normalized;
  try {
    normalized = normalizeStock(candidate);
  } catch (error) {
    return {...base, classification: CLASSES.INVALID_STOCK, reason: error.message || 'NORMALIZE_FAILED'};
  }

  const qty = asNonNegInt(stock.quantidade);
  if (qty == null) {
    return {...base, classification: CLASSES.INVALID_STOCK, reason: 'UNPROVEN_QUANTITY'};
  }
  // After normalize, quantidade must stay coherent with persisted authoritative qty for simple;
  // for variation, every canonical cell must remain identical (we never rewrite cells).
  if (classified.kind === 'simple') {
    if (nonempty(stock.variacoes) || nonempty(stock.estoquePorTamanho) || nonempty(stock.estoquePorCor)
        || (Array.isArray(stock.tamanhos) && stock.tamanhos.some((v) => String(v).trim()))
        || (Array.isArray(stock.cores) && stock.cores.some((v) => String(v).trim()))) {
      return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: 'SIMPLE_WITH_VARIATION_PROJECTION'};
    }
    if (normalized.quantidade !== qty) {
      return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: 'QTY_NORMALIZE_MISMATCH'};
    }
  } else if (classified.kind === 'variation') {
    if (!nonempty(stock.variacoes)) {
      return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: 'MISSING_CANONICAL_VARIACOES'};
    }
    // Do not rebuild variation maps — only allow metadata when normalize preserves cell structure
    // and aggregate equals persisted quantidade when quantidade is present.
    if (!qtySnapshotsEqual(snapshotQty(stock), {
      quantidade: stock.quantidade,
      variacoes: stock.variacoes,
      estoquePorTamanho: stock.estoquePorTamanho ?? null,
      estoquePorCor: stock.estoquePorCor ?? null,
    })) {
      return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: 'VARIATION_SNAPSHOT_UNSTABLE'};
    }
    if (asNonNegInt(normalized.quantidade) == null) {
      return {...base, classification: CLASSES.INVALID_STOCK, reason: 'VARIATION_AGGREGATE_INVALID'};
    }
    // Persisted quantidade must match normalized aggregate when both exist.
    if (qty !== normalized.quantidade) {
      return {...base, classification: CLASSES.UNSAFE_AMBIGUOUS, reason: 'VARIATION_AGGREGATE_MISMATCH'};
    }
  } else if (classified.kind === 'grade') {
    return {...base, classification: CLASSES.GRADE, reason: 'GRADE', kind: 'grade', bootstrappable: false};
  } else {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'UNSUPPORTED_KIND'};
  }

  const needsKind = stock.stockKind !== classified.kind;
  const needsRevision = revisionMissing;
  const needsDep = !hasValidDependency(dependency);
  const alreadySafe = !needsKind && hasValidRevision(stock) && hasValidDependency(dependency);

  const zeroStock = qty === 0;
  if (alreadySafe) {
    return {
      ...base,
      classification: zeroStock ? CLASSES.ZERO_STOCK : CLASSES.ALREADY_SAFE,
      reason: zeroStock ? 'ALREADY_SAFE_ZERO_STOCK' : 'ALREADY_SAFE',
      kind: classified.kind,
      alreadySafe: true,
      zeroStock,
      bootstrappable: false,
      writes: null,
    };
  }

  // Bootstrappable legacy metadata only.
  if (classified.kind !== 'simple' && classified.kind !== 'variation') {
    return {...base, classification: CLASSES.OTHER_UNSUPPORTED, reason: 'UNSUPPORTED_KIND', kind: classified.kind};
  }

  const writes = {
    stockPatch: {},
    dependency: needsDep ? {comboIds: []} : null,
  };
  if (needsKind) writes.stockPatch.stockKind = classified.kind;
  if (needsRevision) writes.stockPatch.stockRevision = 0;
  if (!Object.keys(writes.stockPatch).length) writes.stockPatch = null;

  return {
    ...base,
    classification: classified.kind === 'simple'
      ? CLASSES.LEGACY_SIMPLE_BOOTSTRAPPABLE
      : CLASSES.LEGACY_VARIATION_BOOTSTRAPPABLE,
    reason: classified.kind === 'simple' ? 'LEGACY_SIMPLE' : 'LEGACY_VARIATION',
    kind: classified.kind,
    bootstrappable: true,
    zeroStock,
    writes,
  };
}

/** Apply planned metadata onto in-memory stock/dep copies (for tests / dry eligibility). */
export function applyLegacyBootstrapPlan(stock, dependency, plan) {
  if (!plan?.bootstrappable || !plan.writes) {
    return {stock, dependency, mutated: false};
  }
  const nextStock = {...stock};
  if (plan.writes.stockPatch) Object.assign(nextStock, plan.writes.stockPatch);
  const nextDep = plan.writes.dependency
    ? {...(dependency || {}), ...plan.writes.dependency}
    : dependency;
  return {stock: nextStock, dependency: nextDep, mutated: true};
}

export function evaluateAfterBootstrap({lojaId, productId, stock, draft, dependency, tombstone}) {
  return evaluateConsignmentPickerEligibility({
    lojaId, productId, stock, draft, dependency, tombstone,
  });
}

export function assertQtyUnchanged(before, afterStock) {
  const after = snapshotQty(afterStock);
  if (!qtySnapshotsEqual(before, after)) {
    throw new Error('STOCK_QTY_MUTATION_DETECTED');
  }
  return true;
}

export {snapshotQty, qtySnapshotsEqual, hasValidDependency};
