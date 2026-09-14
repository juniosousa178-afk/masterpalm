/** Offline migration planner. No Admin SDK, credentials, network or write executor.
 * Importing this module is inert. A future authorized cutover must acquire and
 * attest a frozen inventory and review this plan before implementing execution.
 */
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {readFileSync} from 'node:fs';
import {documentId} from '../src/stockCatalogAccess.js';
import {EDITORIAL_FIELDS, inferStockKind, isMap, normalizeStock, projectCatalog, quantity, validateEditorial} from '../src/catalogStockProjection.js';
import {recipe, comboOrder, recalculateFixedCombos} from '../src/stockCatalogCombo.js';

const permissions = new Set(['sale','restock','adjust','restore','editorial','create','delete','undo','publish']);
const ordered = v => Array.isArray(v) ? v.map(ordered) : isMap(v)
  ? Object.fromEntries(Object.keys(v).sort().map(k => [k, ordered(v[k])])) : v;
const digest = v => createHash('sha256').update(JSON.stringify(ordered(v))).digest('hex');
const editorial = p => Object.fromEntries(EDITORIAL_FIELDS.filter(k => k in p).map(k => [k, p[k]]));

/** Input consists of offline, complete store collections, never a client payload.
 * Attestations are audit requirements, NOT proof of deployed Rules or IAM.
 * Any unresolved legacy operation or partial tombstone blocks the whole plan:
 * this planner cannot invent an original intent or assume a debit never ran.
 */
export function planStockCatalogMigration(snapshot, ownershipManifest) {
  const blockers = [], warnings = [], writes = [];
  const block = (code, id = null) => blockers.push({code, id});
  if (!isMap(snapshot)) throw new TypeError('Offline snapshot required');
  const lojaId = documentId(snapshot.lojaId, 'lojaId');
  const base = `lojas/${lojaId}`;
  const inventoryHash = digest(snapshot);
  if (snapshot.control?.mode !== 'maintenance') block('MAINTENANCE_REQUIRED');
  for (const key of ['inventoryComplete','backupVerified','directWritesDenied','legacyAdminWritersDrained']) {
    if (snapshot.attestations?.[key] !== true) block(`ATTESTATION_REQUIRED:${key}`);
  }
  for (const name of ['stock','draft','live','tombstones','legacyOperations','pendingIntents','orders','access']) {
    if (!isMap(snapshot[name])) block(`COMPLETE_COLLECTION_REQUIRED:${name}`);
  }
  if (Object.keys(snapshot.legacyOperations ?? {}).length || Object.keys(snapshot.pendingIntents ?? {}).length) {
    block('LEGACY_OPERATIONS_AND_PENDING_INTENTS_REQUIRE_RECONCILIATION');
  }
  // Even an unpaid order may already have a manual stock debit. Do not infer
  // replay safety from its payment status or a client-writable legacy marker.
  if (Object.keys(snapshot.orders ?? {}).length) block('EXISTING_ORDERS_REQUIRE_OPERATION_ID_RECONCILIATION');
  if (!isMap(ownershipManifest) || ownershipManifest.lojaId !== lojaId ||
      typeof ownershipManifest.evidenceId !== 'string' || !ownershipManifest.evidenceId.trim() ||
      !isMap(ownershipManifest.grants) || !Object.keys(ownershipManifest.grants).length) {
    block('INDEPENDENT_OWNERSHIP_MANIFEST_REQUIRED');
  } else for (const [uid, grant] of Object.entries(ownershipManifest.grants)) {
    try {
      documentId(uid, 'uid');
      if (!isMap(grant) || grant.enabled !== true || !isMap(grant.permissions) ||
          Object.keys(grant).some(k => !['enabled','permissions'].includes(k)) ||
          !Object.keys(grant.permissions).length ||
          Object.entries(grant.permissions).some(([k,v]) => !permissions.has(k) || typeof v !== 'boolean')) throw new Error();
      writes.push({action: 'set', path: `${base}/stock_catalog_access/${uid}`, data: grant});
    } catch {block('INVALID_TRUSTED_GRANT', uid);}
  }
  if (isMap(ownershipManifest?.grants)) {
    for (const [uid, permission] of [['stock-catalog-publisher','publish'], ['stock-catalog-payment','sale']]) {
      if (ownershipManifest.grants[uid]?.enabled !== true || ownershipManifest.grants[uid]?.permissions?.[permission] !== true) {
        block('REQUIRED_SERVICE_GRANT_MISSING', uid);
      }
    }
    for (const uid of Object.keys(snapshot.access ?? {})) {
      try {
        documentId(uid, 'uid');
        if (!Object.hasOwn(ownershipManifest.grants, uid)) writes.push({action: 'delete', path: `${base}/stock_catalog_access/${uid}`});
      } catch {block('INVALID_EXISTING_ACCESS_ID', uid);}
    }
  }
  const records = new Map(), metas = new Map();
  for (const [id, raw] of Object.entries(snapshot.stock ?? {})) {
    try {
      documentId(id);
      if (!isMap(raw) || [raw.id, raw.idFirebase].some(v => v != null && v !== '' && v !== id)) throw new Error('CANONICAL_ID_CONFLICT');
      if (raw.lojaId != null && raw.lojaId !== lojaId) throw new Error('CROSS_STORE_CANONICAL');
      if (raw.pendingStockOperationId || raw.stockConflict === true) throw new Error('PENDING_CANONICAL_INTENT');
      const kind = raw.stockKind ?? inferStockKind(raw);
      // A variable product with no usable grade is ambiguous, not evidence of 0.
      if (kind === 'variation' && raw.variacoes == null &&
          !Object.keys(raw.estoquePorTamanho ?? {}).length && !Object.keys(raw.estoquePorCor ?? {}).length) {
        throw new Error('MISSING_CANONICAL_GRADE');
      }
      const stockRevision = raw.stockRevision ?? 0;
      quantity(stockRevision);
      const stock = normalizeStock({...raw, stockKind: kind, stockRevision});
      if (raw.stockRevision == null) warnings.push({code: 'INITIALIZE_REVISION_ZERO_AFTER_FREEZE', id});
      const tomb = snapshot.tombstones?.[id];
      if (tomb !== undefined) {
        if (!isMap(tomb) || tomb.p !== true) throw new Error('PARTIAL_TOMBSTONE_REQUIRES_RECONCILIATION');
        stock.pendingSoftDelete = true;
      }
      // Prefer the canonical editorial draft. Do not borrow stock from it.
      const draft = snapshot.draft?.[id];
      const meta = {...editorial(raw), ...(isMap(draft) ? editorial(draft) : {})};
      if (typeof meta.publicadoNoCatalogo !== 'boolean') throw new Error('PUBLICATION_INTENT_REQUIRED');
      validateEditorial(meta);
      records.set(id, {data: stock}); metas.set(id, meta);
    } catch (error) {block(error.message, id);}
  }
  for (const id of Object.keys(snapshot.tombstones ?? {})) {
    if (!Object.hasOwn(snapshot.stock ?? {}, id)) block('ORPHAN_TOMBSTONE_REQUIRES_RECONCILIATION', id);
  }
  // Delete only proven copies. Name or a matching slug alone is not ownership.
  for (const collection of ['draft','live']) for (const [id, data] of Object.entries(snapshot[collection] ?? {})) {
    try {
      documentId(id);
      if (!isMap(data)) throw new Error('INVALID_CATALOG_DOCUMENT');
      if (data.lojaId != null && data.lojaId !== lojaId) throw new Error('CROSS_STORE_CATALOG');
      const hints = [...new Set([data.id, data.productId, data.idFirebase].filter(v => v != null && v !== ''))];
      if (hints.length > 1) throw new Error('CONFLICTING_CATALOG_IDENTITIES');
      const ownerId = Object.hasOwn(snapshot.stock ?? {}, id) ? id : hints[0];
      if (data.vendasCatalogoTotal !== undefined) {
        quantity(data.vendasCatalogoTotal);
        const canonicalCount = snapshot.stock?.[ownerId]?.vendasCatalogoTotal;
        if (canonicalCount === undefined || canonicalCount !== data.vendasCatalogoTotal) {
          throw new Error('CATALOG_COUNTER_REQUIRES_RECONCILIATION');
        }
      }
      if (Object.hasOwn(snapshot.stock ?? {}, id)) {
        if (hints.length && hints[0] !== id) throw new Error('CATALOG_ID_COLLISION');
      } else {
        const owner = hints[0];
        if (!owner || !records.has(owner) || records.get(owner).data.slug !== id) throw new Error('UNPROVEN_LEGACY_COPY');
        writes.push({action: 'delete', path: `${base}/${collection === 'draft' ? 'draft_produtos' : 'produtos'}/${id}`, canonicalOwner: owner});
      }
    } catch (error) {block(error.message, `${collection}/${id}`);}
  }
  try {
    comboOrder(records); recalculateFixedCombos(records, -1);
    const dependencies = new Map([...records.keys()].map(id => [id, new Set()]));
    for (const [id, {data}] of records) for (const item of recipe(data)) dependencies.get(item.productId).add(id);
    for (const root of records.keys()) {
      const visited = new Set(), pending = [root];
      while (pending.length && visited.size <= 25) {
        const id = pending.pop(); if (visited.has(id)) continue; visited.add(id);
        pending.push(...dependencies.get(id), ...recipe(records.get(id).data).map(item => item.productId));
      }
      if (visited.size > 25) block('CONNECTED_COMPONENT_EXCEEDS_TRANSACTION_BUDGET', root);
    }
    for (const [id, {data}] of records) {
      const projected = projectCatalog(data, metas.get(id), id);
      writes.push({action: 'set', path: `${base}/estoque_produtos/${id}`, data: projected.stock});
      writes.push({action: 'set', path: `${base}/draft_produtos/${id}`, data: projected.draft});
      writes.push(projected.live ? {action: 'set', path: `${base}/produtos/${id}`, data: projected.live}
        : {action: 'delete', path: `${base}/produtos/${id}`});
      writes.push({action: 'set', path: `${base}/stock_catalog_dependencies/${id}`, data: {comboIds: [...dependencies.get(id)].sort()}});
    }
  } catch (error) {block(error.message);}
  // Activation is a separate, future authorized step after re-reading and
  // verifying every planned document; never include active in a dry-run plan.
  const acceptedWrites = blockers.length ? [] : writes.sort((a,b) => a.path.localeCompare(b.path));
  const result = {dryRun: true, executable: false, lojaId, inventoryHash,
    ownershipManifestHash: digest(ownershipManifest ?? null),
    status: blockers.length ? 'BLOCKED' : 'PLAN_READY_FOR_REVIEW', blockers, warnings,
    writes: acceptedWrites, activationIncluded: false, dataMigrationExecuted: false};
  return {...result, planHash: digest(result)};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 4 || process.argv.some(arg => arg === '--apply')) {
    throw new Error('Dry-run only: node migrate_stock_catalog_protocol.js offline-snapshot.json verified-ownership.json');
  }
  const plan = planStockCatalogMigration(JSON.parse(readFileSync(process.argv[2], 'utf8')),
    JSON.parse(readFileSync(process.argv[3], 'utf8')));
  process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`);
  process.exitCode = plan.status === 'BLOCKED' ? 2 : 0;
}
