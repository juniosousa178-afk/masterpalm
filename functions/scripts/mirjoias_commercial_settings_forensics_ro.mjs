/**
 * READ-ONLY Mirjoias catalog commercial settings forensics.
 * No writes. STORE_ID=mirjoias only.
 */
import {execFileSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {writeFileSync, mkdirSync} from 'node:fs';

const PROJECT = 'masterpalm-58c46';
const STORE = 'mirjoias';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../artifacts/mirjoias_commercial_settings');

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
  try { json = text ? JSON.parse(text) : null; } catch { json = {raw: text.slice(0, 300)}; }
  if (!res.ok) {
    if (res.status === 404) return null;
    throw new Error(`${res.status} ${url} ${text.slice(0, 200)}`);
  }
  return json;
}

async function getDoc(auth, path) {
  const json = await getJson(`${BASE}/${path}`, {headers: {Authorization: `Bearer ${auth}`}});
  return json ? decodeDoc(json) : null;
}

async function listAll(auth, path) {
  const out = [];
  let pageToken = '';
  do {
    const url = new URL(`${BASE}/${path}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const json = await getJson(url.toString(), {headers: {Authorization: `Bearer ${auth}`}});
    for (const d of json?.documents || []) out.push(decodeDoc(d));
    pageToken = json?.nextPageToken || '';
  } while (pageToken);
  return out;
}

const auth = token();
mkdirSync(OUT, {recursive: true});

const [loja, payments, paymentsPublic, cfg, control] = await Promise.all([
  getDoc(auth, `lojas/${STORE}`),
  getDoc(auth, `lojas/${STORE}/config/payments`),
  getDoc(auth, `lojas/${STORE}/config/payments_public`),
  getDoc(auth, `lojas/${STORE}/config/config`),
  getDoc(auth, `lojas/${STORE}/stock_catalog_control/state`),
]);

const estoque = await listAll(auth, `lojas/${STORE}/estoque_produtos`);
const live = await listAll(auth, `lojas/${STORE}/produtos`);

function commercialOf(p) {
  return {
    id: p?.id,
    percentualDescontoPix: p?.percentualDescontoPix ?? null,
    divideSemJuros: p?.divideSemJuros ?? null,
    maxParcelasSemJuros: p?.maxParcelasSemJuros ?? null,
    updatedAt: p?.updatedAt ?? null,
  };
}

const estWithPix = estoque.filter((p) => Number(p.percentualDescontoPix) > 0);
const estWithDiv = estoque.filter((p) => p.divideSemJuros === true);
const liveWithPix = live.filter((p) => Number(p.percentualDescontoPix) > 0);
const liveWithDiv = live.filter((p) => p.divideSemJuros === true);

const samples = [];
const candidates = [...estWithPix, ...estWithDiv].slice(0, 5);
for (const e of candidates) {
  const draft = await getDoc(auth, `lojas/${STORE}/draft_produtos/${e.id}`);
  const lv = live.find((x) => x.id === e.id) || await getDoc(auth, `lojas/${STORE}/produtos/${e.id}`);
  samples.push({
    productId: e.id,
    ESTOQUE: commercialOf(e),
    DRAFT: commercialOf(draft),
    LIVE_PRODUTOS: commercialOf(lv),
  });
}

// How many live products have ANY of the commercial keys present
let liveKeyPresent = {pix: 0, div: 0, max: 0};
for (const p of live) {
  if ('percentualDescontoPix' in p) liveKeyPresent.pix++;
  if ('divideSemJuros' in p) liveKeyPresent.div++;
  if ('maxParcelasSemJuros' in p) liveKeyPresent.max++;
}
let estKeyPresent = {pix: 0, div: 0, max: 0};
for (const p of estoque) {
  if ('percentualDescontoPix' in p) estKeyPresent.pix++;
  if ('divideSemJuros' in p) estKeyPresent.div++;
  if ('maxParcelasSemJuros' in p) estKeyPresent.max++;
}

const report = {
  MODE: 'READ_ONLY',
  STORE_ID: STORE,
  STOCK_CATALOG_CONTROL_MODE: control?.mode ?? null,
  LOJA_CHECKOUT: loja?.checkout ?? null,
  PAYMENTS_CHECKOUT: payments?.checkout ?? null,
  PAYMENTS_PUBLIC_CHECKOUT: paymentsPublic?.checkout ?? null,
  PAYMENTS_UPDATED_AT: payments?.checkout?.updated_at ?? payments?.updated_at ?? null,
  PAYMENTS_PUBLIC_UPDATED_AT: paymentsPublic?.checkout?.updated_at ?? paymentsPublic?.updated_at ?? null,
  CFG_HAS_CHECKOUT: cfg?.checkout != null,
  COUNTS: {
    ESTOQUE_PRODUCTS: estoque.length,
    LIVE_PRODUTOS: live.length,
    ESTOQUE_PIX_GT0: estWithPix.length,
    ESTOQUE_DIVIDE_SEM_JUROS: estWithDiv.length,
    LIVE_PIX_GT0: liveWithPix.length,
    LIVE_DIVIDE_SEM_JUROS: liveWithDiv.length,
    ESTOQUE_KEY_PRESENT: estKeyPresent,
    LIVE_KEY_PRESENT: liveKeyPresent,
  },
  SAMPLES: samples,
  SAFETY: {
    REMOTE_STOCK_WRITES: 0,
    CATALOG_WRITES: 0,
    STORE_CONFIG_WRITES: 0,
    SALE_WRITES: 0,
    CROSS_TENANT_DATA_READS: 0,
  },
};

writeFileSync(join(OUT, 'MIRJOIAS_COMMERCIAL_SETTINGS_FORENSICS.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({
  CONTROL: report.STOCK_CATALOG_CONTROL_MODE,
  LOJA_CHECKOUT: report.LOJA_CHECKOUT,
  PAYMENTS_CHECKOUT: report.PAYMENTS_CHECKOUT,
  PAYMENTS_PUBLIC_CHECKOUT: report.PAYMENTS_PUBLIC_CHECKOUT,
  COUNTS: report.COUNTS,
  SAMPLE0: samples[0] || null,
  OUT: join(OUT, 'MIRJOIAS_COMMERCIAL_SETTINGS_FORENSICS.json'),
}, null, 2));
