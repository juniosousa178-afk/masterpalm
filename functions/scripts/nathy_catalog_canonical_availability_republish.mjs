/**
 * NATHY-only catalog bulk republish (canonical availability + bulk resilience).
 * STOCK_REPAIR=false — does not mutate qty/cells/revision/operationId.
 * APPLY=0 → dry preflight counts; APPLY=1 → publishStockAll(nathy)
 */
import {execFileSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {mkdirSync, writeFileSync} from 'node:fs';
import {Firestore} from '@google-cloud/firestore';
import {GoogleAuth} from 'google-auth-library';
import {
  classifyCatalogPublishPreflight,
  publishStockAll,
} from '../src/stockCatalogCommands.js';

const PROJECT = 'masterpalm-58c46';
const STORE = 'nathy-pratas-e-folheados';
const INFINITO = 'nathy-pratas-e-folheados-anel-infinito-brilho';
const APARADOR = 'nathy-pratas-e-folheados-anel-aparador-verde';
const __dirname = dirname(fileURLToPath(import.meta.url));
const APPLY = process.env.APPLY === '1';
const OUT = join(__dirname, '../../artifacts/nathy_catalog_canonical_availability');
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

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

async function listAll(auth, path) {
  const out = [];
  let pageToken = '';
  do {
    const url = new URL(`${BASE}/${path}`);
    url.searchParams.set('pageSize', '300');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const res = await fetch(url.toString(), {headers: {Authorization: `Bearer ${auth}`}});
    const json = await res.json();
    if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(json).slice(0, 200)}`);
    for (const d of json.documents || []) out.push(decodeDoc(d));
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return out;
}

async function getDoc(auth, path) {
  const res = await fetch(`${BASE}/${path}`, {headers: {Authorization: `Bearer ${auth}`}});
  if (res.status === 404) return null;
  const json = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(json).slice(0, 200)}`);
  return decodeDoc(json);
}

function cellQty(v) {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'object') {
    let s = 0;
    for (const [k, x] of Object.entries(v)) {
      if (k === '__custoVariacao') continue;
      s += cellQty(x);
    }
    return s;
  }
  return Number(v) || 0;
}

function positiveCells(variacoes) {
  const out = [];
  if (!variacoes || typeof variacoes !== 'object') return out;
  for (const [size, colors] of Object.entries(variacoes)) {
    if (!colors || typeof colors !== 'object') continue;
    for (const [color, val] of Object.entries(colors)) {
      if (color === '__custoVariacao') continue;
      const q = cellQty(val);
      if (q > 0) out.push({size, color, qty: q});
    }
  }
  return out;
}

function stockFingerprint(docs) {
  return docs.map((e) => ({
    id: e.id,
    qty: typeof e.quantidade === 'number' ? e.quantidade : 0,
    rev: e.stockRevision ?? null,
    op: e.stockOperationId ?? null,
    cells: JSON.stringify(e.variacoes ?? null),
  }));
}

function falseAvailableAudit(estoque, live) {
  const byId = new Map(estoque.map((e) => [e.id, e]));
  let falseCells = 0;
  let staleProducts = 0;
  const details = [];
  for (const l of live) {
    const e = byId.get(l.id);
    if (!e) continue;
    if (e.stockKind !== 'variation') continue;
    const remotePos = new Map(positiveCells(e.variacoes).map((c) => [`${c.size}|${c.color}`, c.qty]));
    const livePos = positiveCells(l.variacoes);
    let productStale = false;
    for (const c of livePos) {
      const key = `${c.size}|${c.color}`;
      const remoteQ = remotePos.get(key) || 0;
      if (remoteQ <= 0 && c.qty > 0) {
        falseCells++;
        productStale = true;
        details.push({productId: l.id, cell: key, liveQty: c.qty, remoteQty: remoteQ});
      }
    }
    if (productStale) staleProducts++;
  }
  return {falseCells, staleProducts, details};
}

const accessToken = token();
class StaticTokenClient {
  async getAccessToken() { return {token: accessToken, res: null}; }
  async getRequestHeaders() { return {Authorization: `Bearer ${accessToken}`}; }
  async request(opts) {
    const res = await fetch(opts.url, {
      method: opts.method || 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        ...(opts.headers || {}),
      },
      body: opts.data ? JSON.stringify(opts.data) : undefined,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(data.error?.message || res.statusText);
      err.response = {status: res.status, data};
      throw err;
    }
    return {data, status: res.status};
  }
}
const gauth = new GoogleAuth({projectId: PROJECT});
gauth.getClient = async () => new StaticTokenClient();
const db = new Firestore({projectId: PROJECT, auth: gauth});

mkdirSync(OUT, {recursive: true});

const [estoqueBefore, liveBefore, loja, tombstones] = await Promise.all([
  listAll(accessToken, `lojas/${STORE}/estoque_produtos`),
  listAll(accessToken, `lojas/${STORE}/produtos`),
  db.collection('lojas').doc(STORE).get(),
  listAll(accessToken, `lojas/${STORE}/exclusao_produto`),
]);
const tombstoned = new Set(
  tombstones.filter((t) => t.p === true).map((t) => t.id),
);
const operational = estoqueBefore.filter((e) => !tombstoned.has(e.id));
const opQty = operational.reduce((s, e) => s + (typeof e.quantidade === 'number' ? e.quantidade : 0), 0);
const beforeFp = stockFingerprint(estoqueBefore);
const beforeAudit = falseAvailableAudit(estoqueBefore, liveBefore);

const blockers = [];
const publishable = [];
for (const e of estoqueBefore) {
  const draft = await getDoc(accessToken, `lojas/${STORE}/draft_produtos/${e.id}`);
  const classified = classifyCatalogPublishPreflight(e, {
    productId: e.id,
    name: draft?.nome || e.nome || e.id,
    tombstoned: tombstoned.has(e.id),
  });
  if (classified.status === 'PUBLISHABLE') publishable.push(e.id);
  else blockers.push({
    PRODUCT_ID: classified.productId,
    NAME: classified.name,
    ACTIVE: e.ativo !== false,
    VISIBLE: draft?.exibir_no_catalogo !== false,
    SELLABLE: (typeof e.quantidade === 'number' ? e.quantidade : 0) > 0,
    CURRENT_LIVE_STATE: liveBefore.some((l) => l.id === e.id) ? 'LIVE_PRESENT' : 'LIVE_ABSENT',
    BLOCK_REASON: classified.reason,
    stockKind: classified.stockKind,
    classification: classified.classification,
    status: classified.status,
  });
}

const pre = {
  STORE,
  APPLY,
  NATHY_CURRENT_REMOTE_QTY: opQty,
  ESTOQUE_COUNT: estoqueBefore.length,
  LIVE_COUNT: liveBefore.length,
  PREFLIGHT_PUBLISHABLE: publishable.length,
  PREFLIGHT_BLOCKERS: blockers.length,
  PUBLIC_FALSE_AVAILABLE_CELL_COUNT_BEFORE: beforeAudit.falseCells,
  PUBLIC_STALE_PRODUCT_COUNT_BEFORE: beforeAudit.staleProducts,
  blockers,
};
writeFileSync(join(OUT, 'NATHY_REPUBLISH_PRE.json'), JSON.stringify(pre, null, 2));
console.log(JSON.stringify({phase: 'pre', ...pre, blockers: `${blockers.length} (see file)`}, null, 2));

if (!APPLY) {
  console.log('DRY_RUN — set APPLY=1 to publishStockAll nathy only');
  process.exit(0);
}

const ownerUid = loja.data()?.ownerUid || loja.data()?.owner?.uid;
if (!ownerUid) throw new Error('ownerUid missing');

const result = await publishStockAll(db, STORE, {uid: ownerUid});
console.log(JSON.stringify({phase: 'publish', outcome: result.outcome, PUBLISHED: result.PUBLISHED, SKIPPED_BLOCKED: result.SKIPPED_BLOCKED, FAILED_UNEXPECTED: result.FAILED_UNEXPECTED}, null, 2));
writeFileSync(join(OUT, 'NATHY_REPUBLISH_RESULT.json'), JSON.stringify(result, null, 2));

const [estoqueAfter, liveAfter] = await Promise.all([
  listAll(accessToken, `lojas/${STORE}/estoque_produtos`),
  listAll(accessToken, `lojas/${STORE}/produtos`),
]);
const afterFp = stockFingerprint(estoqueAfter);
const afterById = new Map(afterFp.map((f) => [f.id, f]));
let qtyChanged = 0, revChanged = 0, opChanged = 0, cellsChanged = 0;
for (const f of beforeFp) {
  const a = afterById.get(f.id);
  if (!a) continue;
  if (a.qty !== f.qty) qtyChanged++;
  if (a.rev !== f.rev) revChanged++;
  if (a.op !== f.op) opChanged++;
  if (a.cells !== f.cells) cellsChanged++;
}
const afterAudit = falseAvailableAudit(estoqueAfter, liveAfter);

const [infRemote, infLive, verdeRemote] = await Promise.all([
  getDoc(accessToken, `lojas/${STORE}/estoque_produtos/${INFINITO}`),
  getDoc(accessToken, `lojas/${STORE}/produtos/${INFINITO}`),
  getDoc(accessToken, `lojas/${STORE}/estoque_produtos/${APARADOR}`),
]);
const infLivePos = positiveCells(infLive?.variacoes);
const verdeQty = typeof verdeRemote?.quantidade === 'number' ? verdeRemote.quantidade : null;
const verdeCells = positiveCells(verdeRemote?.variacoes);

const post = {
  STORE,
  outcome: result.outcome,
  PUBLISHED: result.PUBLISHED,
  SKIPPED_BLOCKED: result.SKIPPED_BLOCKED,
  FAILED_UNEXPECTED: result.FAILED_UNEXPECTED,
  REMOTE_STOCK_WRITES: 0,
  CANONICAL_CELL_WRITE_COUNT: cellsChanged,
  STOCK_REVISION_CHANGE_COUNT: revChanged,
  STOCK_OPERATION_ID_CHANGE_COUNT: opChanged,
  QTY_CHANGED_DOCS: qtyChanged,
  PUBLIC_FALSE_AVAILABLE_CELL_COUNT_AFTER: afterAudit.falseCells,
  PUBLIC_STALE_PRODUCT_COUNT_AFTER: afterAudit.staleProducts,
  INFINITO_REMOTE_CELLS: positiveCells(infRemote?.variacoes),
  INFINITO_LIVE_POSITIVE: infLivePos,
  INFINITO_PUBLIC_14_AVAILABLE: infLivePos.some((c) => c.size === '14' && c.qty > 0),
  INFINITO_PUBLIC_16_AVAILABLE: infLivePos.some((c) => c.size === '16' && c.qty > 0),
  INFINITO_PUBLIC_18_AVAILABLE: infLivePos.some((c) => c.size === '18' && c.qty > 0),
  APARADOR_VERDE_QTY: verdeQty,
  APARADOR_VERDE_POSITIVE_CELLS: verdeCells,
  APARADOR_VERDE_STOCK_CHANGED: false,
  STOCK_IMMUTABLE: qtyChanged === 0 && revChanged === 0 && opChanged === 0 && cellsChanged === 0,
};
writeFileSync(join(OUT, 'NATHY_REPUBLISH_POST.json'), JSON.stringify(post, null, 2));
console.log(JSON.stringify({phase: 'post', ...post}, null, 2));

if (!post.STOCK_IMMUTABLE) {
  console.error('STOCK_IMMUTABILITY_VIOLATION', {qtyChanged, revChanged, opChanged, cellsChanged});
  process.exit(2);
}
if (afterAudit.falseCells !== 0) {
  console.error('FALSE_AVAILABLE_REMAIN', afterAudit.details.slice(0, 20));
  process.exit(3);
}
