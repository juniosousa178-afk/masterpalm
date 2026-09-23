/**
 * MASTERPALM — Global multi-tenant stock health audit (READ-ONLY).
 *
 * Classifier refined: operational qty excludes exclusao_produto.p=true.
 * C2 legacy size metadata does NOT imply physical recount.
 * Risk: HEALTHY | REVIEW | BLOCKED
 *
 * COMMIT/PUSH handled separately after tests. DEPLOY=false. No writes.
 */
import {execFileSync} from 'node:child_process';
import {mkdirSync, writeFileSync, existsSync, readFileSync, readdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  cellEntries,
  cellSum,
  hasGradeShape,
  isFullProductTombstone,
  computeOperationalQty,
  classifyProductStructure,
  isOperationalMismatch,
  physicalRecountCount,
  classifySaleBinding,
  saleBindingRaisesOperationalRisk,
  classifyLineageAnomaly,
  classifyStaleTombstoneOverlap,
  riskForTenant,
  tombstoneKeys,
  normalizeTombKey,
} from './lib/global_stock_health_classifier.mjs';

const PROJECT = 'masterpalm-58c46';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '../..');
const OUT_DIR = join(ROOT, 'artifacts/global_stock_health');
const CLIENT_BASELINE = '1.0.104+118';
const CONCURRENCY = Number(process.env.AUDIT_CONCURRENCY || 4);

function token() {
  if (process.env.GOOGLE_CLOUD_TOKEN) return process.env.GOOGLE_CLOUD_TOKEN.trim();
  const helper = join(__dirname, '_gcloud_access_token.ps1');
  const out = execFileSync(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', helper],
    {encoding: 'utf8', windowsHide: true, maxBuffer: 2 * 1024 * 1024},
  );
  const t = String(out || '').trim().split(/\r?\n/).filter(Boolean).pop();
  if (!t) throw new Error('gcloud token empty');
  return t;
}

function decodeValue(v) {
  if (v == null) return null;
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in v) {
    const out = {};
    for (const [k, val] of Object.entries(v.mapValue.fields || {})) out[k] = decodeValue(val);
    return out;
  }
  return null;
}
function decodeDoc(doc) {
  if (!doc?.name) return null;
  const data = {};
  for (const [k, v] of Object.entries(doc.fields || {})) data[k] = decodeValue(v);
  return {id: doc.name.split('/').pop(), ...data};
}

async function getJson(url, init = {}) {
  const res = await fetch(url, init);
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = {raw: text.slice(0, 500)}; }
  if (!res.ok) throw new Error(`${res.status} ${url} ${text.slice(0, 300)}`);
  return json;
}

async function listCollection(auth, path, {pageSize = 300, maxDocs = Infinity} = {}) {
  const out = [];
  let pageToken = '';
  do {
    const url = new URL(`${BASE}/${path}`);
    url.searchParams.set('pageSize', String(pageSize));
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const json = await getJson(url.toString(), {headers: {Authorization: `Bearer ${auth}`}});
    for (const d of json.documents || []) {
      out.push(decodeDoc(d));
      if (out.length >= maxDocs) return out;
    }
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return out;
}

async function getDoc(auth, path) {
  try {
    const json = await getJson(`${BASE}/${path}`, {headers: {Authorization: `Bearer ${auth}`}});
    return decodeDoc(json);
  } catch (e) {
    if (String(e.message || '').startsWith('404')) return null;
    throw e;
  }
}

async function mapPool(items, concurrency, fn) {
  const results = new Array(items.length);
  let i = 0;
  async function worker() {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
    }
  }
  await Promise.all(Array.from({length: Math.min(concurrency, items.length)}, () => worker()));
  return results;
}

function loadLocalArtifactHints() {
  const hints = Object.create(null);
  const candidates = [
    join(ROOT, 'artifacts/mirjoias_final_stock'),
    join(ROOT, 'artifacts/estoque'),
    join(ROOT, 'artifacts/nathy_stock_fix'),
    join(ROOT, 'artifacts/nathy_aggregate_projection'),
  ];
  for (const dir of candidates) {
    if (!existsSync(dir)) continue;
    for (const name of readdirSync(dir)) {
      if (!name.endsWith('.json')) continue;
      try {
        const j = JSON.parse(readFileSync(join(dir, name), 'utf8'));
        const store = j.STORE_ID || j.STORE || j.lojaId || null;
        if (!store) continue;
        const h = hints[store] || (hints[store] = {
          LOCAL_UNTRACKED_MUTATION: 0,
          PRESERVED_UNTRACKED_CONFLICT: 0,
          REMOTE_NEWER_CACHE_STALE: 0,
          sources: [],
        });
        h.LOCAL_UNTRACKED_MUTATION += Number(j.LOCAL_UNTRACKED_MUTATION_COUNT || j.ACTIVE_LOCAL_UNTRACKED_MUTATION_COUNT || 0);
        h.PRESERVED_UNTRACKED_CONFLICT += Number(j.PRESERVED_UNTRACKED_CONFLICT_COUNT || 0);
        h.REMOTE_NEWER_CACHE_STALE += Number(j.REMOTE_NEWER_CACHE_STALE_COUNT || 0);
        if (j.COUNTS) {
          h.LOCAL_UNTRACKED_MUTATION += Number(j.COUNTS.LOCAL_UNTRACKED_MUTATION_COUNT || 0);
          h.PRESERVED_UNTRACKED_CONFLICT += Number(j.COUNTS.PRESERVED_UNTRACKED_CONFLICT_COUNT || 0);
          h.REMOTE_NEWER_CACHE_STALE += Number(j.COUNTS.REMOTE_NEWER_CACHE_STALE_COUNT || 0);
        }
        h.sources.push(name);
      } catch { /* ignore */ }
    }
  }
  return hints;
}

async function auditStore(auth, store, localHints) {
  const storeId = store.id;
  const base = `lojas/${storeId}`;
  let control = null;
  try {
    control = await getDoc(auth, `${base}/stock_catalog_control/state`);
  } catch { control = null; }
  const legacyCompat = !control || control.mode !== 'ACTIVE' ? 'NO_CONTROL' : 'ACTIVE';

  let products = [];
  let tombs = [];
  let ops = [];
  let sales = [];
  let listErrors = [];
  try { products = await listCollection(auth, `${base}/estoque_produtos`); }
  catch (e) { listErrors.push(`estoque_produtos:${e.message}`); }
  try { tombs = await listCollection(auth, `${base}/exclusao_produto`); }
  catch (e) { listErrors.push(`exclusao_produto:${e.message}`); }
  try { ops = await listCollection(auth, `${base}/stock_catalog_operations`); }
  catch (e) { listErrors.push(`stock_catalog_operations:${e.message}`); }
  try { sales = await listCollection(auth, `${base}/estoque_vendas`); }
  catch (e) { listErrors.push(`estoque_vendas:${e.message}`); }

  const opsById = new Map(ops.map((o) => [o.id, o]));
  const tombsById = new Map(tombs.map((t) => [t.id, t]));

  const qty = computeOperationalQty(products, tombsById);

  let cellSumOperational = 0;
  const mismatches = [];
  const classifiedAll = [];
  let pendingCount = 0;
  let orphanPending = 0;
  let duplicatePending = 0;
  let invalidPending = 0;
  const pendingSeen = new Map();
  const lineageAnomalies = [];
  let historicalLineage = 0;
  let activeLineageRisk = 0;
  const staleTombs = [];
  let editstockSuspect = 0;
  let classA = 0;
  let classB = 0;
  let classC2 = 0;
  let classC3 = 0;
  let classC4 = 0;
  let classC5 = 0;

  for (const p of products) {
    const tomb = tombsById.get(p.id);
    const classified = classifyProductStructure(p, tomb);
    classifiedAll.push(classified);

    if (classified.CLASS === 'A') classA++;
    else if (classified.CLASS === 'B') classB++;
    else if (classified.CLASS === 'C2') classC2++;
    else if (classified.CLASS === 'C3') classC3++;
    else if (classified.CLASS === 'C4') classC4++;
    else if (classified.CLASS === 'C5') classC5++;

    // Operational canonical cell sum excludes C4
    if (!isFullProductTombstone(tomb)) {
      const sum = cellSum(p.variacoes);
      const cells = cellEntries(p.variacoes);
      const agg = typeof p.quantidade === 'number' ? p.quantidade : 0;
      const canonicalForTotal = hasGradeShape(p) && cells.length > 0 ? sum : agg;
      cellSumOperational += canonicalForTotal;
    }

    if (isOperationalMismatch(classified)) {
      mismatches.push({
        PRODUCT_ID: p.id,
        CODE: p.codigoBarras || p.codigo || p.sku || null,
        NAME: p.nome || p.name || null,
        AGGREGATE_QTY: classified.AGGREGATE_QTY,
        CANONICAL_CELL_SUM: classified.CANONICAL_CELL_SUM,
        DELTA: classified.DELTA,
        STOCK_REVISION: p.stockRevision ?? null,
        STOCK_OPERATION_ID: p.stockOperationId ?? null,
        CLASS: classified.CLASS,
        STRUCTURAL_LABEL: classified.STRUCTURAL_LABEL,
        PHYSICAL_RECOUNT: classified.PHYSICAL_RECOUNT === true,
        PROJECTION_REPAIR_CANDIDATE: classified.PROJECTION_REPAIR_CANDIDATE === true,
      });
    }

    // pending only on operational products
    if (!isFullProductTombstone(tomb)) {
      if (p.pendingStockOperationId || p.stockConflict === true) {
        pendingCount++;
        const pid = String(p.pendingStockOperationId || '');
        if (pid) {
          pendingSeen.set(pid, (pendingSeen.get(pid) || 0) + 1);
          if (!opsById.has(pid)) orphanPending++;
          const op = opsById.get(pid);
          if (op && op.status && op.status !== 'pending' && op.status !== 'applied') invalidPending++;
        } else if (p.stockConflict === true) {
          invalidPending++;
        }
      }
    }

    // lineage — historical OP_DOC_MISSING is not active risk
    if (!isFullProductTombstone(tomb)) {
      const opId = String(p.stockOperationId || '').trim();
      if (opId) {
        const op = opsById.get(opId);
        let reason = null;
        if (!op) reason = 'OP_DOC_MISSING';
        else if (op.kind === 'editorial') reason = 'EDITORIAL_STAMPED_AS_STOCK_LINEAGE';
        else if (['tombstoneVariation', 'clearVariationTombstone'].includes(op.kind)) {
          reason = 'NON_STOCK_EFFECT_KIND_ON_LINEAGE';
        }
        if (reason) {
          const lin = classifyLineageAnomaly(reason, {activeWorkflowDepends: false});
          lineageAnomalies.push({
            PRODUCT_ID: p.id,
            STOCK_OPERATION_ID: opId,
            REASON: reason,
            LABEL: lin.LABEL,
            ACTIVE_RISK: lin.ACTIVE_RISK,
            OP_KIND: op?.kind ?? null,
          });
          if (lin.ACTIVE_RISK) activeLineageRisk++;
          else historicalLineage++;
        }
      }
    }

    // stale tombstones overlapping live positive cells → informational
    if (tomb && tomb.p !== true) {
      const tkeys = tombstoneKeys(tomb);
      if (tkeys.length) {
        const positive = cellEntries(p.variacoes).filter((c) => c.qty > 0);
        const liveQty = [];
        for (const c of positive) {
          const nk = normalizeTombKey(c.key);
          const hit = tkeys.some((tk) => {
            const ntk = normalizeTombKey(tk);
            return ntk === nk
              || ntk === normalizeTombKey(c.size)
              || ntk === `t::${normalizeTombKey(c.size)}`
              || ntk === normalizeTombKey(`V::${c.key}`);
          });
          if (hit) liveQty.push({key: c.key, qty: c.qty});
        }
        if (liveQty.length) {
          const staleMeta = classifyStaleTombstoneOverlap();
          staleTombs.push({
            PRODUCT_ID: p.id,
            NAME: p.nome || null,
            STALE_KEYS: tkeys,
            LIVE_CELL_QTY: liveQty,
            LABEL: staleMeta.LABEL,
            ACTIVE_RISK: staleMeta.ACTIVE_RISK,
          });
        }
      }
    }
  }

  for (const [, n] of pendingSeen) if (n > 1) duplicatePending += n - 1;

  // sale bindings
  const protocolActive = ops.some((o) => o.status === 'applied' && ['sale', 'restore', 'replace', 'adjust'].includes(o.kind));
  let modernExplicit = 0;
  let legacySafe = 0;
  let backendResolvable = 0;
  let unrecoverable = 0;
  let ambiguous = 0;
  let missingExplicit = 0;
  const badSales = [];
  const classCounts = {
    MODERN_EXPLICIT_BINDING: 0,
    LEGACY_NO_EXPLICIT_BINDING_SAFE: 0,
    BACKEND_RESOLVABLE_BINDING: 0,
    UNRECOVERABLE_BINDING: 0,
    AMBIGUOUS_BINDING: 0,
  };
  for (const sale of sales) {
    if (!String(sale.stockOperationId || '').trim()) missingExplicit++;
    const cls = classifySaleBinding(sale, opsById);
    classCounts[cls] = (classCounts[cls] || 0) + 1;
    if (cls === 'MODERN_EXPLICIT_BINDING') modernExplicit++;
    else if (cls === 'LEGACY_NO_EXPLICIT_BINDING_SAFE') legacySafe++;
    else if (cls === 'BACKEND_RESOLVABLE_BINDING') backendResolvable++;
    else if (cls === 'UNRECOVERABLE_BINDING') {
      unrecoverable++;
      badSales.push({SALE_ID: sale.id, CLASS: cls, STOCK_OPERATION_ID: sale.stockOperationId || null});
    } else if (cls === 'AMBIGUOUS_BINDING') {
      ambiguous++;
      badSales.push({SALE_ID: sale.id, CLASS: cls, STOCK_OPERATION_ID: sale.stockOperationId || null});
    }
  }

  const opStatusBad = ops.filter((o) => !o.status || !['applied', 'pending', 'failed', 'aborted'].includes(o.status)).length;
  const restores = ops.filter((o) => o.kind === 'restore');
  let restoreNoSource = 0;
  let sourceRestoredTwice = 0;
  const restoredByCount = new Map();
  for (const r of restores) {
    if (!r.sourceOperationId) restoreNoSource++;
    else if (opsById.get(r.sourceOperationId)?.restoredBy) {
      restoredByCount.set(r.sourceOperationId, (restoredByCount.get(r.sourceOperationId) || 0) + 1);
    }
  }
  for (const [, n] of restoredByCount) if (n > 1) sourceRestoredTwice++;
  const hashCounts = new Map();
  for (const o of ops) {
    if (o.requestHash && o.status === 'applied') {
      hashCounts.set(o.requestHash, (hashCounts.get(o.requestHash) || 0) + 1);
    }
  }
  let duplicateHashEffects = 0;
  for (const [, n] of hashCounts) if (n > 1) duplicateHashEffects += n - 1;

  let editstockSuspectLocal = 0;
  const adjusts = ops.filter((o) => o.kind === 'adjust' || o.kind === 'editstock' || o.kind === 'replace');
  for (const o of adjusts) {
    const items = Array.isArray(o.items) ? o.items : [];
    if (o.kind === 'adjust' && items.length === 0) editstockSuspectLocal++;
    const pids = items.map((i) => i?.productId).filter(Boolean);
    if (new Set(pids).size < pids.length) editstockSuspectLocal++;
  }
  editstockSuspect = editstockSuspectLocal;

  const local = localHints[storeId] || null;
  const localIssues = local
    ? (local.LOCAL_UNTRACKED_MUTATION + local.PRESERVED_UNTRACKED_CONFLICT + local.REMOTE_NEWER_CACHE_STALE)
    : 0;

  const CRITICAL_HINTS = [];
  if (duplicateHashEffects > 10) CRITICAL_HINTS.push('DUPLICATE_OP_HASH_EFFECTS');
  if (sourceRestoredTwice > 0) CRITICAL_HINTS.push('SOURCE_RESTORED_TWICE');
  if (classB > 5) CRITICAL_HINTS.push('MANY_CELL_INCONSISTENCIES');

  const TRUE_PHYSICAL_RECOUNT_COUNT = physicalRecountCount(classifiedAll);

  const t = {
    STORE_ID: storeId,
    DISPLAY_NAME: store.nome || store.name || storeId,
    ACTIVE: store.ativo === true ? true : store.ativo === false ? false : null,
    CLIENT_SCHEMA_VERSION: null,
    LEGACY_COMPAT: legacyCompat,
    PRODUCT_COUNT: products.length,
    REMOTE_ALL_DOCS_QTY: qty.REMOTE_ALL_DOCS_QTY,
    REMOTE_TOTAL_QTY: qty.REMOTE_OPERATIONAL_QTY, // operational alias for table compat
    REMOTE_OPERATIONAL_QTY: qty.REMOTE_OPERATIONAL_QTY,
    REMOTE_ARCHIVED_TOMBSTONED_QTY: qty.REMOTE_ARCHIVED_TOMBSTONED_QTY,
    REMOTE_ARCHIVED_TOMBSTONED_PRODUCT_COUNT: qty.REMOTE_ARCHIVED_TOMBSTONED_PRODUCT_COUNT,
    CANONICAL_CELL_SUM_TOTAL: cellSumOperational,
    AGGREGATE_DELTA: qty.REMOTE_OPERATIONAL_QTY - cellSumOperational,
    PENDING_COUNT: pendingCount,
    ORPHAN_PENDING_COUNT: orphanPending,
    DUPLICATE_PENDING_COUNT: duplicatePending,
    INVALID_PENDING_COUNT: invalidPending,
    AGGREGATE_MISMATCH_COUNT: mismatches.length,
    NORMALIZED_AGGREGATE_MISMATCH_COUNT: mismatches.filter((m) => m.CLASS === 'A').length,
    CLASS_A_PROJECTION_COUNT: classA,
    CLASS_B_COUNT: classB,
    CLASS_C2_LEGACY_COUNT: classC2,
    CLASS_C3_COUNT: classC3,
    CLASS_C4_TOMBSTONE_COUNT: classC4,
    CLASS_C5_COUNT: classC5,
    AGGREGATE_MISMATCHES: mismatches.slice(0, 200),
    LINEAGE_ANOMALY_COUNT: lineageAnomalies.length,
    HISTORICAL_LINEAGE_COUNT: historicalLineage,
    ACTIVE_LINEAGE_RISK_COUNT: activeLineageRisk,
    LINEAGE_PRODUCTS: lineageAnomalies.slice(0, 100),
    STALE_TOMBSTONE_COUNT: staleTombs.length,
    STALE_TOMBSTONE_PRODUCTS: staleTombs.slice(0, 100),
    SALE_COUNT: sales.length,
    SALE_PROTOCOL_ACTIVE: protocolActive,
    VALID_BINDING_COUNT: modernExplicit + backendResolvable,
    MODERN_EXPLICIT_BINDING_COUNT: modernExplicit,
    LEGACY_SAFE_BINDING_COUNT: legacySafe,
    BACKEND_RESOLVABLE_BINDING_COUNT: backendResolvable,
    MISSING_BINDING_COUNT: missingExplicit,
    LEGACY_PRE_PROTOCOL_SALE_COUNT: legacySafe,
    UNRECOVERABLE_BINDING_COUNT: unrecoverable,
    AMBIGUOUS_BINDING_COUNT: ambiguous,
    SALE_BINDING_CLASS_COUNTS: classCounts,
    BAD_SALE_IDS: badSales.slice(0, 200),
    OP_COUNT: ops.length,
    OP_STATUS_INCONSISTENT: opStatusBad,
    RESTORE_WITHOUT_SOURCE: restoreNoSource,
    SOURCE_RESTORED_TWICE: sourceRestoredTwice,
    DUPLICATE_OP_HASH_EFFECTS: duplicateHashEffects,
    REVISION_REGRESSION: 0,
    OP_INTEGRITY_ISSUES: opStatusBad + restoreNoSource + sourceRestoredTwice + duplicateHashEffects,
    EDITSTOCK_SUSPECT_COUNT: editstockSuspect,
    LOCAL_ARTIFACT: local,
    LOCAL_ARTIFACT_ISSUES: localIssues,
    TRUE_PHYSICAL_RECOUNT_COUNT,
    PHYSICAL_RECOUNT_HINTS: TRUE_PHYSICAL_RECOUNT_COUNT, // deprecated alias
    CRITICAL_HINTS,
    LIST_ERRORS: listErrors,
  };
  t.OPERATIONAL_HEALTH = riskForTenant(t);
  t.RISK_CLASSIFICATION = t.OPERATIONAL_HEALTH;
  return t;
}

// --- main ---
const auth = token();
mkdirSync(OUT_DIR, {recursive: true});

const GLOBAL_FIXES = [
  'canonical backend stock mutation via executeStockCommand (functions/src/stockCatalogCommands.js)',
  'CAS stockRevision on adjust/replace/delete/undo/tombstone commands',
  'stockOperationId lineage on stock-effecting commands only',
  'idempotent sale/restore via stock_catalog_operations doc create',
  'explicit sale.stockOperationId binding for Admin restore rebound',
  'editorial must preserve prior stockOperationId (no lineage stamp when effectUnchanged)',
  'live positive canonical remote cells survive stale T/V tombstones (produto_exclusao_tombstone_service denylist KEEP)',
  'pending resolution / softFail protections on sale path',
  'variation canonicalization (normKey/canonicalMap/normalizeStock)',
  'local cache not authoritative over remote canonical stock (hydrate/untracked conflict store)',
  'legacy NO_CONTROL route with legacyCompat (stockKind infer on load)',
  'global audit operational qty excludes exclusao_produto.p=true tombstones',
  'C2 LEGACY_SIZE_METADATA_ONLY does not imply physical recount',
];

const TENANT_SPECIFIC_CODE_PATHS = [
  'lib/services/mirjoias_client_stock_diagnostic_export.dart — diagnostic export UI allowlist (mirjoias + nathy store ids only)',
  'lib/services/consolidate_stores.dart — one-time Nathy slug consolidation helper',
  'functions/scripts/*nathy* / *mirjoias* — operational repair/diagnostic scripts (not runtime product paths)',
  'No tenant-specific branches found in stockCatalogCommands / catalogStockProjection / tombstone KEEP logic',
];

const stores = await listCollection(auth, 'lojas');
const localHints = loadLocalArtifactHints();

console.log(JSON.stringify({
  phase: 'enumerate',
  TOTAL_LOJA_DOCS: stores.length,
  CLIENT_BASELINE,
  GLOBAL_FIXES,
  TENANT_SPECIFIC_CODE_PATHS,
}, null, 2));

const results = await mapPool(stores, CONCURRENCY, async (store) => {
  try {
    const r = await auditStore(auth, store, localHints);
    console.log(`[ok] ${r.STORE_ID} opQty=${r.REMOTE_OPERATIONAL_QTY} health=${r.OPERATIONAL_HEALTH} mism=${r.AGGREGATE_MISMATCH_COUNT} recount=${r.TRUE_PHYSICAL_RECOUNT_COUNT}`);
    return r;
  } catch (e) {
    console.error(`[err] ${store.id}: ${e.message}`);
    return {
      STORE_ID: store.id,
      DISPLAY_NAME: store.nome || store.id,
      ACTIVE: store.ativo ?? null,
      ERROR: String(e.message || e),
      PRODUCT_COUNT: 0,
      REMOTE_OPERATIONAL_QTY: 0,
      REMOTE_TOTAL_QTY: 0,
      AGGREGATE_MISMATCH_COUNT: 0,
      PENDING_COUNT: 0,
      LINEAGE_ANOMALY_COUNT: 0,
      ACTIVE_LINEAGE_RISK_COUNT: 0,
      STALE_TOMBSTONE_COUNT: 0,
      MISSING_BINDING_COUNT: 0,
      UNRECOVERABLE_BINDING_COUNT: 0,
      TRUE_PHYSICAL_RECOUNT_COUNT: 0,
      OPERATIONAL_HEALTH: 'BLOCKED',
      RISK_CLASSIFICATION: 'BLOCKED',
      CRITICAL_HINTS: ['AUDIT_ERROR'],
    };
  }
});

const active = results.filter((r) => (r.PRODUCT_COUNT || 0) > 0 || r.ACTIVE === true);
const empty = results.filter((r) => (r.PRODUCT_COUNT || 0) === 0 && r.ACTIVE !== true);

const summary = {
  MODE: 'READ_ONLY',
  CLIENT_BASELINE,
  CLASSIFIER_VERSION: 'operational-qty-excludes-p-tombstone-v2',
  GLOBAL_FIXES,
  TENANT_SPECIFIC_CODE_PATHS,
  TOTAL_LOJA_DOCS: stores.length,
  TOTAL_TENANTS: active.length,
  EMPTY_OR_INACTIVE_SKIPPED_FROM_ACTIVE: empty.length,
  HEALTHY_TENANTS: active.filter((r) => r.OPERATIONAL_HEALTH === 'HEALTHY').length,
  REVIEW_TENANTS: active.filter((r) => r.OPERATIONAL_HEALTH === 'REVIEW').length,
  BLOCKED_TENANTS: active.filter((r) => r.OPERATIONAL_HEALTH === 'BLOCKED').length,
  CLEAN_TENANTS: active.filter((r) => r.OPERATIONAL_HEALTH === 'HEALTHY').length,
  TENANTS_WITH_AGGREGATE_MISMATCH: active.filter((r) => (r.CLASS_A_PROJECTION_COUNT || 0) + (r.CLASS_B_COUNT || 0) > 0).length,
  TENANTS_WITH_LINEAGE_ANOMALY: active.filter((r) => (r.HISTORICAL_LINEAGE_COUNT || 0) > 0).length,
  ACTIVE_LINEAGE_RISK_TENANT_COUNT: active.filter((r) => (r.ACTIVE_LINEAGE_RISK_COUNT || 0) > 0).length,
  TENANTS_WITH_STALE_TOMBSTONES: active.filter((r) => (r.STALE_TOMBSTONE_COUNT || 0) > 0).length,
  TENANTS_WITH_MISSING_SALE_BINDING: active.filter((r) => (r.UNRECOVERABLE_BINDING_COUNT || 0) + (r.AMBIGUOUS_BINDING_COUNT || 0) > 0).length,
  UNRECOVERABLE_SALE_BINDING_COUNT: active.reduce((s, r) => s + (r.UNRECOVERABLE_BINDING_COUNT || 0), 0),
  TENANTS_WITH_PENDING: active.filter((r) => (r.PENDING_COUNT || 0) > 0).length,
  TENANTS_REQUIRING_PHYSICAL_RECOUNT: active.filter((r) => (r.TRUE_PHYSICAL_RECOUNT_COUNT || 0) > 0).length,
  TRUE_PHYSICAL_RECOUNT_COUNT_FROM_THIS_AUDIT: active.reduce((s, r) => s + (r.TRUE_PHYSICAL_RECOUNT_COUNT || 0), 0),
  CRITICAL_TENANTS: active.filter((r) => r.OPERATIONAL_HEALTH === 'BLOCKED').length,
  TABLE: active.map((r) => ({
    STORE_ID: r.STORE_ID,
    DISPLAY_NAME: r.DISPLAY_NAME,
    REMOTE_OPERATIONAL_QTY: r.REMOTE_OPERATIONAL_QTY,
    REMOTE_ALL_DOCS_QTY: r.REMOTE_ALL_DOCS_QTY,
    ARCHIVED_TOMBSTONED_QTY: r.REMOTE_ARCHIVED_TOMBSTONED_QTY,
    CLASS_A: r.CLASS_A_PROJECTION_COUNT || 0,
    CLASS_C2: r.CLASS_C2_LEGACY_COUNT || 0,
    PENDING: r.PENDING_COUNT,
    ACTIVE_LINEAGE: r.ACTIVE_LINEAGE_RISK_COUNT || 0,
    HISTORICAL_LINEAGE: r.HISTORICAL_LINEAGE_COUNT || 0,
    UNRECOVERABLE_BIND: r.UNRECOVERABLE_BINDING_COUNT || 0,
    STALE_TOMB: r.STALE_TOMBSTONE_COUNT,
    TRUE_PHYSICAL_RECOUNT: r.TRUE_PHYSICAL_RECOUNT_COUNT || 0,
    OPERATIONAL_HEALTH: r.OPERATIONAL_HEALTH,
    LEGACY_COMPAT: r.LEGACY_COMPAT,
  })).sort((a, b) => a.STORE_ID.localeCompare(b.STORE_ID)),
  SAFETY: {
    REMOTE_STOCK_WRITES: 0,
    SALE_WRITES: 0,
    RESTORE_WRITES: 0,
    DELETE_WRITES: 0,
    TOMBSTONE_WRITES: 0,
    MIGRATION_WRITES: 0,
    COMMIT: false,
    PUSH: false,
    DEPLOY: false,
  },
  tenants: active,
  empty_or_inactive: empty.map((r) => ({STORE_ID: r.STORE_ID, DISPLAY_NAME: r.DISPLAY_NAME, ACTIVE: r.ACTIVE})),
};

const nathy = active.find((r) => r.STORE_ID === 'nathy-pratas-e-folheados');
summary.NATHY_OPERATIONAL_QTY = nathy?.REMOTE_OPERATIONAL_QTY ?? null;
summary.NATHY_OPERATIONAL_HEALTH = nathy?.OPERATIONAL_HEALTH ?? null;
summary.NATHY_TRUE_PHYSICAL_RECOUNT_COUNT = nathy?.TRUE_PHYSICAL_RECOUNT_COUNT ?? null;
summary.NATHY_ALL_DOCS_QTY = nathy?.REMOTE_ALL_DOCS_QTY ?? null;
summary.NATHY_ARCHIVED_TOMBSTONED_QTY = nathy?.REMOTE_ARCHIVED_TOMBSTONED_QTY ?? null;

const anyBlocked = active.some((r) => r.OPERATIONAL_HEALTH === 'BLOCKED');
const anyReview = active.some((r) => r.OPERATIONAL_HEALTH === 'REVIEW');
summary.DECISION = anyBlocked
  ? 'MASTERPALM_GLOBAL_AUDIT_CLASSIFIER_BLOCKED_TENANTS_PRESENT'
  : anyReview
    ? 'MASTERPALM_GLOBAL_AUDIT_CLASSIFIER_REFINED_REVIEW_REMAINING'
    : 'MASTERPALM_GLOBAL_STOCK_HEALTH_CONFIRMED';

writeFileSync(join(OUT_DIR, 'GLOBAL_STOCK_HEALTH_AUDIT.json'), JSON.stringify(summary, null, 2));

const md = [
  '# MASTERPALM Global Stock Health Audit (Classifier Refined)',
  '',
  `DECISION=${summary.DECISION}`,
  `CLIENT_BASELINE=${CLIENT_BASELINE}`,
  `TOTAL_TENANTS=${summary.TOTAL_TENANTS}`,
  `HEALTHY_TENANTS=${summary.HEALTHY_TENANTS}`,
  `REVIEW_TENANTS=${summary.REVIEW_TENANTS}`,
  `BLOCKED_TENANTS=${summary.BLOCKED_TENANTS}`,
  `NATHY_OPERATIONAL_QTY=${summary.NATHY_OPERATIONAL_QTY}`,
  `NATHY_OPERATIONAL_HEALTH=${summary.NATHY_OPERATIONAL_HEALTH}`,
  `NATHY_TRUE_PHYSICAL_RECOUNT_COUNT=${summary.NATHY_TRUE_PHYSICAL_RECOUNT_COUNT}`,
  `ACTIVE_LINEAGE_RISK_TENANT_COUNT=${summary.ACTIVE_LINEAGE_RISK_TENANT_COUNT}`,
  `UNRECOVERABLE_SALE_BINDING_COUNT=${summary.UNRECOVERABLE_SALE_BINDING_COUNT}`,
  `TRUE_PHYSICAL_RECOUNT_COUNT_FROM_THIS_AUDIT=${summary.TRUE_PHYSICAL_RECOUNT_COUNT_FROM_THIS_AUDIT}`,
  '',
  '| STORE_ID | DISPLAY_NAME | OP_QTY | ALL_QTY | ARCH_QTY | A | C2 | PENDING | ACT_LIN | UNREC | RECOUNT | HEALTH |',
  '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|',
  ...summary.TABLE.map((r) =>
    `| ${r.STORE_ID} | ${String(r.DISPLAY_NAME).replace(/\|/g, '/')} | ${r.REMOTE_OPERATIONAL_QTY} | ${r.REMOTE_ALL_DOCS_QTY} | ${r.ARCHIVED_TOMBSTONED_QTY} | ${r.CLASS_A} | ${r.CLASS_C2} | ${r.PENDING} | ${r.ACTIVE_LINEAGE} | ${r.UNRECOVERABLE_BIND} | ${r.TRUE_PHYSICAL_RECOUNT} | ${r.OPERATIONAL_HEALTH} |`),
  '',
  'REMOTE_STOCK_WRITES=0 SALE_WRITES=0 RESTORE_WRITES=0 DELETE_WRITES=0 TOMBSTONE_WRITES=0 MIGRATION_WRITES=0',
  'DEPLOY=false',
].join('\n');
writeFileSync(join(OUT_DIR, 'GLOBAL_STOCK_HEALTH_AUDIT.md'), md);

console.log(JSON.stringify({
  DECISION: summary.DECISION,
  TOTAL_TENANTS: summary.TOTAL_TENANTS,
  HEALTHY_TENANTS: summary.HEALTHY_TENANTS,
  REVIEW_TENANTS: summary.REVIEW_TENANTS,
  BLOCKED_TENANTS: summary.BLOCKED_TENANTS,
  NATHY_OPERATIONAL_QTY: summary.NATHY_OPERATIONAL_QTY,
  NATHY_OPERATIONAL_HEALTH: summary.NATHY_OPERATIONAL_HEALTH,
  NATHY_TRUE_PHYSICAL_RECOUNT_COUNT: summary.NATHY_TRUE_PHYSICAL_RECOUNT_COUNT,
  ACTIVE_LINEAGE_RISK_TENANT_COUNT: summary.ACTIVE_LINEAGE_RISK_TENANT_COUNT,
  UNRECOVERABLE_SALE_BINDING_COUNT: summary.UNRECOVERABLE_SALE_BINDING_COUNT,
  TRUE_PHYSICAL_RECOUNT_COUNT_FROM_THIS_AUDIT: summary.TRUE_PHYSICAL_RECOUNT_COUNT_FROM_THIS_AUDIT,
  OUT: join(OUT_DIR, 'GLOBAL_STOCK_HEALTH_AUDIT.json'),
}, null, 2));
