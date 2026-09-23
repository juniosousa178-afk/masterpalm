/**
 * READ-ONLY: count tenants where estoque commercial fields ≠ live produtos.
 * No writes. No republish.
 */
import {execFileSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {mkdirSync, writeFileSync} from 'node:fs';

const PROJECT = 'masterpalm-58c46';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../artifacts/catalog_commercial_fields');
const CONCURRENCY = Number(process.env.AUDIT_CONCURRENCY || 4);

function token() {
  if (process.env.GOOGLE_CLOUD_TOKEN) return process.env.GOOGLE_CLOUD_TOKEN.trim();
  const helper = join(__dirname, '_gcloud_access_token.ps1');
  const out = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', helper], {
    encoding: 'utf8', windowsHide: true, maxBuffer: 2 * 1024 * 1024,
  });
  return String(out || '').trim().split(/\r?\n/).filter(Boolean).pop();
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
  try { json = text ? JSON.parse(text) : null; } catch { json = null; }
  if (!res.ok) throw new Error(`${res.status} ${text.slice(0, 200)}`);
  return json;
}

async function listAll(auth, path) {
  const out = [];
  let pageToken = '';
  do {
    const url = new URL(`${BASE}/${path}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const json = await getJson(url.toString(), {headers: {Authorization: `Bearer ${auth}`}});
    for (const d of json.documents || []) out.push(decodeDoc(d));
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return out;
}

function hasCommercialSource(p) {
  return ('divideSemJuros' in p) || ('percentualDescontoPix' in p) || ('maxParcelasSemJuros' in p);
}

function eqField(a, b, key) {
  const aHas = key in a;
  const bHas = key in b;
  if (!aHas && !bHas) return true;
  if (aHas !== bHas) return false;
  return a[key] === b[key];
}

function auditStore(estoque, live) {
  const liveById = new Map(live.map((p) => [p.id, p]));
  let affected = 0;
  let pixMismatch = 0;
  let installMismatch = 0;
  let divideMismatch = 0;
  let sourceWithAny = 0;
  for (const e of estoque) {
    if (!hasCommercialSource(e)) continue;
    sourceWithAny++;
    const l = liveById.get(e.id);
    // Only compare when product is live-published OR source has commercial and live exists
    if (!l) {
      // Not live — mismatch only if we'd expect projection when available;
      // count source commercial for published-intent differently: skip absent live
      continue;
    }
    const pixOk = eqField(e, l, 'percentualDescontoPix');
    const divOk = eqField(e, l, 'divideSemJuros');
    const maxOk = eqField(e, l, 'maxParcelasSemJuros');
    if (!pixOk) pixMismatch++;
    if (!divOk) divideMismatch++;
    if (!maxOk) installMismatch++;
    if (!pixOk || !divOk || !maxOk) affected++;
  }
  return {
    SOURCE_WITH_COMMERCIAL: sourceWithAny,
    LIVE_COUNT: live.length,
    ESTOQUE_COUNT: estoque.length,
    AFFECTED_PRODUCT_COUNT: affected,
    PIX_MISMATCH_COUNT: pixMismatch,
    INSTALLMENT_MISMATCH_COUNT: installMismatch,
    DIVIDE_MISMATCH_COUNT: divideMismatch,
  };
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

const auth = token();
mkdirSync(OUT, {recursive: true});
const stores = await listAll(auth, 'lojas');
console.log(JSON.stringify({phase: 'enumerate', TOTAL: stores.length}, null, 2));

const rows = await mapPool(stores, CONCURRENCY, async (store) => {
  const id = store.id;
  try {
    const [estoque, live] = await Promise.all([
      listAll(auth, `lojas/${id}/estoque_produtos`),
      listAll(auth, `lojas/${id}/produtos`),
    ]);
    if (estoque.length === 0 && live.length === 0) {
      return {STORE_ID: id, SKIPPED: true, AFFECTED_PRODUCT_COUNT: 0};
    }
    const a = auditStore(estoque, live);
    console.log(`[ok] ${id} affected=${a.AFFECTED_PRODUCT_COUNT} pix=${a.PIX_MISMATCH_COUNT}`);
    return {STORE_ID: id, DISPLAY_NAME: store.nome || store.name || id, ...a};
  } catch (e) {
    console.error(`[err] ${id}: ${e.message}`);
    return {STORE_ID: id, ERROR: String(e.message || e), AFFECTED_PRODUCT_COUNT: 0};
  }
});

const active = rows.filter((r) => !r.SKIPPED && !r.ERROR);
const affectedTenants = active.filter((r) => (r.AFFECTED_PRODUCT_COUNT || 0) > 0);
const summary = {
  MODE: 'READ_ONLY',
  GLOBAL_AFFECTED_TENANT_COUNT: affectedTenants.length,
  GLOBAL_AFFECTED_PRODUCT_COUNT: affectedTenants.reduce((s, r) => s + (r.AFFECTED_PRODUCT_COUNT || 0), 0),
  TABLE: active
    .filter((r) => (r.AFFECTED_PRODUCT_COUNT || 0) > 0 || (r.SOURCE_WITH_COMMERCIAL || 0) > 0)
    .sort((a, b) => (b.AFFECTED_PRODUCT_COUNT || 0) - (a.AFFECTED_PRODUCT_COUNT || 0)),
  MIRJOIAS: active.find((r) => r.STORE_ID === 'mirjoias') || null,
  SAFETY: {REMOTE_STOCK_WRITES: 0, CATALOG_WRITES: 0, CROSS_TENANT_DATA_READS: 0},
};
writeFileSync(join(OUT, 'GLOBAL_COMMERCIAL_FIELDS_MISMATCH_AUDIT.json'), JSON.stringify(summary, null, 2));
console.log(JSON.stringify({
  GLOBAL_AFFECTED_TENANT_COUNT: summary.GLOBAL_AFFECTED_TENANT_COUNT,
  GLOBAL_AFFECTED_PRODUCT_COUNT: summary.GLOBAL_AFFECTED_PRODUCT_COUNT,
  MIRJOIAS: summary.MIRJOIAS,
  OUT: join(OUT, 'GLOBAL_COMMERCIAL_FIELDS_MISMATCH_AUDIT.json'),
}, null, 2));
