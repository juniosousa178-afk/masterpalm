/**
 * Server-authoritative sale edit: the saved sale is read inside the stock transaction,
 * the stock delta is computed here per exact cell, and stock + sale document commit together.
 */
import {createHash} from 'node:crypto';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';
import {documentId} from './stockCatalogAccess.js';
import {isMap, normKey, quantity, stockError} from './catalogStockProjection.js';

export const SALE_EDIT_KIND = 'saleEdit';
export const MAX_SALE_EDIT_LINES = 200;
export const SALE_EDIT_OPERATION_ID = /^saleedit_[0-9a-f]{64}$/;
/** Mixed edits from clients before saleEdit: `editstock_<saleId>_<sha256>_sale` (then `_restock`). */
export const LEGACY_SPLIT_EDIT_SALE_HALF = /^editstock_(.+)_[0-9a-f]{64}_sale$/;
const LEGACY_SPLIT_EDIT_RESTOCK_HALF = /^editstock_(.+)_[0-9a-f]{64}_restock$/;
const LEGACY_SINGLE_EDIT = /^editstock_(.+)_[0-9a-f]{64}$/;

/** Structured reason codes surfaced to clients in HttpsError.details.code. */
export const SALE_EDIT_REASON = Object.freeze({
  STOCK_CHANGED: 'STOCK_CHANGED',
  INSUFFICIENT_STOCK: 'INSUFFICIENT_STOCK',
  LEGACY_PROTOCOL_BLOCKED: 'LEGACY_PROTOCOL_BLOCKED',
  GRADE_SELECTION_REQUIRED: 'GRADE_SELECTION_REQUIRED',
  SALE_EDIT_CONFLICT: 'SALE_EDIT_CONFLICT',
  INVALID_SALE_EDIT: 'INVALID_SALE_EDIT',
  OPERATION_PAYLOAD_CONFLICT: 'OPERATION_PAYLOAD_CONFLICT',
});

export function saleEditError(httpCode, code, reason, message) {
  const error = stockError(httpCode, message || code);
  error.details = {code, ...(reason ? {reason} : {})};
  return error;
}

const invalid = (reason, message) =>
  saleEditError('failed-precondition', SALE_EDIT_REASON.INVALID_SALE_EDIT, reason, message || 'Invalid sale edit');

const SALE_FIELD_KEYS = Object.freeze([
  'clienteNome', 'clienteId', 'produtosDescricao', 'quantidade', 'preco', 'total',
  'formasPagamento', 'frete', 'desconto', 'descontoValor', 'observacao',
  'pagamentoDinheiro', 'pagamentoPix', 'pagamentoCartao', 'taxas', 'custoProdutos',
  'tamanho', 'vendedor', 'vendedorUid', 'vendedorNome', 'vendedorEmail',
  'itens', 'origemCusto', 'itensComboSelecaoJson', 'saldoFiado',
  'quantidadeParcelasFiado', 'intervaloParcelasDias', 'dataVencimentoFiado', 'data',
]);
const LINE_KEYS = Object.freeze(['produtoNome', 'quantidade', 'tamanho', 'cor', 'precoUnitario', 'precoTotal',
  'productId', 'variacaoExtraResumo', 'extraValor', 'custoUnitario', 'origemCustoItem']);
/** Fiado fields are removed from the sale document when the edited sale has no open balance. */
const FIADO_FIELDS = Object.freeze(['saldoFiado', 'quantidadeParcelasFiado', 'intervaloParcelasDias', 'dataVencimentoFiado']);

function money(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw invalid('INVALID_FIELD', `Invalid ${label}`);
  }
  return value;
}
function text(value, label, max) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalid('INVALID_FIELD', `Invalid ${label}`);
  const trimmed = value.trim();
  if (trimmed.length > max) throw invalid('INVALID_FIELD', `${label} too long`);
  return trimmed;
}
function isoDate(value, label) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length > 40 || Number.isNaN(Date.parse(value))) {
    throw invalid('INVALID_FIELD', `Invalid ${label}`);
  }
  return new Date(Date.parse(value)).toISOString();
}
function positiveInt(value, label) {
  if (!Number.isSafeInteger(value) || value <= 0) throw invalid('INVALID_FIELD', `Invalid ${label}`);
  return value;
}

function parseLine(item, index) {
  if (!isMap(item) || Object.keys(item).some(k => !LINE_KEYS.includes(k))) {
    throw invalid('INVALID_LINE', `Invalid sale line ${index}`);
  }
  const productId = item.productId === undefined || item.productId === null || item.productId === ''
    ? null
    : documentId(item.productId, `sale.itens[${index}].productId`);
  const line = {
    produtoNome: text(item.produtoNome, 'produtoNome', 300) ?? '',
    quantidade: positiveInt(item.quantidade, 'quantidade'),
    tamanho: text(item.tamanho, 'tamanho', 80) ?? '',
    cor: text(item.cor, 'cor', 80) ?? '',
    precoUnitario: money(item.precoUnitario ?? 0, 'precoUnitario'),
    precoTotal: money(item.precoTotal ?? 0, 'precoTotal'),
    custoUnitario: money(item.custoUnitario ?? 0, 'custoUnitario'),
    origemCustoItem: text(item.origemCustoItem, 'origemCustoItem', 40) ?? 'desconhecido',
  };
  if (productId) line.productId = productId;
  const resumo = text(item.variacaoExtraResumo, 'variacaoExtraResumo', 200);
  if (resumo) line.variacaoExtraResumo = resumo;
  const extra = text(item.extraValor, 'extraValor', 80);
  if (extra) line.extraValor = extra;
  return line;
}

/** Client payload: identifiers, the CAS hash of the lines the client edited, and the edited sale fields. */
export function parseSaleEditPayload(raw) {
  if (!isMap(raw) || Object.keys(raw).some(k => !['saleId', 'expectedOriginalLinesHash', 'sale'].includes(k))) {
    throw invalid('INVALID_PAYLOAD', 'Unknown or protected saleEdit field');
  }
  const saleId = documentId(raw.saleId, 'saleId');
  if (typeof raw.expectedOriginalLinesHash !== 'string' || !/^[0-9a-f]{64}$/.test(raw.expectedOriginalLinesHash)) {
    throw invalid('INVALID_PAYLOAD', 'expectedOriginalLinesHash required');
  }
  const s = raw.sale;
  if (!isMap(s) || Object.keys(s).some(k => !SALE_FIELD_KEYS.includes(k))) {
    throw invalid('INVALID_PAYLOAD', 'Unknown or protected sale field');
  }
  if (!Array.isArray(s.itens) || s.itens.length === 0) throw invalid('EMPTY_SALE', 'sale.itens required');
  if (s.itens.length > MAX_SALE_EDIT_LINES) {
    throw saleEditError('resource-exhausted', SALE_EDIT_REASON.INVALID_SALE_EDIT, 'SALE_EDIT_TOO_LARGE', 'Too many sale lines');
  }
  const clienteNome = text(s.clienteNome, 'clienteNome', 200);
  if (!clienteNome) throw invalid('INVALID_FIELD', 'clienteNome required');
  const sale = {
    clienteNome,
    clienteId: text(s.clienteId, 'clienteId', 128),
    produtosDescricao: text(s.produtosDescricao, 'produtosDescricao', 20000) ?? '',
    quantidade: positiveInt(s.quantidade ?? s.itens.length, 'quantidade'),
    preco: money(s.preco ?? 0, 'preco'),
    total: money(s.total, 'total'),
    formasPagamento: text(s.formasPagamento, 'formasPagamento', 2000) ?? '',
    frete: money(s.frete ?? 0, 'frete'),
    desconto: money(s.desconto ?? 0, 'desconto'),
    descontoValor: money(s.descontoValor ?? 0, 'descontoValor'),
    observacao: text(s.observacao, 'observacao', 2000) ?? '',
    pagamentoDinheiro: money(s.pagamentoDinheiro ?? 0, 'pagamentoDinheiro'),
    pagamentoPix: money(s.pagamentoPix ?? 0, 'pagamentoPix'),
    pagamentoCartao: money(s.pagamentoCartao ?? 0, 'pagamentoCartao'),
    taxas: money(s.taxas ?? 0, 'taxas'),
    custoProdutos: money(s.custoProdutos ?? 0, 'custoProdutos'),
    tamanho: text(s.tamanho, 'tamanho', 80) ?? '',
    vendedor: text(s.vendedor, 'vendedor', 200) ?? 'App',
    vendedorUid: text(s.vendedorUid, 'vendedorUid', 128),
    vendedorNome: text(s.vendedorNome, 'vendedorNome', 200),
    vendedorEmail: text(s.vendedorEmail, 'vendedorEmail', 200),
    itens: s.itens.map(parseLine),
    origemCusto: text(s.origemCusto, 'origemCusto', 40),
    itensComboSelecaoJson: text(s.itensComboSelecaoJson, 'itensComboSelecaoJson', 20000),
    saldoFiado: money(s.saldoFiado ?? 0, 'saldoFiado'),
    quantidadeParcelasFiado: s.quantidadeParcelasFiado === undefined || s.quantidadeParcelasFiado === null
      ? null : positiveInt(s.quantidadeParcelasFiado, 'quantidadeParcelasFiado'),
    intervaloParcelasDias: s.intervaloParcelasDias === undefined || s.intervaloParcelasDias === null
      ? null : positiveInt(s.intervaloParcelasDias, 'intervaloParcelasDias'),
    dataVencimentoFiado: isoDate(s.dataVencimentoFiado, 'dataVencimentoFiado'),
    data: isoDate(s.data, 'data'),
  };
  return {saleId, expectedOriginalLinesHash: raw.expectedOriginalLinesHash, sale};
}

/** Stored lines are tolerant (legacy keys); quantities must still be positive integers. */
export function storedSaleLines(itens) {
  if (!Array.isArray(itens)) return [];
  return itens.filter(isMap).map((m, index) => {
    const raw = m.quantidade ?? m.qty;
    const q = typeof raw === 'number' && Number.isFinite(raw) && Number.isInteger(raw) ? raw : NaN;
    if (!Number.isSafeInteger(q) || q < 0) throw invalid('STORED_SALE_LINES_INVALID', `Stored sale line ${index} invalid`);
    const productId = String(m.productId ?? m.id ?? '').trim();
    return {
      productId: productId || null,
      produtoNome: String(m.produtoNome ?? m.nome ?? m.produto ?? m.name ?? '').trim(),
      quantidade: q,
      tamanho: String(m.tamanho ?? m.size ?? '').trim(),
      cor: String(m.cor ?? m.color ?? '').trim(),
      extraValor: String(m.extraValor ?? '').trim(),
    };
  }).filter(l => l.quantidade > 0);
}

/** Stock identity of a sale line. Lines without productId are identified by normalized name. */
function lineKey(line) {
  const pid = String(line.productId ?? '').trim();
  return [pid, pid ? '' : normKey(line.produtoNome ?? ''), normKey(line.tamanho ?? ''),
    normKey(line.cor ?? ''), normKey(line.extraValor ?? '')];
}

function aggregate(lines) {
  const out = new Map();
  for (const line of lines) {
    const key = lineKey(line);
    const id = JSON.stringify(key);
    const prev = out.get(id);
    out.set(id, {key, line: prev?.line ?? line, quantity: (prev?.quantity ?? 0) + line.quantidade});
  }
  return out;
}

/**
 * Order-insensitive sha256 over aggregated stock identities and quantities.
 * Mirrored by the Dart client (`VendaEdicaoEstoqueDiff.saleEditLinesHash`).
 */
export function saleLinesHash(lines) {
  const rows = [...aggregate(lines).values()].filter(r => r.quantity > 0)
    .map(r => [...r.key, r.quantity])
    .sort((a, b) => {
      const ka = JSON.stringify(a.slice(0, 5)), kb = JSON.stringify(b.slice(0, 5));
      return ka < kb ? -1 : ka > kb ? 1 : 0;
    });
  return createHash('sha256').update(JSON.stringify(rows), 'utf8').digest('hex');
}

/**
 * Per exact cell delta. Restores (old > new) only come from cells present in the saved sale and
 * never exceed the quantity the saved sale consumed; debits are new or increased cells.
 */
export function computeSaleEditDelta(oldLines, newLines) {
  const before = aggregate(oldLines), after = aggregate(newLines);
  const items = [];
  for (const id of new Set([...before.keys(), ...after.keys()])) {
    const o = before.get(id), n = after.get(id);
    const delta = (n?.quantity ?? 0) - (o?.quantity ?? 0);
    if (delta === 0) continue;
    const line = (delta < 0 ? o : n).line;
    if (!line.productId) throw invalid('LINE_PRODUCT_ID_REQUIRED', 'Changed sale line has no productId');
    items.push({
      productId: line.productId,
      quantity: quantity(Math.abs(delta)),
      size: String(line.tamanho ?? '').trim(),
      color: String(line.cor ?? '').trim(),
      extra: String(line.extraValor ?? '').trim(),
      direction: delta < 0 ? 'restore' : 'debit',
    });
  }
  // Restores first: a cell moved within the same product never needs transient stock.
  return items.sort((a, b) => (a.direction === b.direction ? 0 : a.direction === 'restore' ? -1 : 1));
}

const CLOSED_STATUSES = new Set(['cancelada', 'cancelado', 'estornada', 'estornado', 'excluida', 'excluido']);

/** Validates the stored sale and returns the edit plan. All reads happen before any write. */
export async function loadSaleEditPlan(tx, base, command) {
  const {saleId, expectedOriginalLinesHash, sale} = command.saleEdit;
  const saleRef = base.collection('estoque_vendas').doc(saleId);
  const saleSnap = await tx.get(saleRef);
  if (!saleSnap.exists) throw invalid('SALE_NOT_FOUND', 'Sale not found');
  const stored = saleSnap.data() || {};
  if (stored.lojaId !== undefined && stored.lojaId !== null && stored.lojaId !== command.lojaId) {
    throw invalid('SALE_STORE_MISMATCH', 'Sale belongs to another store');
  }
  const status = String(stored.statusVenda ?? '').trim().toLowerCase();
  if (stored.cancelada === true || stored.estornada === true || CLOSED_STATUSES.has(status)) {
    throw invalid('SALE_NOT_EDITABLE', 'Sale is cancelled or reversed');
  }
  const oldLines = storedSaleLines(stored.itens);
  const originalLinesHash = saleLinesHash(oldLines);
  if (originalLinesHash !== expectedOriginalLinesHash) {
    throw saleEditError('aborted', SALE_EDIT_REASON.SALE_EDIT_CONFLICT, 'ORIGINAL_LINES_CHANGED',
      'Sale lines changed since the edit started');
  }
  const oldCombo = String(stored.itensComboSelecaoJson ?? '').trim();
  const newCombo = String(sale.itensComboSelecaoJson ?? '').trim();
  // Component selections move component stock even when the sale lines are unchanged.
  if (oldCombo !== newCombo) {
    throw invalid('COMBO_EDIT_NOT_SUPPORTED', 'Combo selection changes are not supported in sale edit');
  }
  const items = computeSaleEditDelta(oldLines, sale.itens);

  // Stock lineage of the sale: explicit binding first, then the modern convention (op id == sale id).
  const boundId = String(stored.stockOperationId ?? '').trim();
  const candidates = [...new Set([boundId, saleId].filter(Boolean))];
  let saleOp = null;
  for (const id of candidates) {
    try { documentId(id); } catch { continue; }
    const ref = base.collection('stock_catalog_operations').doc(id);
    const snap = await tx.get(ref);
    if (snap.exists && snap.data()?.kind === 'sale' && snap.data()?.status === 'applied') {
      saleOp = {ref, data: snap.data()};
      break;
    }
  }
  if (saleOp?.data.restoredBy) throw invalid('SALE_ALREADY_RESTORED', 'Sale stock already restored');

  return {
    saleRef,
    stored,
    oldLines,
    originalLinesHash,
    newLinesHash: saleLinesHash(storedSaleLines(sale.itens)),
    items,
    saleOp,
    revision: (Number.isSafeInteger(stored.saleEditRevision) ? stored.saleEditRevision : 0) + 1,
  };
}

/** Sale document patch: client-edited fields plus server lineage. Identity fields are never touched. */
export function buildSaleEditPatch(command, plan, {actorUid}) {
  const s = command.saleEdit.sale;
  const patch = {
    clienteNome: s.clienteNome,
    produtosDescricao: s.produtosDescricao,
    quantidade: s.quantidade,
    preco: s.preco,
    total: s.total,
    formasPagamento: s.formasPagamento,
    frete: s.frete,
    desconto: s.desconto,
    descontoValor: s.descontoValor,
    observacao: s.observacao,
    pagamentoDinheiro: s.pagamentoDinheiro,
    pagamentoPix: s.pagamentoPix,
    pagamentoCartao: s.pagamentoCartao,
    taxas: s.taxas,
    custoProdutos: s.custoProdutos,
    tamanho: s.tamanho,
    vendedor: s.vendedor,
    itens: s.itens,
    clienteId: s.clienteId,
    updatedAt: FieldValue.serverTimestamp(),
    saleEditRevision: plan.revision,
    lastSaleEditOperationId: command.operationId,
    lastSaleEditActorUid: actorUid,
    lastSaleEditAt: FieldValue.serverTimestamp(),
  };
  for (const key of ['vendedorUid', 'vendedorNome', 'vendedorEmail', 'origemCusto']) {
    if (s[key]) patch[key] = s[key];
  }
  patch.itensComboSelecaoJson = s.itensComboSelecaoJson ? s.itensComboSelecaoJson : FieldValue.delete();
  if (s.data) patch.data = Timestamp.fromDate(new Date(s.data));
  if (s.saldoFiado > 0.01) {
    patch.saldoFiado = s.saldoFiado;
    patch.quantidadeParcelasFiado = s.quantidadeParcelasFiado && s.quantidadeParcelasFiado > 1
      ? s.quantidadeParcelasFiado : FieldValue.delete();
    patch.intervaloParcelasDias = s.quantidadeParcelasFiado && s.quantidadeParcelasFiado > 1
      ? (s.intervaloParcelasDias ?? 30) : FieldValue.delete();
    patch.dataVencimentoFiado = s.dataVencimentoFiado
      ? Timestamp.fromDate(new Date(s.dataVencimentoFiado)) : FieldValue.delete();
  } else {
    for (const key of FIADO_FIELDS) patch[key] = FieldValue.delete();
  }
  return patch;
}

/**
 * Keeps the applied sale operation aligned with what the sale now consumes, so a later
 * restore (sale deletion) returns the edited quantities. When the recorded items cannot
 * absorb the delta exactly, the operation is flagged and restore keeps its prior behaviour.
 */
export function nextSaleOperationItems(saleOpData, deltaItems) {
  const base = Array.isArray(saleOpData?.currentItems) && !saleOpData?.currentItemsUnreliable
    ? saleOpData.currentItems
    : saleOpData?.items;
  if (!Array.isArray(base) || saleOpData?.currentItemsUnreliable) return {unreliable: true};
  const cell = i => JSON.stringify([i.productId, normKey(i.size ?? ''), normKey(i.color ?? ''), normKey(i.extra ?? '')]);
  const rows = new Map();
  for (const item of base) {
    if (!isMap(item) || typeof item.productId !== 'string') return {unreliable: true};
    const id = cell(item);
    const prev = rows.get(id);
    rows.set(id, {
      productId: item.productId, size: item.size ?? '', color: item.color ?? '', extra: item.extra ?? '',
      quantity: (prev?.quantity ?? 0) + (Number.isSafeInteger(item.quantity) ? item.quantity : NaN),
    });
  }
  for (const d of deltaItems) {
    const id = cell(d);
    const prev = rows.get(id);
    const next = (prev?.quantity ?? 0) + (d.direction === 'debit' ? d.quantity : -d.quantity);
    if (!Number.isSafeInteger(next) || next < 0) return {unreliable: true};
    rows.set(id, prev ? {...prev, quantity: next}
      : {productId: d.productId, size: d.size, color: d.color, extra: d.extra, quantity: next});
  }
  return {items: [...rows.values()].filter(r => r.quantity > 0)};
}

function safeBuild(value) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  return /^[A-Za-z0-9._+:\-]{1,80}$/.test(v) ? v : null;
}

export function parseClientBuild(value) {
  if (value === undefined) return null;
  const build = safeBuild(value);
  if (!build) throw stockError('invalid-argument', 'Invalid clientBuild');
  return build;
}

/** Classifies a stock command by its id shape for observability; ids carry no customer data. */
export function stockCommandOperationType(raw) {
  const kind = typeof raw?.kind === 'string' ? raw.kind : 'unknown';
  const opId = typeof raw?.operationId === 'string' ? raw.operationId : '';
  let match;
  if (kind === SALE_EDIT_KIND) return {operationType: 'saleEdit', saleId: isMap(raw?.saleEdit) && typeof raw.saleEdit.saleId === 'string' ? raw.saleEdit.saleId : null};
  if ((match = LEGACY_SPLIT_EDIT_SALE_HALF.exec(opId))) return {operationType: 'legacyEditSplitSale', saleId: match[1]};
  if ((match = LEGACY_SPLIT_EDIT_RESTOCK_HALF.exec(opId))) return {operationType: 'legacyEditSplitRestock', saleId: match[1]};
  if ((match = LEGACY_SINGLE_EDIT.exec(opId))) return {operationType: 'legacyEditSingle', saleId: match[1]};
  return {operationType: kind, saleId: null};
}

/** Single-line structured log entry for a rejected stock command (no PII, no payload contents). */
export function stockCommandRejectionLog(raw, error) {
  const {operationType, saleId} = stockCommandOperationType(raw);
  const details = isMap(error?.details) ? error.details : {};
  const saleRef = saleId ? createHash('sha256').update(saleId).digest('hex').slice(0, 16) : null;
  return {
    severity: 'WARNING',
    message: 'stock_command_rejected',
    storeId: typeof raw?.lojaId === 'string' ? raw.lojaId.slice(0, 128) : null,
    kind: typeof raw?.kind === 'string' ? raw.kind.slice(0, 40) : null,
    operationType,
    saleRef,
    reasonCode: String(details.code || error?.stockCode || '').slice(0, 64) || null,
    reason: details.reason ? String(details.reason).slice(0, 64) : null,
    httpCode: typeof error?.code === 'string' ? error.code : 'internal',
    errorMessage: String(error?.message || '').slice(0, 120),
    clientBuild: safeBuild(raw?.clientBuild),
  };
}
