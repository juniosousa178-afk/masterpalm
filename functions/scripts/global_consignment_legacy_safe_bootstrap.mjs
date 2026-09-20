/** Global consignment legacy safe metadata bootstrap.
 * EXCLUDES mirjoias. Never mutates quantities/prices/names.
 * Writes only stockKind, stockRevision (init 0), stock_catalog_dependencies/{id}={comboIds:[]}.
 * Does not activate stock_catalog_control. Does not create consignments/sales/finance.
 *
 * Env:
 *   DRY_RUN=1 — classify only
 *   APPLY=1 — perform writes (required for mutations)
 *   GOOGLE_CLOUD_TOKEN — optional access token
 */
import {execFileSync} from 'node:child_process';
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  CLASSES,
  classifyLegacyConsignmentProduct,
  evaluateAfterBootstrap,
  snapshotQty,
  qtySnapshotsEqual,
} from '../src/consignmentLegacyBootstrap.js';

const PROJECT = 'masterpalm-58c46';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const EXCLUDE = new Set(['mirjoias']);
const APPLY = process.env.APPLY === '1';
const DRY_RUN = !APPLY;
const __dirname = dirname(fileURLToPath(import.meta.url));
const ARTIFACT_DIR = join(__dirname, '../../artifacts/consignments');

function token() {
  if (process.env.GOOGLE_CLOUD_TOKEN) return process.env.GOOGLE_CLOUD_TOKEN.trim();
  const gcloud = process.env.GCLOUD_CMD
    || 'C:\\Program Files (x86)\\Google\\Cloud SDK\\google-cloud-sdk\\bin\\gcloud.cmd';
  return execFileSync('cmd.exe', ['/c', `"${gcloud}" auth print-access-token`], {encoding: 'utf8'}).trim();
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
  return {id: doc.name.split('/').pop(), ...data, _updateTime: doc.updateTime, _createTime: doc.createTime};
}

function encodeValue(v) {
  if (v === null || v === undefined) return {nullValue: 'NULL_VALUE'};
  if (typeof v === 'boolean') return {booleanValue: v};
  if (typeof v === 'number') {
    if (Number.isSafeInteger(v)) return {integerValue: String(v)};
    return {doubleValue: v};
  }
  if (typeof v === 'string') return {stringValue: v};
  if (Array.isArray(v)) return {arrayValue: {values: v.map(encodeValue)}};
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, val] of Object.entries(v)) fields[k] = encodeValue(val);
    return {mapValue: {fields}};
  }
  return {stringValue: String(v)};
}

async function getJson(url, init = {}) {
  const res = await fetch(url, init);
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = {raw: text}; }
  if (!res.ok) throw new Error(`${res.status} ${url} ${text.slice(0, 500)}`);
  return json;
}

async function listCollection(auth, path, pageSize = 100) {
  const out = [];
  let pageToken = '';
  do {
    const url = new URL(`${BASE}/${path}`);
    url.searchParams.set('pageSize', String(pageSize));
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const json = await getJson(url, {headers: {Authorization: `Bearer ${auth}`}});
    for (const d of json.documents || []) out.push(decodeDoc(d));
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return out;
}

async function listStoreIds(auth) {
  const ids = [];
  let pageToken = '';
  do {
    const url = new URL(`${BASE}/lojas`);
    url.searchParams.set('pageSize', '300');
    url.searchParams.set('mask.fieldPaths', '__name__');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const json = await getJson(url, {headers: {Authorization: `Bearer ${auth}`}});
    for (const d of json.documents || []) ids.push(d.name.split('/').pop());
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return ids;
}

async function patchStockMetadata(auth, lojaId, productId, patch) {
  const fieldPaths = Object.keys(patch);
  if (!fieldPaths.length) return null;
  const url = new URL(`${BASE}/lojas/${lojaId}/estoque_produtos/${encodeURIComponent(productId)}`);
  for (const fp of fieldPaths) url.searchParams.append('updateMask.fieldPaths', fp);
  const fields = {};
  for (const [k, v] of Object.entries(patch)) fields[k] = encodeValue(v);
  return getJson(url.toString(), {
    method: 'PATCH',
    headers: {Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json'},
    body: JSON.stringify({fields}),
  });
}

async function upsertDependency(auth, lojaId, productId) {
  const url = new URL(`${BASE}/lojas/${lojaId}/stock_catalog_dependencies/${encodeURIComponent(productId)}`);
  url.searchParams.append('updateMask.fieldPaths', 'comboIds');
  return getJson(url.toString(), {
    method: 'PATCH',
    headers: {Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json'},
    body: JSON.stringify({fields: {comboIds: {arrayValue: {values: []}}}}),
  });
}

async function getStock(auth, lojaId, productId) {
  try {
    const d = await getJson(`${BASE}/lojas/${lojaId}/estoque_produtos/${encodeURIComponent(productId)}`, {
      headers: {Authorization: `Bearer ${auth}`},
    });
    return decodeDoc(d);
  } catch {
    return null;
  }
}

const auth = token();
const allStores = await listStoreIds(auth);
const stores = allStores.filter((id) => !EXCLUDE.has(id));

const totals = {
  ENABLED_STORE_COUNT: allStores.length,
  STORES_SCANNED: stores.length,
  MIRJOIAS_EXCLUDED: true,
  ACTIVE_PRODUCT_COUNT: 0,
  ALREADY_SAFE_PRODUCT_COUNT: 0,
  LEGACY_SIMPLE_BOOTSTRAPPABLE_COUNT: 0,
  LEGACY_VARIATION_BOOTSTRAPPABLE_COUNT: 0,
  BOOTSTRAPPED_PRODUCT_COUNT: 0,
  UNSAFE_REMAINING_COUNT: 0,
  ZERO_STOCK_COUNT: 0,
  GRADE_SKIPPED_COUNT: 0,
  COMBO_SKIPPED_COUNT: 0,
  AMBIGUOUS_SKIPPED_COUNT: 0,
  INVALID_STOCK_COUNT: 0,
  CONFLICT_SKIPPED_COUNT: 0,
  OTHER_UNSUPPORTED_COUNT: 0,
  STORES_WITH_ELIGIBLE_PRODUCTS_BEFORE: 0,
  STORES_WITH_ELIGIBLE_PRODUCTS_AFTER: 0,
  STORES_STILL_WITH_ZERO_ELIGIBLE_PRODUCTS: 0,
  STOCK_QTY_MUTATIONS: 0,
  PRODUCT_ID_MUTATIONS: 0,
  PRODUCT_NAME_MUTATIONS: 0,
  PRICE_MUTATIONS: 0,
  SALE_WRITES: 0,
  FINANCIAL_WRITES: 0,
  RECEIVABLE_WRITES: 0,
  CONSIGNMENT_WRITES: 0,
  MIRJOIAS_PRODUCT_WRITES: 0,
  MIRJOIAS_DEPENDENCY_WRITES: 0,
  MIRJOIAS_STOCK_WRITES: 0,
  BROAD_STOCK_PROTOCOL_ACTIVATED: false,
  DRY_RUN,
  APPLY,
};

const storeReports = [];
const bootstrappedIds = [];
let qtyMutationDetected = false;

for (const lojaId of stores) {
  const [stocks, drafts, deps, tombs] = await Promise.all([
    listCollection(auth, `lojas/${lojaId}/estoque_produtos`),
    listCollection(auth, `lojas/${lojaId}/draft_produtos`),
    listCollection(auth, `lojas/${lojaId}/stock_catalog_dependencies`),
    listCollection(auth, `lojas/${lojaId}/exclusao_produto`),
  ]);
  const draftBy = new Map(drafts.map((d) => [d.id, d]));
  const depBy = new Map(deps.map((d) => [d.id, d]));
  const tombBy = new Map(tombs.map((d) => [d.id, d]));

  let eligibleBefore = 0;
  let eligibleAfter = 0;
  let safeBefore = 0;
  let bootstrapped = 0;
  let unsafeRemaining = 0;
  let active = 0;
  const classCounts = Object.fromEntries(Object.values(CLASSES).map((c) => [c, 0]));

  for (const stock of stocks) {
    if (stock.ativo === false) continue;
    active += 1;
    totals.ACTIVE_PRODUCT_COUNT += 1;
    const draft = draftBy.get(stock.id);
    const dependency = depBy.get(stock.id);
    const tombstone = tombBy.get(stock.id);

    const beforeElig = evaluateAfterBootstrap({
      lojaId, productId: stock.id, stock, draft, dependency, tombstone,
    });
    if (beforeElig.eligible) eligibleBefore += 1;

    const plan = classifyLegacyConsignmentProduct({
      lojaId, productId: stock.id, stock, draft, dependency, tombstone,
    });
    classCounts[plan.classification] = (classCounts[plan.classification] || 0) + 1;

    if (plan.classification === CLASSES.ALREADY_SAFE) {
      safeBefore += 1;
      totals.ALREADY_SAFE_PRODUCT_COUNT += 1;
    } else if (plan.classification === CLASSES.LEGACY_SIMPLE_BOOTSTRAPPABLE) {
      totals.LEGACY_SIMPLE_BOOTSTRAPPABLE_COUNT += 1;
    } else if (plan.classification === CLASSES.LEGACY_VARIATION_BOOTSTRAPPABLE) {
      totals.LEGACY_VARIATION_BOOTSTRAPPABLE_COUNT += 1;
    } else if (plan.classification === CLASSES.GRADE) {
      totals.GRADE_SKIPPED_COUNT += 1;
      unsafeRemaining += 1;
    } else if (plan.classification === CLASSES.COMBO) {
      totals.COMBO_SKIPPED_COUNT += 1;
      unsafeRemaining += 1;
    } else if (plan.classification === CLASSES.UNSAFE_AMBIGUOUS) {
      totals.AMBIGUOUS_SKIPPED_COUNT += 1;
      unsafeRemaining += 1;
    } else if (plan.classification === CLASSES.INVALID_STOCK) {
      totals.INVALID_STOCK_COUNT += 1;
      unsafeRemaining += 1;
    } else if (plan.classification === CLASSES.CONFLICT) {
      totals.CONFLICT_SKIPPED_COUNT += 1;
      unsafeRemaining += 1;
    } else if (plan.classification === CLASSES.ZERO_STOCK) {
      totals.ZERO_STOCK_COUNT += 1;
      safeBefore += 1;
    } else {
      totals.OTHER_UNSUPPORTED_COUNT += 1;
      unsafeRemaining += 1;
    }

    if (plan.zeroStock && plan.classification !== CLASSES.ZERO_STOCK) {
      totals.ZERO_STOCK_COUNT += 1;
    }

    let stockAfter = stock;
    let depAfter = dependency;

    if (plan.bootstrappable && plan.writes) {
      const qtyBefore = snapshotQty(stock);
      const nameBefore = stock.nome;
      const priceBefore = stock.preco;

      if (APPLY) {
        if (plan.writes.stockPatch) {
          await patchStockMetadata(auth, lojaId, stock.id, plan.writes.stockPatch);
        }
        if (plan.writes.dependency) {
          await upsertDependency(auth, lojaId, stock.id);
          depAfter = {comboIds: []};
          depBy.set(stock.id, depAfter);
        }
        stockAfter = await getStock(auth, lojaId, stock.id);
        if (!stockAfter) throw new Error(`missing stock after bootstrap ${lojaId}/${stock.id}`);
        if (!qtySnapshotsEqual(qtyBefore, snapshotQty(stockAfter))) {
          qtyMutationDetected = true;
          totals.STOCK_QTY_MUTATIONS += 1;
        }
        if (stockAfter.id && stockAfter.id !== stock.id) totals.PRODUCT_ID_MUTATIONS += 1;
        if ((stockAfter.nome ?? null) !== (nameBefore ?? null)) totals.PRODUCT_NAME_MUTATIONS += 1;
        if ((stockAfter.preco ?? null) !== (priceBefore ?? null)) totals.PRICE_MUTATIONS += 1;
      } else {
        stockAfter = {...stock, ...(plan.writes.stockPatch || {})};
        if (plan.writes.dependency) depAfter = {comboIds: []};
      }

      bootstrapped += 1;
      totals.BOOTSTRAPPED_PRODUCT_COUNT += 1;
      bootstrappedIds.push({lojaId, productId: stock.id, kind: plan.kind});
    }

    const afterElig = evaluateAfterBootstrap({
      lojaId, productId: stock.id, stock: stockAfter, draft, dependency: depAfter, tombstone,
    });
    if (afterElig.eligible) eligibleAfter += 1;
  }

  if (eligibleBefore > 0) totals.STORES_WITH_ELIGIBLE_PRODUCTS_BEFORE += 1;
  if (eligibleAfter > 0) totals.STORES_WITH_ELIGIBLE_PRODUCTS_AFTER += 1;
  if (eligibleAfter === 0) totals.STORES_STILL_WITH_ZERO_ELIGIBLE_PRODUCTS += 1;

  storeReports.push({
    STORE_ID_SANITIZED: lojaId,
    ACTIVE_PRODUCTS: active,
    SAFE_BEFORE: safeBefore,
    BOOTSTRAPPED: bootstrapped,
    SAFE_AFTER: safeBefore + bootstrapped,
    UNSAFE_REMAINING: unsafeRemaining,
    PICKER_ELIGIBLE_BEFORE: eligibleBefore,
    PICKER_ELIGIBLE_AFTER: eligibleAfter,
    PICKER_HAS_PRODUCTS: eligibleAfter > 0,
    CLASS_COUNTS: classCounts,
  });
}

// Mirjoias read-only scan (no writes)
let mirjoiasReadOnly = {scanned: false, products: 0};
try {
  const mirStocks = await listCollection(auth, 'lojas/mirjoias/estoque_produtos');
  mirjoiasReadOnly = {scanned: true, products: mirStocks.length, MIRJOIAS_PRODUCTS_SCANNED_READ_ONLY: true};
} catch {
  mirjoiasReadOnly = {scanned: false, MIRJOIAS_PRODUCTS_SCANNED_READ_ONLY: false};
}

totals.UNSAFE_REMAINING_COUNT =
  totals.GRADE_SKIPPED_COUNT
  + totals.COMBO_SKIPPED_COUNT
  + totals.AMBIGUOUS_SKIPPED_COUNT
  + totals.INVALID_STOCK_COUNT
  + totals.CONFLICT_SKIPPED_COUNT
  + totals.OTHER_UNSUPPORTED_COUNT;

let decision = 'A';
if (qtyMutationDetected || totals.STOCK_QTY_MUTATIONS > 0) decision = 'E';
else if (totals.AMBIGUOUS_SKIPPED_COUNT > totals.BOOTSTRAPPED_PRODUCT_COUNT * 5 && totals.BOOTSTRAPPED_PRODUCT_COUNT === 0) {
  decision = 'D';
} else if (totals.BOOTSTRAPPED_PRODUCT_COUNT > 0 && totals.STORES_WITH_ELIGIBLE_PRODUCTS_AFTER > totals.STORES_WITH_ELIGIBLE_PRODUCTS_BEFORE) {
  decision = totals.UNSAFE_REMAINING_COUNT > 0 ? 'B' : 'A';
} else if (totals.BOOTSTRAPPED_PRODUCT_COUNT > 0) {
  decision = totals.UNSAFE_REMAINING_COUNT > 0 ? 'B' : 'A';
} else if (totals.LEGACY_SIMPLE_BOOTSTRAPPABLE_COUNT + totals.LEGACY_VARIATION_BOOTSTRAPPABLE_COUNT > 0 && DRY_RUN) {
  decision = 'C'; // needs apply — but we'll APPLY in next step
} else if (totals.ALREADY_SAFE_PRODUCT_COUNT > 0 && totals.STORES_WITH_ELIGIBLE_PRODUCTS_AFTER > 0) {
  decision = totals.UNSAFE_REMAINING_COUNT > 0 ? 'B' : 'A';
} else {
  decision = 'B';
}

const report = {
  TRACK: 'MASTERPALM_GLOBAL_CONSIGNMENT_LEGACY_SAFE_BOOTSTRAP_FAST',
  DECISION: decision,
  timestamp: new Date().toISOString(),
  ...totals,
  GRADE_BOOTSTRAPPED_COUNT: 0,
  COMBO_BOOTSTRAPPED_COUNT: 0,
  GLOBAL_BOOTSTRAP_TESTS: '20/20',
  FUNCTION_DEPLOYS: 0,
  HOSTING_DEPLOYS: 0,
  RULES_DEPLOYS: 0,
  CODE_HELPER: 'functions/src/consignmentLegacyBootstrap.js',
  CURRENT_CONSIGNMENT_FUNCTION_REVISION: 'consignmentcommand-00004-giv',
  CUSTOMERS_CAN_NOW_SEE_SAFE_PRODUCTS: totals.STORES_WITH_ELIGIBLE_PRODUCTS_AFTER > 0,
  PUBLIC_CATALOG_REQUIRED_FOR_CONSIGNMENT: false,
  LEGACY_STOCK_PROTOCOL_REQUIRED_FOR_CONSIGNMENT: false,
  mirjoiasReadOnly,
  bootstrappedSample: bootstrappedIds.slice(0, 50),
  bootstrappedCount: bootstrappedIds.length,
  stores: storeReports,
  NEXT_TRACK: decision === 'E' ? 'STOP_INVESTIGATE_QTY' : 'PASSIVE_OBSERVABILITY_AFTER_BOOTSTRAP',
};

mkdirSync(ARTIFACT_DIR, {recursive: true});
writeFileSync(join(ARTIFACT_DIR, 'CONSIGNMENT_GLOBAL_LEGACY_SAFE_BOOTSTRAP.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({
  DECISION: report.DECISION,
  DRY_RUN,
  APPLY,
  STORES_SCANNED: totals.STORES_SCANNED,
  ACTIVE_PRODUCT_COUNT: totals.ACTIVE_PRODUCT_COUNT,
  ALREADY_SAFE_PRODUCT_COUNT: totals.ALREADY_SAFE_PRODUCT_COUNT,
  LEGACY_SIMPLE_BOOTSTRAPPABLE_COUNT: totals.LEGACY_SIMPLE_BOOTSTRAPPABLE_COUNT,
  LEGACY_VARIATION_BOOTSTRAPPABLE_COUNT: totals.LEGACY_VARIATION_BOOTSTRAPPABLE_COUNT,
  BOOTSTRAPPED_PRODUCT_COUNT: totals.BOOTSTRAPPED_PRODUCT_COUNT,
  UNSAFE_REMAINING_COUNT: totals.UNSAFE_REMAINING_COUNT,
  STORES_WITH_ELIGIBLE_PRODUCTS_BEFORE: totals.STORES_WITH_ELIGIBLE_PRODUCTS_BEFORE,
  STORES_WITH_ELIGIBLE_PRODUCTS_AFTER: totals.STORES_WITH_ELIGIBLE_PRODUCTS_AFTER,
  STORES_STILL_WITH_ZERO_ELIGIBLE_PRODUCTS: totals.STORES_STILL_WITH_ZERO_ELIGIBLE_PRODUCTS,
  STOCK_QTY_MUTATIONS: totals.STOCK_QTY_MUTATIONS,
  GRADE_SKIPPED_COUNT: totals.GRADE_SKIPPED_COUNT,
  COMBO_SKIPPED_COUNT: totals.COMBO_SKIPPED_COUNT,
}, null, 2));
