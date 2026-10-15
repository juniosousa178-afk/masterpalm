/**
 * Receivable (contas_receber) reconciliation for server-authoritative sale edits.
 * Linked receivables are read inside the saleEdit transaction and written in the same
 * commit as the sale document, so the sale and its receivable can never diverge.
 * Mirrors the client financial model (VendasService._atualizarContasReceberAposEdicaoVenda).
 */
import {createHash} from 'node:crypto';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';
import {saleEditError, SALE_EDIT_REASON} from './stockCatalogSaleEdit.js';

export const RECEIVABLE_ACTION = Object.freeze({
  NONE: 'NONE',
  CREATE: 'CREATE',
  UPDATE: 'UPDATE',
  SOFT_DELETE: 'SOFT_DELETE',
});
export const SALE_EDIT_REMOVED_FIADO = 'SALE_EDIT_REMOVED_FIADO';
export const RECEIVABLE_WRITE_ORIGIN = 'sale_edit_server';
const EPS = 0.01;
const MAX_PARCELS = 48;
/** Upper bound on linked docs read per sale; more than this is not a sale-shaped receivable set. */
const MAX_LINKED = MAX_PARCELS + 12;
const DAY_MS = 86_400_000;

const receivableError = (reason, message) =>
  saleEditError('failed-precondition', SALE_EDIT_REASON.INVALID_SALE_EDIT, reason, message);

export function stableReceivableId(saleId, parcela) {
  return `cr_${String(saleId).trim().replace(/[/:]/g, '_')}_p${parcela}`;
}

const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
const balance = d => num(d.saldoAtual ?? d.valor);

export function isCancelledReceivable(d) {
  return d.cancelada === true || d.deletedAt != null || String(d.status ?? '').trim().toLowerCase() === 'cancelada';
}
function isPaidReceivable(d) {
  return d.pago === true || String(d.status ?? '').trim().toLowerCase() === 'paga';
}
function hasPayments(d) {
  return num(d.valorPago) > EPS || (Array.isArray(d.historicoPagamentos) && d.historicoPagamentos.length > 0);
}

/** Open balance of a sale (fiado / mixed); stored sales may predate the saldoFiado field. */
export function saleOpenBalance(sale) {
  if (typeof sale?.saldoFiado === 'number' && Number.isFinite(sale.saldoFiado)) return Math.max(0, sale.saldoFiado);
  const paid = num(sale?.pagamentoDinheiro) + num(sale?.pagamentoPix) + num(sale?.pagamentoCartao);
  return Math.max(0, num(sale?.total) - paid);
}

export function paymentMode(sale) {
  const open = saleOpenBalance(sale);
  if (open <= EPS) return 'PAID';
  const paid = num(sale?.pagamentoDinheiro) + num(sale?.pagamentoPix) + num(sale?.pagamentoCartao);
  return paid > EPS ? 'MIXED_FIADO' : 'FIADO';
}

/** Same split as the client `_parcelarValores`: cents spread over parcels, remainder first. */
export function splitParcels(total, parcels) {
  const qtd = Math.min(Math.max(parcels, 1), MAX_PARCELS);
  const cents = Math.round(total * 100);
  const base = Math.floor(cents / qtd);
  const rest = cents % qtd;
  return Array.from({length: qtd}, (_, i) => (base + (i < rest ? 1 : 0)) / 100);
}

/**
 * All docs linked to the sale by `vendaIdFirebase`, plus the stable ids a new fiado would use.
 * Reads only; must run before any transactional write.
 */
export async function loadSaleEditReceivables(tx, base, command) {
  const {saleId, sale} = command.saleEdit;
  const coll = base.collection('contas_receber');
  const snap = await tx.get(coll.where('vendaIdFirebase', '==', saleId).limit(MAX_LINKED + 1));
  if (snap.size > MAX_LINKED) {
    throw receivableError('RECEIVABLE_REQUIRES_REVIEW', 'Too many receivables linked to this sale');
  }
  const docs = new Map(snap.docs.map(d => [d.id, {id: d.id, ref: d.ref ?? coll.doc(d.id), data: d.data() || {}}]));
  if (sale.saldoFiado > EPS) {
    const qtd = Math.min(Math.max(sale.quantidadeParcelasFiado ?? 1, 1), MAX_PARCELS);
    const missing = [];
    for (let p = 1; p <= qtd; p++) {
      const id = stableReceivableId(saleId, p);
      if (!docs.has(id)) missing.push(coll.doc(id));
    }
    if (missing.length) {
      for (const s of await tx.getAll(...missing)) {
        if (s.exists) docs.set(s.id ?? s.ref.id, {id: s.id ?? s.ref.id, ref: s.ref, data: s.data() || {}});
      }
    }
  }
  return [...docs.values()];
}

function audit(command, plan) {
  return {
    lastWriteOrigin: RECEIVABLE_WRITE_ORIGIN,
    saleEditOperationId: command.operationId,
    saleEditRevision: plan.revision,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function saleDate(sale, stored) {
  if (sale.data) return Timestamp.fromDate(new Date(sale.data));
  if (stored?.data instanceof Timestamp) return stored.data;
  return null;
}

/**
 * Pure decision for one saleEdit. Returns {action, writes:[{type,ref,data}], count, oldPaymentMode, newPaymentMode}
 * or throws a structured INVALID_SALE_EDIT error (nothing is written).
 */
export function planSaleEditReceivable({base, command, plan, linked}) {
  const {saleId, sale} = command.saleEdit;
  const lojaId = command.lojaId;
  const coll = base.collection('contas_receber');
  const summary = {oldPaymentMode: paymentMode(plan.stored), newPaymentMode: paymentMode(sale)};
  const none = {...summary, action: RECEIVABLE_ACTION.NONE, count: 0, writes: []};

  for (const r of linked) {
    if (r.data.lojaId !== undefined && r.data.lojaId !== null && r.data.lojaId !== lojaId) {
      throw receivableError('RECEIVABLE_REQUIRES_REVIEW', 'Receivable belongs to another store');
    }
  }
  const active = linked
    .filter(r => r.data.vendaIdFirebase === saleId && !isCancelledReceivable(r.data))
    .sort((a, b) => num(a.data.parcelaNumero) - num(b.data.parcelaNumero) || a.id.localeCompare(b.id));
  const newOpen = sale.saldoFiado;

  // E / A: the edited sale has no open balance.
  if (newOpen <= EPS) {
    if (!active.length) return none;
    if (active.some(r => hasPayments(r.data) || isPaidReceivable(r.data))) {
      throw receivableError('RECEIVABLE_HAS_PAYMENTS', 'Receivable has payments; fiado cannot be removed');
    }
    return {
      ...summary,
      action: RECEIVABLE_ACTION.SOFT_DELETE,
      count: active.length,
      writes: active.map(r => ({
        type: 'set-merge',
        ref: r.ref,
        data: {
          cancelada: true,
          deletedAt: FieldValue.serverTimestamp(),
          status: 'cancelada',
          saldoAtual: 0,
          valor: 0,
          pago: false,
          motivoCancelamento: SALE_EDIT_REMOVED_FIADO,
          saldoAntesCancelamento: balance(r.data),
          ...audit(command, plan),
        },
      })),
    };
  }

  if (!sale.dataVencimentoFiado) {
    if (!active.length) return none;
    throw receivableError('FIADO_DUE_DATE_REQUIRED', 'Fiado due date required');
  }

  // B: fiado without a live receivable — create the client-shaped parcels at stable ids.
  if (!active.length) {
    const qtd = Math.min(Math.max(sale.quantidadeParcelasFiado ?? 1, 1), MAX_PARCELS);
    const interval = Math.min(Math.max(sale.intervaloParcelasDias ?? 30, 1), 120);
    const values = splitParcels(newOpen, qtd);
    const due = Date.parse(sale.dataVencimentoFiado);
    const obs = String(sale.observacao ?? '').trim();
    const dataVenda = saleDate(sale, plan.stored);
    const writes = values.map((v, i) => {
      const id = stableReceivableId(saleId, i + 1);
      const prior = linked.find(r => r.id === id);
      if (prior) {
        // A sale edit may restore a fiado it removed earlier; any other prior doc needs review.
        const reopenable = isCancelledReceivable(prior.data) &&
          prior.data.motivoCancelamento === SALE_EDIT_REMOVED_FIADO && !hasPayments(prior.data);
        if (!reopenable) throw receivableError('RECEIVABLE_REQUIRES_REVIEW', 'Existing receivable blocks fiado');
      }
      return {
        type: 'set',
        ref: prior?.ref ?? coll.doc(id),
        data: {
          lojaId,
          contaReceberId: id,
          vendaIdFirebase: saleId,
          vendaKey: -1,
          clienteId: '',
          clienteNome: sale.clienteNome,
          valorOriginal: v,
          valorPago: 0,
          saldoAtual: v,
          valor: v,
          status: 'pendente',
          pago: false,
          parcelaNumero: i + 1,
          parcelaTotal: qtd,
          dataVencimento: Timestamp.fromMillis(due + i * interval * DAY_MS),
          ...(dataVenda ? {dataVenda} : {}),
          observacao: qtd > 1 ? `Parcela ${i + 1}/${qtd}${obs ? ` - ${obs}` : ''}` : (obs || 'Venda fiada'),
          historicoPagamentos: [],
          lembrete2DiasEnviado: false,
          cancelada: false,
          deletedAt: null,
          schemaVersion: 1,
          ...(prior ? {reabertaAposCancelamento: {motivo: SALE_EDIT_REMOVED_FIADO,
            operationId: String(prior.data.saleEditOperationId ?? '')}} : {}),
          ...audit(command, plan),
        },
      };
    });
    return {...summary, action: RECEIVABLE_ACTION.CREATE, count: writes.length, writes};
  }

  // C / D: fiado stays; keep payments, move only the open balance.
  const paid = active.reduce((s, r) => s + num(r.data.valorPago), 0);
  const target = Math.max(0, newOpen - paid);
  const current = active.reduce((s, r) => s + balance(r.data), 0);
  if (Math.abs(current - target) <= EPS) return none;

  const review = () => receivableError('RECEIVABLE_REQUIRES_REVIEW', 'Receivable cannot be adjusted automatically');
  const updateTo = (r, value, extra = {}) => {
    if (value < EPS) throw review();
    const valorPago = num(r.data.valorPago);
    return {
      type: 'update',
      ref: r.ref,
      data: {
        valor: value,
        saldoAtual: value,
        valorOriginal: value + valorPago,
        status: valorPago > EPS ? 'parcial' : 'pendente',
        pago: false,
        clienteNome: sale.clienteNome,
        ...extra,
        ...audit(command, plan),
      },
    };
  };
  let writes;
  if (active.length === 1) {
    const r = active[0];
    if (isPaidReceivable(r.data) || balance(r.data) < EPS) throw review();
    writes = [updateTo(r, target, {dataVencimento: Timestamp.fromDate(new Date(sale.dataVencimentoFiado))})];
  } else {
    if (current <= EPS) throw review();
    const factor = target / current;
    writes = active
      .filter(r => !isPaidReceivable(r.data) && balance(r.data) >= EPS)
      .map(r => updateTo(r, balance(r.data) * factor));
  }
  return {...summary, action: RECEIVABLE_ACTION.UPDATE, count: writes.length, writes};
}

/** Structured success entry for a saleEdit (no PII: store id, hashed sale ref, op id, modes, action). */
export function saleEditAppliedLog(raw, result) {
  const saleId = typeof raw?.saleEdit?.saleId === 'string' ? raw.saleEdit.saleId : '';
  const r = result?.receivable ?? {};
  return {
    severity: 'INFO',
    message: 'sale_edit_applied',
    storeId: typeof raw?.lojaId === 'string' ? raw.lojaId.slice(0, 128) : null,
    saleRef: saleId ? createHash('sha256').update(saleId).digest('hex').slice(0, 16) : null,
    operationId: typeof result?.operationId === 'string' ? result.operationId.slice(0, 80) : null,
    saleEditRevision: result?.saleEditRevision ?? null,
    oldPaymentMode: r.oldPaymentMode ?? null,
    newPaymentMode: r.newPaymentMode ?? null,
    receivableAction: r.action ?? null,
    receivableCount: Number.isInteger(r.count) ? r.count : null,
    result: result?.alreadyApplied ? 'replay' : 'applied',
  };
}
