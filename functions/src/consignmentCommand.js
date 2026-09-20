/** Server-authoritative consignment commands. Isolated from stockCatalogCommand and PDV sales. */
import {FieldValue} from 'firebase-admin/firestore';
import {
  documentId, storeRef, requireAuthenticated,
} from './stockCatalogAccess.js';
import {
  CONSIGNMENT_SCHEMA_VERSION, STATUS, COMMISSION, CODES, consignmentError, requestFingerprint,
  keysOnly, money, lineAmounts, quantityPositive, quantityNonNegative, optionalString, parseCommand,
} from './consignmentProtocol.js';
import {
  classifyConsignmentProduct, parseVariationSelector, variationIdentity,
  applyExactConsignmentDelta, loadConsignmentStockRecords, persistConsignmentStock,
  evaluateConsignmentPickerEligibility,
} from './consignmentStock.js';
import {
  REASON, makeIssue, productValidationError, gradeKey, gradeKeyLabel,
} from './productValidationErrors.js';
import {quantity} from './catalogStockProjection.js';

const MAX_LINES = 50;

function consignmentRef(base, id) { return base.collection('consignments').doc(documentId(id, 'consignmentId')); }
function resellerRef(base, id) { return base.collection('consignment_resellers').doc(documentId(id, 'resellerId')); }
function opRef(base, id) { return base.collection('consignment_operations').doc(documentId(id, 'operationId')); }

async function requireModuleEnabled(tx, base) {
  const control = await tx.get(base.collection('consignment_control').doc('state'));
  if (!control.exists || control.data()?.moduleEnabled !== true || control.data()?.protocolVersion !== 1) {
    throw consignmentError(CODES.MODULE_DISABLED, 'Consignment module is not enabled for this store');
  }
}

const RESELLER_OPERATIONS = new Set(['createReseller', 'updateReseller']);

async function authorizeStoreMember(tx, db, base, auth, operation) {
  const uid = requireAuthenticated(auth);
  await requireModuleEnabled(tx, base);
  const loja = await tx.get(base);
  const lojaData = loja.data() || {};
  if (loja.exists && lojaData.ownerUid === uid) return uid;
  const member = await tx.get(base.collection('members').doc(uid));
  if (member.exists) {
    const role = String(member.data()?.role ?? '').trim();
    if (!role || ['owner', 'admin', 'vendedor'].includes(role)) return uid;
  }
  const seller = await tx.get(base.collection('vendedores').doc(uid));
  if (seller.exists && seller.data()?.ativo === true) return uid;
  const userSnap = await tx.get(db.collection('users').doc(uid));
  if (userSnap.exists) {
    const resolved = String(userSnap.data()?.store_id || userSnap.data()?.storeId || '').trim();
    if (resolved === base.id && (!lojaData.ownerUid || lojaData.ownerUid === uid)) return uid;
  }
  throw consignmentError(
    RESELLER_OPERATIONS.has(operation) ? CODES.RESELLER_PERMISSION : CODES.AUTH,
    'Store membership required',
  );
}

async function authorize(tx, db, base, auth, operation) {
  return authorizeStoreMember(tx, db, base, auth, operation);
}

function docsById(snap) {
  const map = new Map();
  for (const doc of snap?.docs || []) map.set(doc.id, doc.data() || {});
  return map;
}

async function listEligibleProducts(db, command, auth) {
  keysOnly(command.payload, []);
  const base = storeRef(db, command.lojaId);
  await db.runTransaction(tx => authorize(tx, db, base, auth, command.operation));
  const [stockSnap, draftSnap, depSnap, tombSnap] = await Promise.all([
    base.collection('estoque_produtos').get(),
    base.collection('draft_produtos').get(),
    base.collection('stock_catalog_dependencies').get(),
    base.collection('exclusao_produto').get(),
  ]);
  const drafts = docsById(draftSnap);
  const deps = docsById(depSnap);
  const tombs = docsById(tombSnap);
  const products = [];
  for (const doc of stockSnap.docs || []) {
    const item = evaluateConsignmentPickerEligibility({
      productId: doc.id,
      lojaId: command.lojaId,
      stock: doc.data() || {},
      draft: drafts.get(doc.id),
      dependency: deps.get(doc.id),
      tombstone: tombs.get(doc.id),
    });
    // Surface selectable + zero-stock disabled rows; hide hard-unsupported noise.
    if (!item.eligible && !['ZERO_STOCK', 'INSUFFICIENT_STOCK', 'COMBO_NOT_SUPPORTED'].includes(item.reason)) {
      continue;
    }
    products.push({
      productId: item.productId,
      name: item.name,
      price: item.price,
      availableQty: item.availableQty,
      stockKind: item.stockKind,
      variacoes: item.variacoes,
      eligible: item.eligible === true,
      reason: item.reason || '',
      unavailableReason: item.eligible
        ? ''
        : (item.reason === 'ZERO_STOCK' || item.reason === 'INSUFFICIENT_STOCK'
          ? 'Sem estoque'
          : (item.reason === 'COMBO_NOT_SUPPORTED'
            ? 'Produtos do tipo combo ainda não são suportados nesta operação.'
            : 'Produto ainda não disponível para consignação.')),
    });
  }
  products.sort((a, b) => {
    if (a.eligible !== b.eligible) return a.eligible ? -1 : 1;
    return a.name.localeCompare(b.name, 'pt-BR');
  });
  return {products, alreadyApplied: false, writes: 0};
}

function parseLineInput(raw, index) {
  keysOnly(raw, ['productId','variationKey','qtySent','unitSalePrice','commissionType','commissionValue','notes']);
  const productId = documentId(raw.productId, 'productId');
  const qtySent = quantityPositive(raw.qtySent);
  const unitSalePrice = money(raw.unitSalePrice);
  const commissionType = raw.commissionType ?? COMMISSION.SEM_COMISSAO;
  if (!Object.values(COMMISSION).includes(commissionType)) {
    throw consignmentError(CODES.INVALID_ARGUMENT, 'Invalid commission type');
  }
  const commissionValue = commissionType === COMMISSION.SEM_COMISSAO ? 0 : money(raw.commissionValue ?? 0);
  const variationKey = raw.variationKey == null ? {size: '', color: '', extra: ''} : parseVariationSelector(raw.variationKey);
  const potential = lineAmounts(qtySent, unitSalePrice, commissionType, commissionValue);
  return {
    lineId: `${productId}::${variationIdentity(variationKey)}`,
    productId,
    variationKey,
    qtySent,
    qtySold: 0,
    qtyReturned: 0,
    unitSalePriceSnapshot: unitSalePrice,
    commissionType,
    commissionValueSnapshot: commissionValue,
    lineGrossAmount: 0,
    lineCommissionAmount: 0,
    lineNetAmount: 0,
    potentialGrossAmount: potential.lineGrossAmount,
    potentialCommissionAmount: potential.lineCommissionAmount,
    potentialNetAmount: potential.lineNetAmount,
    notes: optionalString(raw.notes, 'line notes', 500),
    _index: index,
  };
}

function uniqueLines(lines) {
  if (!Array.isArray(lines) || lines.length > MAX_LINES) throw consignmentError(CODES.INVALID_ARGUMENT, 'Invalid lines');
  const parsed = lines.map((line, i) => parseLineInput(line, i));
  const ids = parsed.map(l => l.lineId);
  if (new Set(ids).size !== ids.length) throw consignmentError(CODES.INVALID_ARGUMENT, 'Duplicate consignment lines');
  return parsed;
}

async function snapshotLines(tx, base, lines) {
  const productIds = [...new Set(lines.map(l => l.productId))];
  const records = new Map();
  const loadErrors = new Map();
  for (const id of productIds) {
    try {
      const one = await loadConsignmentStockRecords(tx, base, [id]);
      records.set(id, one.get(id));
    } catch (error) {
      records.set(id, null);
      loadErrors.set(id, error);
    }
  }
  const out = [];
  const issues = [];
  for (const line of lines) {
    const record = records.get(line.productId);
    const loadError = loadErrors.get(line.productId);
    const editorial = record?.editorial || {};
    const stockName = typeof record?.data?.nome === 'string' ? record.data.nome.trim() : '';
    const editorialName = typeof editorial.nome === 'string' ? editorial.nome.trim() : '';
    const name = editorialName || stockName || line.productId;
    const selectionLabel = gradeKeyLabel(line.variationKey);
    const idx = line._index ?? 0;
    if (!record) {
      const msg = String(loadError?.message || '');
      const code = loadError?.consignmentCode;
      let reason = REASON.PRODUCT_NOT_FOUND;
      if (code === CODES.AUTH || /Cross-store/i.test(msg)) reason = REASON.CROSS_STORE_PRODUCT;
      else if (/Dependency migration/i.test(msg)) reason = REASON.MISSING_DEPENDENCY;
      else if (/inactive|tombstone|deleted/i.test(msg)) reason = REASON.PRODUCT_INACTIVE;
      else if (/ambiguous|Invalid canonical|stockRevision/i.test(msg) || code === CODES.PRODUCT_STATE_UNSAFE) {
        reason = REASON.INVALID_STOCK_STATE;
      } else if (/combo/i.test(msg)) reason = REASON.COMBO_NOT_SUPPORTED;
      issues.push(makeIssue({
        productId: line.productId, productName: name, lineIndex: idx,
        selectionLabel, reasonCode: reason, requestedQty: line.qtySent,
      }));
      continue;
    }
    let classified;
    try {
      classified = classifyConsignmentProduct(record.data);
    } catch (error) {
      const msg = error?.message || '';
      let reason = REASON.INVALID_STOCK_STATE;
      if (/combo/i.test(msg)) reason = REASON.COMBO_NOT_SUPPORTED;
      else if (error?.consignmentCode === CODES.PRODUCT_NOT_FOUND) reason = REASON.PRODUCT_NOT_FOUND;
      else if (/Cross-store|AUTH/i.test(msg)) reason = REASON.CROSS_STORE_PRODUCT;
      issues.push(makeIssue({
        productId: line.productId, productName: name, lineIndex: idx,
        selectionLabel, reasonCode: reason, requestedQty: line.qtySent,
      }));
      continue;
    }
    if (classified.kind === 'simple') {
      if (line.variationKey.size || line.variationKey.color || line.variationKey.extra) {
        issues.push(makeIssue({
          productId: line.productId, productName: name, lineIndex: idx,
          selectionLabel, reasonCode: REASON.VARIATION_NOT_FOUND, requestedQty: line.qtySent,
        }));
        continue;
      }
    } else if (classified.kind === 'grade') {
      if (!line.variationKey.size || !line.variationKey.color) {
        issues.push(makeIssue({
          productId: line.productId, productName: name, lineIndex: idx,
          selectionLabel, reasonCode: REASON.GRADE_SELECTION_REQUIRED, requestedQty: line.qtySent,
        }));
        continue;
      }
    } else if (!line.variationKey.size || !line.variationKey.color) {
      issues.push(makeIssue({
        productId: line.productId, productName: name, lineIndex: idx,
        selectionLabel, reasonCode: REASON.VARIATION_REQUIRED, requestedQty: line.qtySent,
      }));
      continue;
    }
    if (classified.kind !== 'simple') {
      try {
        applyExactConsignmentDelta(
          JSON.parse(JSON.stringify(classified.stock)),
          classified.kind,
          line.variationKey,
          -line.qtySent,
        );
      } catch (error) {
        const code = error?.consignmentCode;
        let reason = classified.kind === 'grade' ? REASON.GRADE_CELL_NOT_FOUND : REASON.VARIATION_NOT_FOUND;
        if (code === CODES.INSUFFICIENT_STOCK) reason = REASON.INSUFFICIENT_STOCK;
        issues.push(makeIssue({
          productId: line.productId, productName: name, lineIndex: idx,
          selectionLabel, reasonCode: reason, requestedQty: line.qtySent,
        }));
        continue;
      }
    } else {
      const avail = quantity(classified.stock.quantidade);
      if (avail < line.qtySent) {
        issues.push(makeIssue({
          productId: line.productId, productName: name, lineIndex: idx,
          selectionLabel,
          reasonCode: avail === 0 ? REASON.ZERO_STOCK : REASON.INSUFFICIENT_STOCK,
          requestedQty: line.qtySent, availableQty: avail,
        }));
        continue;
      }
    }
    const gKey = classified.kind === 'simple' ? '' : gradeKey(line.variationKey);
    out.push({
      ...line,
      productNameSnapshot: name,
      productType: classified.kind,
      variationSnapshot: classified.kind === 'simple' ? null : {...line.variationKey},
      gradeKey: gKey || null,
      gradeDimensions: classified.kind === 'simple' ? null : {...line.variationKey},
    });
    delete out[out.length - 1]._index;
  }
  if (issues.length) throw productValidationError(issues);
  return {lines: out, records};
}

async function replayOrConflict(tx, opSnap, uid, hash) {
  if (!opSnap.exists) return null;
  const data = opSnap.data() || {};
  if (data.requestHash !== hash || data.actorUid !== uid) {
    throw consignmentError(CODES.IDEMPOTENCY_CONFLICT, 'Operation identity conflict');
  }
  return {alreadyApplied: true, operationId: opSnap.id, result: data.result ?? {}, consignment: data.consignment ?? null};
}

async function runConsignmentTransaction(db, callback) {
  for (let attempt = 0; ; attempt++) {
    try { return await db.runTransaction(callback); }
    catch (error) {
      const closedToken = error.code === 3 && /Transaction is invalid or closed\./.test(error.details ?? error.message ?? '');
      if (!closedToken || attempt >= 2) throw error;
      await new Promise(resolve => setTimeout(resolve, 100 * (attempt + 1)));
    }
  }
}

export async function executeConsignmentCommand(db, raw, auth) {
  if (raw?.operation === 'listEligibleProducts') {
    return listEligibleProducts(db, parseCommand(raw), auth);
  }
  return runConsignmentTransaction(db, tx => executeConsignmentInTransaction(tx, db, raw, auth));
}

export async function executeConsignmentInTransaction(tx, db, raw, auth) {
  const command = parseCommand(raw);
  const base = storeRef(db, command.lojaId);
  const uid = await authorize(tx, db, base, auth, command.operation);
  const hash = requestFingerprint({
    protocolVersion: command.protocolVersion,
    lojaId: command.lojaId,
    operation: command.operation,
    operationId: command.operationId,
    consignmentId: command.consignmentId,
    payload: command.payload,
  });
  const operationDoc = await tx.get(opRef(base, command.operationId));
  const replay = await replayOrConflict(tx, operationDoc, uid, hash);
  if (replay) {
    if (replay.consignment) {
      const current = await tx.get(consignmentRef(base, replay.consignment));
      if (current.exists) replay.consignmentDoc = current.data();
    }
    return replay;
  }
  let result;
  switch (command.operation) {
    case 'createReseller': result = await createReseller(tx, base, command, uid); break;
    case 'updateReseller': result = await updateReseller(tx, base, command, uid); break;
    case 'createDraft': result = await createDraft(tx, base, command, uid); break;
    case 'updateDraft': result = await updateDraft(tx, base, command, uid); break;
    case 'cancelDraft': result = await cancelDraft(tx, base, command, uid); break;
    case 'issue': result = await issueConsignment(tx, base, command, uid); break;
    case 'settle': result = await settleConsignment(tx, base, command, uid); break;
    default: throw consignmentError(CODES.INVALID_ARGUMENT, 'Unsupported consignment operation');
  }
  tx.create(opRef(base, command.operationId), {
    actorUid: uid,
    operation: command.operation,
    requestHash: hash,
    consignment: result.consignmentId ?? null,
    status: 'applied',
    result,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {alreadyApplied: false, operationId: command.operationId, ...result};
}

async function readReseller(tx, base, resellerId, lojaId) {
  const snap = await tx.get(resellerRef(base, resellerId));
  if (!snap.exists) throw consignmentError(CODES.NOT_FOUND, 'Reseller not found');
  const data = snap.data() || {};
  if (data.storeId !== lojaId) throw consignmentError(CODES.AUTH, 'Reseller does not belong to this store');
  if (data.active !== true) throw consignmentError(CODES.FAILED_PRECONDITION, 'Reseller is inactive');
  return {id: snap.id, displayName: data.displayName || snap.id, notes: data.notes || '', active: true};
}

function parseResellerPayload(payload, creating) {
  keysOnly(payload, creating
    ? ['resellerId','displayName','notes','phone']
    : ['resellerId','displayName','notes','phone','active']);
  const resellerId = documentId(payload.resellerId, 'resellerId');
  const displayName = optionalString(payload.displayName, 'displayName', 120).trim();
  if (creating && !displayName) throw consignmentError(CODES.INVALID_ARGUMENT, 'Reseller name required');
  return {
    resellerId,
    displayName,
    notes: optionalString(payload.notes, 'notes', 2000),
    phone: optionalString(payload.phone, 'phone', 40).trim(),
    active: payload.active === undefined ? true : payload.active === true,
  };
}

async function createReseller(tx, base, command, uid) {
  const parsed = parseResellerPayload(command.payload, true);
  const ref = resellerRef(base, parsed.resellerId);
  const existing = await tx.get(ref);
  if (existing.exists) throw consignmentError(CODES.FAILED_PRECONDITION, 'Reseller already exists');
  tx.create(ref, {
    storeId: command.lojaId,
    resellerId: parsed.resellerId,
    displayName: parsed.displayName,
    active: true,
    notes: parsed.notes,
    phone: parsed.phone,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    createdBy: uid,
    schemaVersion: CONSIGNMENT_SCHEMA_VERSION,
  });
  return {resellerId: parsed.resellerId, displayName: parsed.displayName};
}

async function updateReseller(tx, base, command, uid) {
  const parsed = parseResellerPayload(command.payload, false);
  const ref = resellerRef(base, parsed.resellerId);
  const existing = await tx.get(ref);
  if (!existing.exists) throw consignmentError(CODES.NOT_FOUND, 'Reseller not found');
  if (existing.data()?.storeId !== command.lojaId) throw consignmentError(CODES.AUTH, 'Reseller does not belong to this store');
  const patch = {updatedAt: FieldValue.serverTimestamp(), updatedBy: uid};
  if (command.payload.displayName !== undefined) {
    if (!parsed.displayName) throw consignmentError(CODES.INVALID_ARGUMENT, 'Reseller name required');
    patch.displayName = parsed.displayName;
  }
  if (command.payload.notes !== undefined) patch.notes = parsed.notes;
  if (command.payload.phone !== undefined) patch.phone = parsed.phone;
  if (command.payload.active !== undefined) patch.active = parsed.active;
  tx.update(ref, patch);
  return {resellerId: parsed.resellerId};
}

function draftTotals(lines) {
  return {
    totalItemsSent: lines.reduce((sum, l) => sum + l.qtySent, 0),
    totalItemsSold: 0,
    totalItemsReturned: 0,
    grossSoldAmount: 0,
    commissionAmount: 0,
    netAmount: 0,
    potentialGrossAmount: lines.reduce((sum, l) => sum + l.potentialGrossAmount, 0),
    potentialCommissionAmount: lines.reduce((sum, l) => sum + l.potentialCommissionAmount, 0),
    potentialNetAmount: lines.reduce((sum, l) => sum + l.potentialNetAmount, 0),
  };
}

async function createDraft(tx, base, command, uid) {
  const consignmentId = command.consignmentId || command.operationId;
  documentId(consignmentId, 'consignmentId');
  keysOnly(command.payload, ['resellerId','notes','lines']);
  const resellerId = documentId(command.payload.resellerId, 'resellerId');
  const reseller = await readReseller(tx, base, resellerId, command.lojaId);
  const parsedLines = uniqueLines(command.payload.lines ?? []);
  const {lines} = parsedLines.length ? await snapshotLines(tx, base, parsedLines) : {lines: []};
  const ref = consignmentRef(base, consignmentId);
  const existing = await tx.get(ref);
  if (existing.exists) throw consignmentError(CODES.FAILED_PRECONDITION, 'Consignment already exists');
  const totals = draftTotals(lines);
  const doc = {
    id: consignmentId,
    storeId: command.lojaId,
    resellerId,
    resellerSnapshot: {resellerId, displayName: reseller.displayName},
    status: STATUS.DRAFT,
    createdAt: FieldValue.serverTimestamp(),
    issuedAt: null,
    settledAt: null,
    createdBy: uid,
    settledBy: null,
    notes: optionalString(command.payload.notes, 'notes'),
    lines,
    ...totals,
    revision: 1,
    issueOperationId: null,
    settlementOperationId: null,
    schemaVersion: CONSIGNMENT_SCHEMA_VERSION,
    saleId: null,
    financeId: null,
  };
  tx.create(ref, doc);
  return {consignmentId, status: STATUS.DRAFT, revision: 1};
}

async function loadDraft(tx, base, command) {
  const consignmentId = command.consignmentId;
  if (!consignmentId) throw consignmentError(CODES.INVALID_ARGUMENT, 'consignmentId required');
  const ref = consignmentRef(base, consignmentId);
  const snap = await tx.get(ref);
  if (!snap.exists) throw consignmentError(CODES.NOT_FOUND, 'Consignment not found');
  const data = snap.data() || {};
  if (data.storeId !== command.lojaId) throw consignmentError(CODES.AUTH, 'Cross-store consignment access denied');
  return {ref, data};
}

async function updateDraft(tx, base, command, uid) {
  keysOnly(command.payload, ['resellerId','notes','lines']);
  const {ref, data} = await loadDraft(tx, base, command);
  if (data.status === STATUS.CANCELLED) throw consignmentError(CODES.FAILED_PRECONDITION, 'Cancelled consignment cannot be edited');
  if (data.status !== STATUS.DRAFT) throw consignmentError(CODES.CONSIGNMENT_ALREADY_ISSUED, 'Issued consignments cannot be edited');
  const patch = {updatedAt: FieldValue.serverTimestamp(), updatedBy: uid, revision: (data.revision || 1) + 1};
  if (command.payload.resellerId !== undefined) {
    const reseller = await readReseller(tx, base, command.payload.resellerId, command.lojaId);
    patch.resellerId = reseller.id;
    patch.resellerSnapshot = {resellerId: reseller.id, displayName: reseller.displayName};
  }
  if (command.payload.notes !== undefined) patch.notes = optionalString(command.payload.notes, 'notes');
  if (command.payload.lines !== undefined) {
    const parsedLines = uniqueLines(command.payload.lines);
    const {lines} = parsedLines.length ? await snapshotLines(tx, base, parsedLines) : {lines: []};
    Object.assign(patch, {lines, ...draftTotals(lines)});
  }
  tx.update(ref, patch);
  return {consignmentId: command.consignmentId, status: STATUS.DRAFT, revision: patch.revision};
}

async function cancelDraft(tx, base, command, uid) {
  keysOnly(command.payload, []);
  const {ref, data} = await loadDraft(tx, base, command);
  if (data.status === STATUS.CANCELLED) {
    return {consignmentId: command.consignmentId, status: STATUS.CANCELLED, revision: data.revision};
  }
  if (data.status !== STATUS.DRAFT) {
    throw consignmentError(CODES.CONSIGNMENT_ALREADY_ISSUED, 'Issued consignments cannot be cancelled; settle with full return');
  }
  tx.update(ref, {
    status: STATUS.CANCELLED,
    cancelledAt: FieldValue.serverTimestamp(),
    cancelledBy: uid,
    revision: (data.revision || 1) + 1,
  });
  return {consignmentId: command.consignmentId, status: STATUS.CANCELLED};
}

async function issueConsignment(tx, base, command, uid) {
  keysOnly(command.payload, []);
  const {ref, data} = await loadDraft(tx, base, command);
  if (data.status === STATUS.ISSUED && data.issueOperationId === command.operationId) {
    return {consignmentId: command.consignmentId, status: STATUS.ISSUED, alreadyApplied: true};
  }
  if (data.status === STATUS.ISSUED) throw consignmentError(CODES.CONSIGNMENT_ALREADY_ISSUED, 'Consignment already issued');
  if (data.status === STATUS.SETTLED) throw consignmentError(CODES.CONSIGNMENT_ALREADY_SETTLED, 'Consignment already settled');
  if (data.status !== STATUS.DRAFT) throw consignmentError(CODES.FAILED_PRECONDITION, 'Only draft consignments can be issued');
  const lines = Array.isArray(data.lines) ? data.lines : [];
  if (!lines.length) throw consignmentError(CODES.INVALID_ARGUMENT, 'Cannot issue empty consignment');
  await readReseller(tx, base, data.resellerId, command.lojaId);
  const records = await loadConsignmentStockRecords(tx, base, lines.map(l => l.productId));
  const frozen = [];
  for (const line of lines) {
    const record = records.get(line.productId);
    const classified = classifyConsignmentProduct(record.data);
    if (classified.kind !== line.productType) {
      throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Product type changed after draft');
    }
    const selector = parseVariationSelector(line.variationKey);
    record.data = applyExactConsignmentDelta(record.data, line.productType, selector, -line.qtySent);
    frozen.push({...line, variationKey: selector, variationSnapshot: line.productType === 'simple' ? null : selector});
  }
  const persisted = persistConsignmentStock(tx, base, records, command.operationId, -1);
  if (persisted.writes.length + 8 > 100) throw consignmentError(CODES.RESOURCE_EXHAUSTED, 'Stock transaction write budget exceeded');
  for (const write of persisted.writes) write();
  const issued = {
    ...data,
    lines: frozen.map(l => {
      const {potentialGrossAmount, potentialCommissionAmount, potentialNetAmount, _index, ...rest} = l;
      return {
        ...rest,
        potentialGrossAmount,
        potentialCommissionAmount,
        potentialNetAmount,
      };
    }),
    status: STATUS.ISSUED,
    issuedAt: FieldValue.serverTimestamp(),
    issuedBy: uid,
    issueOperationId: command.operationId,
    revision: (data.revision || 1) + 1,
    totalItemsSent: frozen.reduce((sum, l) => sum + l.qtySent, 0),
    potentialGrossAmount: frozen.reduce((sum, l) => sum + l.potentialGrossAmount, 0),
    potentialCommissionAmount: frozen.reduce((sum, l) => sum + l.potentialCommissionAmount, 0),
    potentialNetAmount: frozen.reduce((sum, l) => sum + l.potentialNetAmount, 0),
  };
  tx.set(ref, issued);
  tx.create(base.collection('consignment_audit').doc(command.operationId), {
    type: 'CONSIGNMENT_ISSUE',
    storeId: command.lojaId,
    consignmentId: command.consignmentId,
    operationId: command.operationId,
    actorUid: uid,
    timestamp: FieldValue.serverTimestamp(),
    affectedProducts: persisted.affected,
    saleId: null,
    financeId: null,
  });
  return {
    consignmentId: command.consignmentId,
    status: STATUS.ISSUED,
    products: persisted.products,
    affected: persisted.affected,
    saleCreated: false,
    financeCreated: false,
  };
}

function settlementLineKey(line) {
  return line.lineId || `${line.productId}::${variationIdentity(parseVariationSelector(line.variationKey))}`;
}

async function settleConsignment(tx, base, command, uid) {
  keysOnly(command.payload, ['lines']);
  const {ref, data} = await loadDraft(tx, base, command);
  if (data.status === STATUS.SETTLED && data.settlementOperationId === command.operationId) {
    return {
      consignmentId: command.consignmentId, status: STATUS.SETTLED, alreadyApplied: true,
      saleId: data.saleId, financeId: data.financeId,
    };
  }
  if (data.status === STATUS.SETTLED) throw consignmentError(CODES.CONSIGNMENT_ALREADY_SETTLED, 'Consignment already settled');
  if (data.status !== STATUS.ISSUED) throw consignmentError(CODES.FAILED_PRECONDITION, 'Only issued consignments can be settled');
  const submitted = command.payload.lines;
  if (!Array.isArray(submitted) || submitted.length !== (data.lines || []).length) {
    throw consignmentError(CODES.INVALID_SETTLEMENT_TOTAL, 'Settlement must include every issued line');
  }
  const byKey = new Map((data.lines || []).map(l => [settlementLineKey(l), l]));
  const settledLines = [];
  let totalSold = 0, totalReturned = 0, grossCents = 0, commissionCents = 0;
  const returnDeltas = [];
  const soldItems = [];
  for (const row of submitted) {
    keysOnly(row, ['lineId','productId','variationKey','qtySold','qtyReturned']);
    const key = row.lineId || `${row.productId}::${variationIdentity(parseVariationSelector(row.variationKey))}`;
    const issued = byKey.get(key);
    if (!issued) throw consignmentError(CODES.INVALID_ARGUMENT, 'Unknown settlement line');
    byKey.delete(key);
    const qtySold = quantityNonNegative(row.qtySold);
    const qtyReturned = quantityNonNegative(row.qtyReturned);
    if (qtySold + qtyReturned !== issued.qtySent) {
      throw consignmentError(CODES.INVALID_SETTLEMENT_TOTAL, 'qtySold + qtyReturned must equal qtySent');
    }
    const amounts = lineAmounts(qtySold, issued.unitSalePriceSnapshot, issued.commissionType, issued.commissionValueSnapshot);
    settledLines.push({
      ...issued,
      qtySold,
      qtyReturned,
      lineGrossAmount: amounts.lineGrossAmount,
      lineCommissionAmount: amounts.lineCommissionAmount,
      lineNetAmount: amounts.lineNetAmount,
    });
    totalSold += qtySold;
    totalReturned += qtyReturned;
    grossCents += Math.round(amounts.lineGrossAmount * 100);
    commissionCents += Math.round(amounts.lineCommissionAmount * 100);
    if (qtyReturned > 0) {
      returnDeltas.push({
        productId: issued.productId,
        productType: issued.productType,
        variationKey: parseVariationSelector(issued.variationKey),
        qty: qtyReturned,
      });
    }
    if (qtySold > 0) {
      soldItems.push({
        produtoNome: issued.productNameSnapshot,
        quantidade: qtySold,
        tamanho: issued.variationKey?.size || '',
        cor: issued.variationKey?.color || '',
        extraValor: issued.variationKey?.extra || '',
        precoUnitario: issued.unitSalePriceSnapshot,
        precoTotal: amounts.lineGrossAmount,
        productId: issued.productId,
        custoUnitario: 0,
        commissionType: issued.commissionType,
        commissionValueSnapshot: issued.commissionValueSnapshot,
        lineCommissionAmount: amounts.lineCommissionAmount,
        lineNetAmount: amounts.lineNetAmount,
      });
    }
  }
  if (byKey.size) throw consignmentError(CODES.INVALID_SETTLEMENT_TOTAL, 'Missing issued lines in settlement');

  let persisted = {products: [], writes: [], affected: []};
  if (returnDeltas.length) {
    const records = await loadConsignmentStockRecords(tx, base, returnDeltas.map(d => d.productId));
    for (const delta of returnDeltas) {
      const record = records.get(delta.productId);
      const classified = classifyConsignmentProduct(record.data);
      if (classified.kind !== delta.productType) {
        throw consignmentError(CODES.PRODUCT_STATE_UNSAFE, 'Product type changed after issue');
      }
      record.data = applyExactConsignmentDelta(record.data, delta.productType, delta.variationKey, delta.qty);
    }
    persisted = persistConsignmentStock(tx, base, records, command.operationId, 1);
  }

  const saleId = soldItems.length ? `csgn_${command.consignmentId}` : null;
  const financeId = soldItems.length && (grossCents - commissionCents) >= 0 ? `csgn_fin_${command.consignmentId}` : null;
  if (saleId) {
    const saleRef = base.collection('estoque_vendas').doc(saleId);
    const existingSale = await tx.get(saleRef);
    if (existingSale.exists) throw consignmentError(CODES.CONSIGNMENT_ALREADY_SETTLED, 'Consignment sale already exists');
    tx.create(saleRef, {
      lojaId: command.lojaId,
      id: saleId,
      origemVenda: 'consignment',
      saleOrigin: 'consignment',
      consignmentId: command.consignmentId,
      resellerId: data.resellerId,
      settlementOperationId: command.operationId,
      stockAlreadyReservedByConsignment: true,
      clienteNome: data.resellerSnapshot?.displayName || data.resellerId,
      clienteId: data.resellerId,
      produtosDescricao: soldItems.map(i => i.produtoNome).join(', '),
      quantidade: totalSold,
      preco: fromCentsSafe(grossCents),
      total: fromCentsSafe(grossCents),
      desconto: 0,
      frete: 0,
      formasPagamento: 'consignacao',
      pagamentoDinheiro: 0,
      pagamentoPix: 0,
      pagamentoCartao: 0,
      taxas: 0,
      custoProdutos: 0,
      commissionAmount: fromCentsSafe(commissionCents),
      netAmount: fromCentsSafe(grossCents - commissionCents),
      vendedor: 'consignacao',
      observacao: `Acerto consignado ${command.consignmentId}`,
      itens: soldItems,
      data: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      status: 'concluida',
      statusVenda: 'concluida',
      cancelada: false,
      estornada: false,
    });
  }
  if (financeId && soldItems.length) {
    const now = new Date();
    tx.create(base.collection('lancamentos_financeiros').doc(financeId), {
      lojaId: command.lojaId,
      descricao: `Consignado ${data.resellerSnapshot?.displayName || data.resellerId}`,
      valor: fromCentsSafe(grossCents - commissionCents),
      tipo: 'entrada_extra',
      categoria: 'consignacao',
      subcategoria: 'acerto',
      status: 'pago',
      formaPagamento: 'consignacao',
      fornecedor: '',
      observacao: `Acerto ${command.consignmentId}; bruto ${fromCentsSafe(grossCents)}; comissao ${fromCentsSafe(commissionCents)}`,
      dataLancamento: FieldValue.serverTimestamp(),
      dataPagamento: FieldValue.serverTimestamp(),
      competenciaMes: now.getUTCMonth() + 1,
      competenciaAno: now.getUTCFullYear(),
      recorrente: false,
      origem: 'consignment',
      usuarioId: uid,
      usuarioNome: '',
      centroCusto: '',
      anexoComprovante: '',
      referenciaExterna: command.consignmentId,
      consignmentId: command.consignmentId,
      saleId,
      commissionAmount: fromCentsSafe(commissionCents),
      grossSoldAmount: fromCentsSafe(grossCents),
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  if (persisted.writes.length + 12 > 100) throw consignmentError(CODES.RESOURCE_EXHAUSTED, 'Stock transaction write budget exceeded');
  for (const write of persisted.writes) write();

  tx.set(ref, {
    ...data,
    lines: settledLines,
    status: STATUS.SETTLED,
    settledAt: FieldValue.serverTimestamp(),
    settledBy: uid,
    settlementOperationId: command.operationId,
    revision: (data.revision || 1) + 1,
    totalItemsSold: totalSold,
    totalItemsReturned: totalReturned,
    grossSoldAmount: fromCentsSafe(grossCents),
    commissionAmount: fromCentsSafe(commissionCents),
    netAmount: fromCentsSafe(grossCents - commissionCents),
    saleId,
    financeId,
  });
  tx.create(base.collection('consignment_audit').doc(command.operationId), {
    type: 'CONSIGNMENT_SETTLEMENT',
    storeId: command.lojaId,
    consignmentId: command.consignmentId,
    operationId: command.operationId,
    actorUid: uid,
    timestamp: FieldValue.serverTimestamp(),
    affectedProducts: persisted.affected,
    sold: totalSold,
    returned: totalReturned,
    saleId,
    financeId,
    grossSoldAmount: fromCentsSafe(grossCents),
    commissionAmount: fromCentsSafe(commissionCents),
    netAmount: fromCentsSafe(grossCents - commissionCents),
  });
  return {
    consignmentId: command.consignmentId,
    status: STATUS.SETTLED,
    products: persisted.products,
    affected: persisted.affected,
    saleId,
    financeId,
    saleCreated: Boolean(saleId),
    financeCreated: Boolean(financeId),
    totalItemsSold: totalSold,
    totalItemsReturned: totalReturned,
    grossSoldAmount: fromCentsSafe(grossCents),
    commissionAmount: fromCentsSafe(commissionCents),
    netAmount: fromCentsSafe(grossCents - commissionCents),
  };
}

function fromCentsSafe(cents) {
  return Math.round(cents) / 100;
}
