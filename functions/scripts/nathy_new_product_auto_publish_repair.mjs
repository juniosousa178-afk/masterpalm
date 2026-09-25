/**
 * Nathy — catalog-only republish of 4 affected new products (NO_CONTROL / legacyCompat).
 * STOCK_WRITES=0 — only draft_produtos / produtos via publishStockProduct.
 *
 * APPLY=1 to write; default is preflight-only.
 */
import {execFileSync} from 'node:child_process';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {mkdirSync, writeFileSync} from 'node:fs';
import {Firestore} from '@google-cloud/firestore';
import {GoogleAuth} from 'google-auth-library';
import {
  classifyCatalogPublishPreflight,
  publishStockProduct,
} from '../src/stockCatalogCommands.js';
import {
  hasExplicitPublicationIntent,
  publicationIntentSourceField,
} from '../src/catalogStockProjection.js';

const PROJECT = 'masterpalm-58c46';
const STORE = 'nathy-pratas-e-folheados';
const APPLY = process.env.APPLY === '1';
const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '../../artifacts/nathy_stabilization_20260924');

const TARGETS = [
  'nathy-pratas-e-folheados-pulseira-2-cora-o-cristal-semijoia',
  'nathy-pratas-e-folheados-colar-cora-o-vermelho-semijoia',
  'nathy-pratas-e-folheados-colar-2-cora-o-cristal',
  'nathy-pratas-e-folheados-kit-a-o-verde',
];

function token() {
  if (process.env.GOOGLE_CLOUD_TOKEN) return process.env.GOOGLE_CLOUD_TOKEN.trim();
  const helper = join(__dirname, '_gcloud_access_token.ps1');
  const out = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', helper], {
    encoding: 'utf8', windowsHide: true, maxBuffer: 2 * 1024 * 1024,
  });
  return String(out || '').trim().split(/\r?\n/).filter(Boolean).pop();
}

function presentUid(v) {
  const s = (v ?? '').toString().trim();
  return s || null;
}

async function resolvePublishAuth(db) {
  const base = db.collection('lojas').doc(STORE);
  const loja = await base.get();
  const data = loja.data() || {};
  const ownerUid = presentUid(data.ownerUid) || presentUid(data.owner?.uid);
  if (ownerUid) return {uid: ownerUid};
  const members = await base.collection('members').get();
  for (const d of members.docs) {
    const m = d.data() || {};
    if (m.role === 'owner' || m.role === 'admin' || m.tipo === 'owner' || m.tipo === 'admin') {
      return {uid: d.id};
    }
  }
  throw new Error('No owner/admin for NO_CONTROL publish');
}

function stockFingerprint(data) {
  return {
    quantidade: data?.quantidade ?? null,
    stockRevision: data?.stockRevision ?? null,
    stockOperationId: data?.stockOperationId ?? null,
    variacoes: data?.variacoes ?? null,
    estoquePorTamanho: data?.estoquePorTamanho ?? null,
    publicadoNoCatalogo: data?.publicadoNoCatalogo ?? null,
  };
}

function cellsChanged(before, after) {
  return JSON.stringify(before?.variacoes ?? null) !== JSON.stringify(after?.variacoes ?? null)
    || JSON.stringify(before?.estoquePorTamanho ?? null) !== JSON.stringify(after?.estoquePorTamanho ?? null);
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
process.env.GOOGLE_CLOUD_PROJECT = PROJECT;
const auth = await resolvePublishAuth(db);
const base = db.collection('lojas').doc(STORE);

const results = [];
let republished = 0;
let skipped = 0;
let qtyChanged = 0;
let cellChanged = 0;
let revChanged = 0;
let opChanged = 0;
let catalogWrites = 0;

for (const productId of TARGETS) {
  const sref = base.collection('estoque_produtos').doc(productId);
  const dref = base.collection('draft_produtos').doc(productId);
  const lref = base.collection('produtos').doc(productId);
  const tref = base.collection('exclusao_produto').doc(productId);
  const [stockSnap, draftSnap, liveSnap, tombSnap] = await Promise.all([
    sref.get(), dref.get(), lref.get(), tref.get(),
  ]);
  const stock = stockSnap.exists ? stockSnap.data() : null;
  const draft = draftSnap.exists ? draftSnap.data() : null;
  const before = stockFingerprint(stock);
  const tombstoneP = tombSnap.exists && tombSnap.data()?.p === true;
  const preflight = stock
    ? classifyCatalogPublishPreflight(stock, {productId, name: stock.nome, tombstoned: tombstoneP})
    : {status: 'MISSING'};
  const intent = hasExplicitPublicationIntent(stock || {}, draft || {});
  const intentField = publicationIntentSourceField(stock || {}, draft || {});
  const pending = stock?.pendingStockOperationId ?? null;

  const row = {
    PRODUCT_ID: productId,
    REMOTE_EXISTS: stockSnap.exists,
    TOMBSTONE_P: tombstoneP,
    PREFLIGHT: preflight.status,
    STOCK_STRUCTURE_VALID: preflight.status === 'PUBLISHABLE',
    PENDING_OPERATION_ID: pending,
    PUBLICATION_INTENT: intent,
    PUBLICATION_INTENT_SOURCE_FIELD: intentField,
    REMOTE_QTY: stock?.quantidade ?? null,
    BEFORE: before,
    SKIP_REASON: null,
    PUBLIC_DOC_EXISTS: liveSnap.exists,
    PUBLIC_QTY: liveSnap.exists ? liveSnap.data()?.quantidade ?? null : null,
    PUBLIC_VISIBLE: null,
    REPUBLISHED: false,
  };

  if (!stockSnap.exists) {
    row.SKIP_REASON = 'REMOTE_EXISTS=false';
    skipped++;
    results.push(row);
    continue;
  }
  if (tombstoneP) {
    row.SKIP_REASON = 'TOMBSTONE_P=true';
    skipped++;
    results.push(row);
    continue;
  }
  if (preflight.status !== 'PUBLISHABLE') {
    row.SKIP_REASON = `PREFLIGHT=${preflight.status}`;
    skipped++;
    results.push(row);
    continue;
  }
  if (pending != null && String(pending).trim() !== '') {
    row.SKIP_REASON = `PENDING_OPERATION_ID=${pending}`;
    skipped++;
    results.push(row);
    continue;
  }
  if (!intent) {
    row.SKIP_REASON = 'PUBLICATION_INTENT=false';
    skipped++;
    results.push(row);
    continue;
  }

  if (APPLY) {
    await publishStockProduct(db, STORE, productId, auth);
    catalogWrites += 1;
    row.REPUBLISHED = true;
    republished++;
    row.SKIP_REASON = null;
  } else {
    row.SKIP_REASON = 'DRY_RUN_WOULD_PUBLISH';
  }

  const [stockAfter, liveAfter] = await Promise.all([sref.get(), lref.get()]);
  const after = stockFingerprint(stockAfter.exists ? stockAfter.data() : null);
  row.AFTER = after;
  if (before.quantidade !== after.quantidade) qtyChanged++;
  if (cellsChanged(before, after)) cellChanged++;
  if (before.stockRevision !== after.stockRevision) revChanged++;
  if (before.stockOperationId !== after.stockOperationId) opChanged++;
  row.PUBLIC_DOC_EXISTS = liveAfter.exists;
  row.PUBLIC_QTY = liveAfter.exists ? liveAfter.data()?.quantidade ?? null : null;
  const live = liveAfter.exists ? liveAfter.data() : null;
  row.PUBLIC_VISIBLE = !!(live && live.ativo !== false && live.publicadoNoCatalogo !== false && (live.quantidade ?? 0) > 0);
  row.PUBLIC_VARIATIONS = live?.variacoes ?? null;
  results.push(row);
}

const report = {
  STORE_ID: STORE,
  APPLY,
  AFFECTED_TARGET_COUNT: 4,
  AFFECTED_REPUBLISHED_COUNT: republished,
  AFFECTED_SKIPPED_COUNT: skipped,
  CATALOG_WRITES: catalogWrites,
  STOCK_WRITES: 0,
  QTY_CHANGED_PRODUCT_COUNT: qtyChanged,
  CELL_CHANGED_PRODUCT_COUNT: cellChanged,
  REVISION_CHANGED_PRODUCT_COUNT: revChanged,
  OPERATION_ID_CHANGED_PRODUCT_COUNT: opChanged,
  ZERO_STOCK_PUBLIC_POLICY: 'qty_gt_0_required',
  PUBLICATION_INTENT_SOURCE_FIELD: 'draft.publicadoNoCatalogo|stock.publicadoNoCatalogo',
  PRODUCTS: results,
};

const outPath = join(OUT, APPLY
  ? 'NATHY_NEW_PRODUCT_AUTO_PUBLISH_REPAIR.json'
  : 'NATHY_NEW_PRODUCT_AUTO_PUBLISH_PREFLIGHT.json');
writeFileSync(outPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
await db.terminate();
