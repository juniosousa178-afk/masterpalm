import {recipe, componentIntents, comboOrder, recalculateFixedCombos} from './stockCatalogCombo.js';
import {createHash} from 'node:crypto';
import {FieldValue} from 'firebase-admin/firestore';
import {documentId, storeRef, requireAuthenticated, authorizeStockCommand, authorizePublish, SERVER_PAYMENT_AUTH} from './stockCatalogAccess.js';
import {isMap, stockError, normalizeStock, projectCatalog, quantity, resolveKey, resolveExtraKey, validateEditorial, inferStockKind} from './catalogStockProjection.js';
import {PRODUCT_VALIDATION_FAILED, REASON, makeIssue, productValidationError, gradeKeyLabel} from './productValidationErrors.js';
import {ATOMIC_PDV_SALE_FLAG, parseAtomicPdvSale, buildCanonicalEstoqueVendaDoc} from './stockCatalogPdvSale.js';

const MAX_PRODUCTS = 25;
const ordered = value => Array.isArray(value) ? value.map(ordered) : isMap(value)
  ? Object.fromEntries(Object.keys(value).sort().map(k => [k, ordered(value[k])])) : value;
const fingerprint = value => createHash('sha256').update(JSON.stringify(ordered(value))).digest('hex');
const stockEffect = p => Object.fromEntries(['quantidade','variacoes','estoquePorTamanho','estoquePorCor',
  'tamanhos','cores','variacoesExtraTipo','tipoProduto','stockKind','itensCombo','comboConfig','pendingSoftDelete']
  .filter(key => key in p).map(key => [key, p[key]]));
function keysOnly(data, allowed) {
  if (!isMap(data) || Object.keys(data).some(k => !allowed.includes(k))) throw stockError('invalid-argument', 'Unknown or protected command field');
}
function parseCommand(raw) {
  keysOnly(raw, ['protocolVersion','lojaId','operationId','kind','items','sourceOperationId','editorial','definition','tombstoneKeys', ATOMIC_PDV_SALE_FLAG, 'sale']);
  if (raw.protocolVersion !== 1) throw stockError('failed-precondition', 'Unsupported stock protocol');
  documentId(raw.lojaId, 'lojaId'); documentId(raw.operationId, 'operationId');
  if (!['sale','restock','adjust','restore','editorial','create','replace','delete','undo','tombstoneVariation','clearVariationTombstone'].includes(raw.kind)) {
    throw stockError('invalid-argument', 'Unsupported command');
  }
  if (!Array.isArray(raw.items) || raw.items.length === 0 || raw.items.length > 100) throw stockError('invalid-argument', 'Invalid items');
  const items = raw.items.map(item => {
    keysOnly(item, ['productId','quantity','size','color','extra','expectedRevision','selection']);
    documentId(item.productId, 'productId');
    for (const key of ['size','color','extra']) if (key in item && typeof item[key] !== 'string') throw stockError('invalid-argument', 'Invalid variation selector');
    if (['sale','restock','adjust'].includes(raw.kind)) {
      quantity(item.quantity);
      if (raw.kind !== 'adjust' && item.quantity === 0) throw stockError('invalid-argument', 'Quantity must be positive');
    }
    if (['adjust','replace','delete','undo','tombstoneVariation','clearVariationTombstone'].includes(raw.kind)) quantity(item.expectedRevision);
    return {...item, size: item.size ?? '', color: item.color ?? '', extra: item.extra ?? ''};
  });
  if (new Set(items.map(i => i.productId)).size > MAX_PRODUCTS) throw stockError('resource-exhausted', 'Too many affected products');
  if (raw.kind === 'restore') documentId(raw.sourceOperationId, 'sourceOperationId');
  if (['editorial','create','replace'].includes(raw.kind)) {
    if (items.length !== 1) throw stockError('invalid-argument', 'Editorial command requires one product');
    validateEditorial(raw.editorial);
  } else if ('editorial' in raw) throw stockError('invalid-argument', 'Editorial fields not allowed');
  if (['create','replace'].includes(raw.kind)) {
    keysOnly(raw.definition, ['quantidade','variacoes','estoquePorTamanho','estoquePorCor','tamanhos','cores',
      'variacoesExtraTipo','tipoProduto','itensCombo','comboConfig','custoReal','custo','precoCusto']);
    if (raw.items.length !== 1) throw stockError('invalid-argument', 'Single product definition required');
  } else if ('definition' in raw) throw stockError('invalid-argument', 'Definition only allowed for create or CAS replacement');
  let tombstoneKeys = null;
  if (['tombstoneVariation','clearVariationTombstone'].includes(raw.kind)) {
    if (items.length !== 1) throw stockError('invalid-argument', 'Variation tombstone requires one product');
    if (!Array.isArray(raw.tombstoneKeys) || raw.tombstoneKeys.length === 0 || raw.tombstoneKeys.length > 200) {
      throw stockError('invalid-argument', 'tombstoneKeys required');
    }
    for (const key of raw.tombstoneKeys) {
      if (typeof key !== 'string' || !key.trim() || key !== key.trim() || key.includes('/') || key.length > 200) {
        throw stockError('invalid-argument', 'Invalid tombstone key');
      }
    }
    tombstoneKeys = [...new Set(raw.tombstoneKeys)];
  } else if ('tombstoneKeys' in raw) {
    throw stockError('invalid-argument', 'tombstoneKeys only for variation tombstone commands');
  }
  let atomicPdvSale = false;
  let atomicSale = null;
  if (raw[ATOMIC_PDV_SALE_FLAG] === true) {
    if (raw.kind !== 'sale') throw stockError('invalid-argument', 'atomicPdvSale only for sale');
    atomicPdvSale = true;
    atomicSale = parseAtomicPdvSale(raw.sale, {
      operationId: raw.operationId, lojaId: raw.lojaId, stockItems: items,
    });
  } else {
    if (ATOMIC_PDV_SALE_FLAG in raw) {
      throw stockError('invalid-argument', 'atomicPdvSale must be true when set');
    }
    if ('sale' in raw) throw stockError('invalid-argument', 'sale requires atomicPdvSale=true');
  }
  if (Buffer.byteLength(JSON.stringify(raw)) > 100000) throw stockError('resource-exhausted', 'Command too large');
  return {...raw, items, tombstoneKeys, atomicPdvSale, atomicSale};
}
function technicalSimpleColor(value) {
  const n = String(value ?? '').trim().toLowerCase().replace(/\s+/gu, '');
  return !n || n === 'sem-cor' || n === 'semcor' || n === 'unico' || n === 'unique' || n === 'u';
}

function applyCell(stock, item, delta, absolute) {
  const next = normalizeStock(stock);
  if (next.pendingSoftDelete) throw stockError('failed-precondition', 'Product deleted');
  let map, key;
  if (next.stockKind === 'simple' || (next.stockKind === 'combo' && !Object.keys(next.variacoes ?? {}).length && !Object.keys(next.estoquePorTamanho).length && !Object.keys(next.estoquePorCor).length)) {
    if (item.size || item.color || item.extra) throw stockError('invalid-argument', 'Simple product cannot select a variation');
    next.quantidade = quantity(absolute ? delta : next.quantidade + delta);
    return next;
  }
  if (isMap(next.variacoes) && Object.keys(next.variacoes).length) {
    const size = resolveKey(next.variacoes, item.size) ?? (!item.size ? resolveKey(next.variacoes, 'sem-tamanho') : undefined);
    if (size !== undefined) {
      map = next.variacoes[size]; key = resolveKey(map, item.color) ?? (!item.color ? resolveKey(map, 'sem-cor') : undefined);
    }
    if (key === undefined && !item.size && Object.keys(next.estoquePorCor).length) {
      const inGrade = Object.values(next.variacoes).some(c => resolveKey(c, item.color) !== undefined);
      if (!inGrade) {map = next.estoquePorCor; key = resolveKey(map, item.color);}
    }
  } else if (Object.keys(next.estoquePorTamanho).length && item.size && !item.color) {
    map = next.estoquePorTamanho; key = resolveKey(map, item.size);
  } else if (Object.keys(next.estoquePorCor).length && !item.size) {
    map = next.estoquePorCor; key = resolveKey(map, item.color);
  }
  if (key === undefined) throw stockError('failed-precondition', 'Variation not found');
  if (isMap(map[key])) {
    if (!item.extra && resolveExtraKey(map[key], '') === undefined) throw stockError('invalid-argument', 'Extra dimension required');
    map = map[key]; key = resolveExtraKey(map, item.extra);
    if (key === undefined) throw stockError('failed-precondition', 'Extra variation not found');
  } else if (item.extra) throw stockError('invalid-argument', 'Unexpected extra dimension');
  map[key] = quantity(absolute ? delta : quantity(map[key]) + delta);
  return normalizeStock(next);
}

/** SDK retries can retain an expired transaction token after a lock timeout.
 * Restart the entire transaction only for that precise transport error. All
 * mutating callbacks carry a persisted operation ID; uncertain commits replay.
 */
export async function runStockTransaction(db, callback) {
  for (let attempt = 0; ; attempt++) {
    try { return await db.runTransaction(callback); }
    catch (error) {
      const closedToken = error.code === 3 && /Transaction is invalid or closed\./.test(error.details ?? error.message ?? '');
      if (!closedToken || attempt >= 2) throw error;
      await new Promise(resolve => setTimeout(resolve, 100 * (attempt + 1)));
    }
  }
}

/** No network work inside callbacks except transaction reads/writes. */
export async function executeStockCommand(db, raw, auth) {
  return runStockTransaction(db, tx => executeStockCommandInTransaction(tx, db, raw, auth));
}

/** Trusted callers may join order/marker writes after this method; all their reads must precede it. */
export async function executeStockCommandInTransaction(tx, db, raw, auth, reservedWrites = 0) {
  if (!Number.isInteger(reservedWrites) || reservedWrites < 0 || reservedWrites > 100) throw stockError('internal', 'Invalid transaction reservation');
  requireAuthenticated(auth);
  const command = parseCommand(raw), base = storeRef(db, command.lojaId);
  const hash = fingerprint(command);
    const permission = command.kind === 'replace' ? 'adjust'
      : command.kind === 'tombstoneVariation' ? 'delete'
      : command.kind === 'clearVariationTombstone' ? 'undo'
      : command.kind;
    const authz = await authorizeStockCommand(tx, db, base, auth, permission, command.kind);
    const uid = authz.uid;
    const legacyCompat = authz.legacyCompat === true;
    const opRef = base.collection('stock_catalog_operations').doc(command.operationId);
    const saleRef = command.atomicPdvSale
      ? base.collection('estoque_vendas').doc(command.operationId)
      : null;
    const op = await tx.get(opRef);
    // Atomic PDV: all reads precede writes — sale doc identity checked before mutation.
    const existingSale = saleRef ? await tx.get(saleRef) : null;
    if (op.exists && (op.data().requestHash !== hash || op.data().actorUid !== uid)) throw stockError('already-exists', 'Operation identity conflict');
    // Replays return current canonical values, even after later deletion/editing.
    // They never traverse a recipe that may have changed since the first commit.
    if (op.exists) {
      const products = [];
      for (const id of op.data().result.productIds) {
        const current = await tx.get(base.collection('estoque_produtos').doc(documentId(id)));
        if (current.exists) products.push({productId: id, ...normalizeStock(current.data())});
      }
      const replay = {alreadyApplied: true, operationId: command.operationId, products};
      if (command.atomicPdvSale) {
        replay.saleCommitted = true;
        replay.saleId = command.operationId;
        replay.authoritativeSalePersisted = true;
        replay.authoritativeStockCommitted = true;
      }
      return replay;
    }
    if (existingSale?.exists) {
      throw stockError('already-exists', 'Sale document conflict without applied operation');
    }
    let items = command.items, sourceRef, source;
    if (command.kind === 'restore') {
      sourceRef = base.collection('stock_catalog_operations').doc(command.sourceOperationId);
      source = await tx.get(sourceRef);
      if (!source.exists || source.data().kind !== 'sale' || source.data().status !== 'applied') {
        // Safe backend recovery for modern sales whose client sent sale-doc id
        // but the applied stock op is bound via explicit sale.stockOperationId.
        // Fail closed unless exactly one proven binding exists (explicit field).
        // Never fuzzy-match by items/time. Never allow client ops collection scans.
        const saleSnap = await tx.get(base.collection('estoque_vendas').doc(command.sourceOperationId));
        const bound = saleSnap.exists
          ? String(saleSnap.data()?.stockOperationId ?? '').trim()
          : '';
        if (!bound || bound === command.sourceOperationId) {
          throw stockError('failed-precondition', 'Applied sale required');
        }
        const reboundRef = base.collection('stock_catalog_operations').doc(bound);
        const rebound = await tx.get(reboundRef);
        if (!rebound.exists || rebound.data().kind !== 'sale' || rebound.data().status !== 'applied') {
          throw stockError('failed-precondition', 'Applied sale required');
        }
        const opSaleId = String(rebound.data()?.saleId ?? '').trim();
        // Accept: legacy (no saleId), op.saleId==op id, or op.saleId==sale doc id.
        if (opSaleId && opSaleId !== bound && opSaleId !== command.sourceOperationId) {
          throw stockError('failed-precondition', 'Applied sale required');
        }
        sourceRef = reboundRef;
        source = rebound;
      }
      if (source.data().restoredBy && source.data().restoredBy !== command.operationId) throw stockError('already-exists', 'Sale already restored');
      items = source.data().items;
    }
    const ids = [...new Set(items.map(i => i.productId))];
    if (ids.length > MAX_PRODUCTS) throw stockError('resource-exhausted', 'Too many products');
    const records = new Map(), targetIds = new Set(items.map(i => i.productId));
    const softSale = command.kind === 'sale' || command.kind === 'restock';
    const newDefinition = ['create','replace'].includes(command.kind) ? normalizeStock({
      variacoes: null, estoquePorTamanho: {}, estoquePorCor: {}, tamanhos: [], cores: [],
      itensCombo: [], comboConfig: null, ...command.definition,
      stockKind: inferStockKind(command.definition), stockRevision: 0,
    }) : null;
    if (newDefinition) for (const c of recipe(newDefinition)) if (!ids.includes(c.productId)) ids.push(c.productId);
    for (const id of ids) {
      if (records.has(id)) continue;
      if (records.size >= MAX_PRODUCTS) throw stockError('resource-exhausted', 'Combo fan-out exceeds transaction budget');
      const stockRef = base.collection('estoque_produtos').doc(id), draftRef = base.collection('draft_produtos').doc(id);
      const [stock, draft, dependency, tombstone] = await tx.getAll(
        stockRef, draftRef, base.collection('stock_catalog_dependencies').doc(id),
        base.collection('exclusao_produto').doc(id),
      );
      const creating = command.kind === 'create' && targetIds.has(id);
      if (legacyCompat) {
        // NO_CONTROL: estoque_produtos required; draft/dependency optional.
        // create may proceed without existing stock; replace/editorial/sale need stock.
        if (!stock.exists && !creating) throw stockError('failed-precondition', 'Canonical product required');
      } else if ((!stock.exists || !draft.exists) && !creating) {
        if (softSale && targetIds.has(id)) {
          records.set(id, null);
          continue;
        }
        throw stockError('failed-precondition', 'Canonical product and editorial draft required');
      }
      if (creating && stock.exists) throw stockError('already-exists', 'Product already exists');
      // Full-product tombstones (p:true) block stock commands until undo/reconcile.
      // Partial variation markers (p:false + v.*) must not freeze the whole product.
      const fullProductTombstone = tombstone.exists && tombstone.data()?.p === true;
      if (fullProductTombstone && !(command.kind === 'undo' && targetIds.has(id)) && !stock.data()?.pendingSoftDelete) {
        if (softSale && targetIds.has(id)) {
          records.set(id, {softFail: REASON.PRODUCT_INACTIVE, stockRef, draftRef, editorial: draft.exists ? draft.data() : {}, draftExists: draft.exists});
          continue;
        }
        throw stockError('failed-precondition', 'Product tombstone requires reconciliation');
      }
      if (!legacyCompat && (!dependency.exists || !Array.isArray(dependency.data().comboIds)) && !creating) {
        if (softSale && targetIds.has(id)) {
          records.set(id, {softFail: REASON.MISSING_DEPENDENCY, stockRef, draftRef, editorial: draft.data() || {}, draftExists: draft.exists});
          continue;
        }
        throw stockError('failed-precondition', 'Dependency migration required');
      }
      const dependencyData = dependency.exists && Array.isArray(dependency.data()?.comboIds)
        ? dependency.data()
        : {comboIds: []};
      const dependencyHandle = legacyCompat
        ? {exists: dependency.exists, data: () => dependencyData}
        : dependency;
      for (const related of (dependencyData.comboIds ?? [])) if (!ids.includes(documentId(related))) ids.push(related);
      let data;
      try {
        const rawStock = creating ? newDefinition : {...(stock.data() || {})};
        if (legacyCompat && (rawStock.stockRevision === undefined || rawStock.stockRevision === null)) {
          rawStock.stockRevision = 0;
        }
        data = normalizeStock(creating ? newDefinition : rawStock); quantity(data.stockRevision);
      } catch (error) {
        if (softSale && targetIds.has(id)) {
          records.set(id, {softFail: REASON.INVALID_STOCK_STATE, stockRef, draftRef, editorial: draft.data() || {}, draftExists: draft.exists});
          continue;
        }
        throw error;
      }
      for (const component of recipe(data)) if (!ids.includes(component.productId)) ids.push(component.productId);
      const editorial = draft.exists
        ? draft.data()
        : (legacyCompat
            ? {
                nome: (stock.data()?.nome ?? stock.data()?.name ?? '').toString(),
                publicadoNoCatalogo: stock.data()?.publicadoNoCatalogo === true,
              }
            : validateEditorial(command.editorial));
      records.set(id, {
        stockRef, draftRef, dependency: dependencyHandle, creating,
        draftExists: draft.exists, originalRecipe: recipe(data), data,
        beforeHash: fingerprint(stockEffect(data)), originalRevision: data.stockRevision,
        originalStockOperationId: (data.stockOperationId ?? '').toString() || null,
        editorial,
      });
    }
    if (!softSale) comboOrder(records);
    else {
      const ok = new Map([...records.entries()].filter(([, r]) => r && r.data));
      if (ok.size) comboOrder(ok);
    }
    const appliedItems = [];
    function applyItem(item, expand) {
      const r = records.get(item.productId);
      if (!r || r.softFail || !r.data) throw stockError('failed-precondition', 'Product unavailable');
      if (command.kind === 'editorial') {
        const patch = validateEditorial(command.editorial);
        r.editorial = {...r.editorial, ...patch}; r.data = {...r.data, ...patch}; return;
      }
      if (['adjust','replace','delete','undo','tombstoneVariation','clearVariationTombstone'].includes(command.kind) && item.expectedRevision !== r.originalRevision) {
        throw stockError('aborted', 'Stock revision conflict');
      }
      if (command.kind === 'create') {r.editorial = validateEditorial(command.editorial); r.data = {...r.data, ...r.editorial}; return;}
      if (command.kind === 'replace') {
        // No missing field inherits an old grade during explicit schema/count replacement.
        if (r.data.pendingSoftDelete) throw stockError('failed-precondition', 'Restore deleted product before editing');
        const candidate = {...r.data, ...newDefinition, stockRevision: r.originalRevision};
        const patch = validateEditorial(command.editorial);
        r.data = {...normalizeStock(candidate), ...patch}; r.editorial = {...r.editorial, ...patch}; return;
      }
      if (command.kind === 'delete' || command.kind === 'undo') {
        r.data.pendingSoftDelete = command.kind === 'delete'; return;
      }
      if (command.kind === 'tombstoneVariation' || command.kind === 'clearVariationTombstone') {
        // Partial markers never flip pendingSoftDelete / full-product tombstone.
        if (r.data.pendingSoftDelete) throw stockError('failed-precondition', 'Product deleted');
        return;
      }
      r.data = applyCell(r.data, item, command.kind === 'sale' ? -item.quantity : item.quantity, command.kind === 'adjust');
      appliedItems.push(item);
      if (expand) for (const child of componentIntents(r.data, item)) applyItem(child, true);
    }
    // Prevalidate ALL sale/restock lines before any mutation (multi-product actionable errors).
    if (command.kind === 'sale' || command.kind === 'restock') {
      const issues = [];
      const scratch = new Map([...records.entries()].map(([id, r]) => {
        if (!r || r.softFail || !r.data) return [id, r];
        return [id, {...r, data: JSON.parse(JSON.stringify(r.data))}];
      }));
      items.forEach((item, lineIndex) => {
        const r = scratch.get(item.productId);
        const name = String(r?.editorial?.nome || item.productId);
        const selectionLabel = gradeKeyLabel({size: item.size, color: item.color, extra: item.extra});
        if (!r) {
          issues.push(makeIssue({
            productId: item.productId, productName: name, lineIndex,
            selectionLabel, reasonCode: REASON.PRODUCT_NOT_FOUND, requestedQty: item.quantity,
          }));
          return;
        }
        if (r.softFail) {
          issues.push(makeIssue({
            productId: item.productId, productName: name, lineIndex,
            selectionLabel, reasonCode: r.softFail, requestedQty: item.quantity,
          }));
          return;
        }
        try {
          if (r.data.ativo === false) {
            issues.push(makeIssue({
              productId: item.productId, productName: name, lineIndex,
              selectionLabel, reasonCode: REASON.PRODUCT_INACTIVE, requestedQty: item.quantity,
            }));
            return;
          }
          r.data = applyCell(r.data, item, command.kind === 'sale' ? -item.quantity : item.quantity, false);
        } catch (error) {
          const msg = String(error?.message || '');
          let reason = REASON.OTHER_PRODUCT_BLOCK;
          if (!item.size || !item.color) {
            reason = REASON.GRADE_SELECTION_REQUIRED;
          } else if (/Variation not found|Extra variation/i.test(msg)) {
            reason = !technicalSimpleColor(item.color)
              ? REASON.GRADE_CELL_NOT_FOUND
              : REASON.VARIATION_NOT_FOUND;
          } else if (/Extra dimension required/i.test(msg)) {
            reason = REASON.GRADE_SELECTION_REQUIRED;
          } else if (/Invalid canonical|quantity/i.test(msg)) {
            reason = REASON.INSUFFICIENT_STOCK;
          } else if (/Simple product cannot/i.test(msg)) {
            reason = REASON.VARIATION_NOT_FOUND;
          } else if (/Product deleted/i.test(msg)) {
            reason = REASON.PRODUCT_INACTIVE;
          }
          issues.push(makeIssue({
            productId: item.productId, productName: name, lineIndex,
            selectionLabel, reasonCode: reason, requestedQty: item.quantity,
          }));
        }
      });
      if (issues.length) throw productValidationError(issues);
    }
    for (const item of items) applyItem(item, command.kind === 'sale');
    const liveRecords = new Map([...records.entries()].filter(([, r]) => r && r.data && !r.softFail));
    comboOrder(liveRecords); // Validate the new recipe, including newly introduced cycles.
    if (command.kind !== 'editorial' && command.kind !== 'tombstoneVariation' && command.kind !== 'clearVariationTombstone') {
      recalculateFixedCombos(liveRecords,
        ['restock','restore','undo'].includes(command.kind) ? 1 : -1);
    }
    const products = [], writes = [];
    // Budget is checked before queuing any write on the Firestore transaction.
    const set = (ref, data, merge = false) => writes.push(() => merge ? tx.set(ref, data, {merge: true}) : tx.set(ref, data));
    const remove = ref => writes.push(() => tx.delete(ref));
    if (newDefinition) {
      const rootId = items[0].productId;
      const oldIds = new Set(command.kind === 'create' ? [] : liveRecords.get(rootId).originalRecipe.map(i => i.productId));
      const newIds = new Set(recipe(liveRecords.get(rootId).data).map(i => i.productId));
      for (const id of new Set([...oldIds, ...newIds, ...(command.kind === 'create' ? [rootId] : [])])) {
        const related = new Set(liveRecords.get(id).dependency.data()?.comboIds ?? []);
        if (oldIds.has(id)) related.delete(rootId);
        if (newIds.has(id)) related.add(rootId);
        set(base.collection('stock_catalog_dependencies').doc(id), {comboIds: [...related].sort()});
      }
    }
    // Ranking counts purchased roots of persisted catalog orders, not expanded
    // combo components. It shares the stock operation marker and its replay.
    const catalogCountDeltas = Object.create(null);
    if (command.kind === 'sale' && auth === SERVER_PAYMENT_AUTH) {
      for (const item of command.items) catalogCountDeltas[item.productId] =
        quantity((catalogCountDeltas[item.productId] ?? 0) + item.quantity);
    } else if (command.kind === 'restore') {
      for (const [id, count] of Object.entries(source.data().catalogCountDeltas ?? {})) {
        if (!liveRecords.has(id)) throw stockError('failed-precondition', 'Missing recorded catalog root');
        catalogCountDeltas[id] = -quantity(count);
      }
    }
    for (const [id, delta] of Object.entries(catalogCountDeltas)) {
      const row = liveRecords.get(id).data;
      row.vendasCatalogoTotal = quantity(Math.max(0, quantity(row.vendasCatalogoTotal ?? 0) + delta));
    }
    for (const [id, r] of liveRecords) {
      const effectUnchanged = fingerprint(stockEffect(r.data)) === r.beforeHash;
      r.data.stockRevision = quantity(r.originalRevision + (effectUnchanged ? 0 : 1));
      // Canonical stock lineage: only stock-effecting commands stamp operationId.
      // Pure editorial metadata must preserve the prior stockOperationId.
      if (effectUnchanged && command.kind === 'editorial') {
        if (r.originalStockOperationId) {
          r.data.stockOperationId = r.originalStockOperationId;
        } else {
          delete r.data.stockOperationId;
        }
      } else {
        r.data.stockOperationId = command.operationId;
      }
      const p = projectCatalog(r.data, r.editorial, id);
      products.push({productId: id, ...p.stock});
      if (targetIds.has(id) && command.kind === 'delete') set(base.collection('exclusao_produto').doc(id),
        {p: true, productId: id, operationId: command.operationId, at: FieldValue.serverTimestamp(), deletedAt: FieldValue.serverTimestamp()});
      if (targetIds.has(id) && command.kind === 'undo') remove(base.collection('exclusao_produto').doc(id));
      if (targetIds.has(id) && command.kind === 'tombstoneVariation') {
        // Partial markers stay p:false — never full-product delete.
        // Nested `v` map (not dotted literal keys): Admin set(merge) treats "v.x" as a field name.
        set(base.collection('exclusao_produto').doc(id), {
          p: false,
          productId: id,
          operationId: command.operationId,
          at: FieldValue.serverTimestamp(),
          v: Object.fromEntries(command.tombstoneKeys.map(k => [k, true])),
        }, true);
      }
      if (targetIds.has(id) && command.kind === 'clearVariationTombstone') {
        // update() interprets dotted paths; set(merge) would not delete nested keys.
        const tombRef = base.collection('exclusao_produto').doc(id);
        const patch = {
          at: FieldValue.serverTimestamp(),
          operationId: command.operationId,
        };
        for (const key of command.tombstoneKeys) patch[`v.${key}`] = FieldValue.delete();
        writes.push(() => tx.update(tombRef, patch));
      }
      set(r.stockRef, {...p.stock, stockUpdatedAt: FieldValue.serverTimestamp()});
      // NO_CONTROL compat: never create draft/dependency/control/grants; update draft/live only if draft existed.
      if (!legacyCompat || r.draftExists) {
        set(r.draftRef, {...p.draft, updatedAt: FieldValue.serverTimestamp()});
        const live = base.collection('produtos').doc(id);
        if (p.live) set(live, {...p.live, updatedAt: FieldValue.serverTimestamp()}); else remove(live);
      }
    }
    writes.push(() => tx.create(opRef, {actorUid: uid, kind: command.kind, requestHash: hash, items: appliedItems, catalogCountDeltas, status: 'applied',
      result: {productIds: ids}, sourceOperationId: command.sourceOperationId ?? null,
      legacyCompat: legacyCompat === true,
      ...(command.kind === 'sale' ? {saleId: command.operationId} : {}),
      ...(command.atomicPdvSale ? {atomicPdvSale: true} : {}),
      createdAt: FieldValue.serverTimestamp()}));
    if (command.atomicPdvSale) {
      // Emulator-only regression hook: abort after in-memory stock apply, before durable writes.
      if (process.env.FIRESTORE_EMULATOR_HOST &&
          command.atomicSale.observacao === '__FORCE_SALE_WRITE_FAIL__') {
        throw stockError('internal', 'Forced sale write failure');
      }
      const saleDoc = buildCanonicalEstoqueVendaDoc(command.atomicSale, {actorUid: uid});
      writes.push(() => tx.create(saleRef, saleDoc));
    }
    if (sourceRef) writes.push(() => tx.update(sourceRef, {restoredBy: command.operationId}));
    if (writes.length + reservedWrites > 100) throw stockError('resource-exhausted', 'Stock transaction write budget exceeded');
    for (const write of writes) write();
    const result = {alreadyApplied: false, operationId: command.operationId, products};
    if (command.atomicPdvSale) {
      result.saleCommitted = true;
      result.saleId = command.operationId;
      result.authoritativeSalePersisted = true;
      result.authoritativeStockCommitted = true;
    }
    return result;
}

export async function publishStockProduct(db, lojaId, productId, auth) {
  requireAuthenticated(auth); documentId(productId, 'productId');
  const base = storeRef(db, lojaId);
  return runStockTransaction(db, async tx => {
    await authorizePublish(tx, db, base, auth);
    const sref = base.collection('estoque_produtos').doc(productId), dref = base.collection('draft_produtos').doc(productId);
    const [stock, draft, tombstone] = await tx.getAll(sref, dref, base.collection('exclusao_produto').doc(productId));
    if (!stock.exists) throw stockError('failed-precondition', 'Canonical product required');
    // NO_CONTROL: draft optional — project from authoritative stock + empty editorial defaults.
    const editorial = draft.exists ? draft.data() : {};
    let p;
    try {
      p = projectCatalog({...stock.data(), ...((tombstone.exists && tombstone.data()?.p === true) ? {pendingSoftDelete: true} : {})}, editorial, productId);
    } catch (e) {
      if (e?.code === 'failed-precondition' && String(e.message || '').includes('Invalid canonical stock quantity')) {
        const details = e.details && typeof e.details === 'object' ? e.details : {};
        const err = stockError('failed-precondition', 'Invalid canonical stock quantity');
        err.details = {
          code: 'INVALID_CANONICAL_STOCK',
          productId,
          field: details.field || 'quantidade',
          reason: details.reason || 'not_safe_nonnegative_integer',
        };
        throw err;
      }
      throw e;
    }
    if (draft.exists) {
      tx.set(dref, {...p.draft, updatedAt: FieldValue.serverTimestamp()});
    }
    const live = base.collection('produtos').doc(productId);
    if (p.live) tx.set(live, {...p.live, updatedAt: FieldValue.serverTimestamp()}); else tx.delete(live);
    return {productId, available: p.live !== null, revision: p.stock.stockRevision};
  });
}

export async function publishStockAll(db, lojaId, auth) {
  requireAuthenticated(auth);
  const base = storeRef(db, lojaId);
  await runStockTransaction(db, tx => authorizePublish(tx, db, base, auth));
  let last, count = 0;
  do {
    let query = base.collection('estoque_produtos').orderBy('__name__').limit(100);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    for (const item of page.docs) { await publishStockProduct(db, lojaId, item.id, auth); count++; }
    last = page.docs.length === 100 ? page.docs.at(-1) : null;
  } while (last);
  return {publishedProductsProcessed: count};
}
