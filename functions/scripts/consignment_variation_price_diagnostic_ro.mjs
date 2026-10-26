/**
 * READ-ONLY: counts consignments whose variation lines may carry the product price
 * instead of the selected variation price. No writes, no fixes, no migration.
 * Products are always read from the consignment's own store (lojas/{lojaId}/...).
 * Stdout prints aggregate counts only; IDs for manual review go to a local artifact.
 */
import {execFileSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {mkdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {diagnoseConsignment, summarizeConsignmentDiagnostics} from '../src/consignmentVariationPriceDiagnostic.js';

const PROJECT = 'masterpalm-58c46';
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = `https://firestore.googleapis.com/v1/${ROOT}`;
const __dirname = dirname(fileURLToPath(import.meta.url));
// Outside the repo: the review file lists store/consignment ids and must never be committed.
const OUT = join(tmpdir(), 'mp_consignment_variation_price');

function token() {
  if (process.env.GOOGLE_CLOUD_TOKEN) return process.env.GOOGLE_CLOUD_TOKEN.trim();
  const helper = join(__dirname, '_gcloud_access_token.ps1');
  const out = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', helper], {
    encoding: 'utf8', windowsHide: true, maxBuffer: 2 * 1024 * 1024,
  });
  return String(out || '').trim().split(/\r?\n/).filter(Boolean).pop();
}

function decodeValue(v) {
  if (v == null || 'nullValue' in v) return null;
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
const decodeFields = doc => Object.fromEntries(Object.entries(doc?.fields || {}).map(([k, v]) => [k, decodeValue(v)]));

async function postJson(url, auth, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: {Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return text ? JSON.parse(text) : null;
}

async function* allConsignments(auth) {
  let last = null;
  for (;;) {
    const structuredQuery = {
      from: [{collectionId: 'consignments', allDescendants: true}],
      orderBy: [{field: {fieldPath: '__name__'}, direction: 'ASCENDING'}],
      limit: 300,
      ...(last ? {startAt: {values: [{referenceValue: last}], before: false}} : {}),
    };
    const rows = await postJson(`${BASE}:runQuery`, auth, {structuredQuery});
    const docs = (rows || []).map(r => r.document).filter(Boolean);
    for (const d of docs) yield d;
    if (docs.length < 300) return;
    last = docs[docs.length - 1].name;
  }
}

async function batchGet(auth, names) {
  const found = new Map();
  for (let i = 0; i < names.length; i += 100) {
    const rows = await postJson(`${BASE}:batchGet`, auth, {documents: names.slice(i, i + 100)});
    for (const r of rows || []) if (r.found) found.set(r.found.name, decodeFields(r.found));
  }
  return found;
}

async function main() {
  const auth = token();
  const byStore = new Map();
  for await (const doc of allConsignments(auth)) {
    const m = doc.name.slice(ROOT.length + 1).split('/');
    if (m.length !== 4 || m[0] !== 'lojas' || m[2] !== 'consignments') continue;
    const list = byStore.get(m[1]) || [];
    list.push({id: m[3], data: decodeFields(doc)});
    byStore.set(m[1], list);
  }

  const results = [];
  const review = [];
  for (const [lojaId, consignments] of byStore) {
    const ids = new Set();
    for (const c of consignments) {
      for (const l of Array.isArray(c.data.lines) ? c.data.lines : []) {
        const vk = l?.variationKey;
        if (vk && ['size', 'color', 'extra'].some(k => String(vk[k] ?? '').trim()) && l.productId) ids.add(String(l.productId));
      }
    }
    const names = [];
    for (const id of ids) {
      names.push(`${ROOT}/lojas/${lojaId}/draft_produtos/${id}`, `${ROOT}/lojas/${lojaId}/estoque_produtos/${id}`);
    }
    const found = names.length ? await batchGet(auth, names) : new Map();
    const products = new Map();
    for (const id of ids) {
      products.set(id, {
        draft: found.get(`${ROOT}/lojas/${lojaId}/draft_produtos/${id}`) || null,
        stock: found.get(`${ROOT}/lojas/${lojaId}/estoque_produtos/${id}`) || null,
      });
    }
    for (const c of consignments) {
      const storeId = String(c.data.storeId || '').trim();
      if (storeId && storeId !== lojaId) continue;
      const result = diagnoseConsignment(c.data, products);
      results.push({status: c.data.status, result});
      if (result.affected) {
        review.push({lojaId, consignmentId: c.id, status: c.data.status || 'UNKNOWN', ...result});
      }
    }
  }

  const summary = {stores: byStore.size, ...summarizeConsignmentDiagnostics(results)};
  mkdirSync(OUT, {recursive: true});
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  writeFileSync(join(OUT, `diagnostic_${stamp}.json`), JSON.stringify({summary, review}, null, 2));
  console.log(JSON.stringify(summary, null, 2));
}

main().catch(err => {
  console.error(`DIAGNOSTIC_FAILED ${err?.message || err}`);
  process.exitCode = 1;
});
