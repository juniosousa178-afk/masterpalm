/**
 * 040B3 — estorno canónico de baixa de ContaReceber via backend confiável (Admin SDK).
 * Autorização NÃO usa campos graváveis pelo cliente (lastWriteOrigin, refund, etc.).
 * O cliente só envia lojaId + contaReceberId + baixaId.
 * Estado financeiro é lido do documento canónico no servidor.
 */

export class TrustedRefundError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "TrustedRefundError";
    this.code = code;
  }
}

export const TRUSTED_REFUND_ENTRYPOINT = "estornarBaixaContaReceber";

const MEMBER_ROLES = new Set(["owner", "admin"]);

function asString(v) {
  return String(v ?? "").trim();
}

function asNumber(v, fallback = 0) {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim()) {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function asBool(v, fallback = false) {
  if (typeof v === "boolean") return v;
  return fallback;
}

export function parseHistoricoPagamentos(raw) {
  if (Array.isArray(raw)) {
    return raw
      .filter((h) => h && typeof h === "object")
      .map((h) => ({ ...h }));
  }
  if (typeof raw === "string" && raw.trim()) {
    try {
      const parsed = JSON.parse(raw);
      return parseHistoricoPagamentos(parsed);
    } catch {
      return [];
    }
  }
  return [];
}

/**
 * Contrato mínimo. Ignora saldo/pago/valor/status/lastWriteOrigin enviados pelo cliente.
 */
export function parseTrustedRefundInput(data) {
  const src = data && typeof data === "object" ? data : {};
  const lojaId = asString(src.lojaId);
  const contaReceberId = asString(src.contaReceberId || src.contaReceberDocId);
  const baixaId = asString(src.baixaId);
  if (!lojaId || !contaReceberId || !baixaId) {
    throw new TrustedRefundError(
      "invalid-argument",
      "lojaId, contaReceberId e baixaId são obrigatórios.",
    );
  }
  return { lojaId, contaReceberId, baixaId };
}

export function applyEstornoBaixaToReceivable(data, baixaId, { nowIso } = {}) {
  const hist = parseHistoricoPagamentos(data?.historicoPagamentos);
  const bx = asString(baixaId);
  let valorEstorno = 0;
  let found = false;
  let already = false;

  for (const h of hist) {
    if (asString(h.baixaId) !== bx) continue;
    found = true;
    if (asBool(h.estornada)) {
      already = true;
      break;
    }
    h.estornada = true;
    h.estornoAt = nowIso || new Date().toISOString();
    valorEstorno = asNumber(h.valor);
    break;
  }

  if (!found) {
    return { kind: "baixa_missing" };
  }
  if (already) {
    return {
      kind: "idempotent",
      data: data && typeof data === "object" ? { ...data, historicoPagamentos: hist } : data,
    };
  }
  if (valorEstorno <= 0) {
    return { kind: "baixa_missing" };
  }

  const saldo = asNumber(data?.saldoAtual, asNumber(data?.valor));
  const valorPago = Math.max(0, asNumber(data?.valorPago) - valorEstorno);
  const novoSaldo = saldo + valorEstorno;

  let status = "pendente";
  let pago = false;
  if (novoSaldo < 0.01) {
    status = "paga";
    pago = true;
  } else if (valorPago > 0.01) {
    status = "parcial";
  }

  return {
    kind: "applied",
    data: {
      ...(data && typeof data === "object" ? data : {}),
      historicoPagamentos: hist,
      valorPago,
      saldoAtual: novoSaldo,
      valor: novoSaldo,
      status,
      pago,
    },
  };
}

export async function canAccessLojaFinanceiroServerSide({
  db,
  lojaId,
  uid,
  email,
  isRootAccountEmail,
}) {
  const id = asString(lojaId);
  const userId = asString(uid);
  if (!id || !userId) return false;

  const emailNorm = asString(email).toLowerCase();
  if (typeof isRootAccountEmail === "function" && isRootAccountEmail(emailNorm)) {
    return true;
  }

  const lojaRef = db.collection("lojas").doc(id);
  const [lojaSnap, userSnap, memberSnap, sellerSnap] = await Promise.all([
    lojaRef.get(),
    db.collection("users").doc(userId).get(),
    lojaRef.collection("members").doc(userId).get(),
    lojaRef.collection("vendedores").doc(userId).get(),
  ]);

  const lojaData = lojaSnap.exists ? lojaSnap.data() || {} : {};
  if (asString(lojaData.ownerUid) === userId) {
    return true;
  }

  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const storeId = asString(userData.store_id || userData.storeId);
  if (storeId && storeId === id) {
    if (!lojaData.ownerUid || asString(lojaData.ownerUid) === userId) {
      return true;
    }
  }

  if (memberSnap.exists) {
    const role = asString((memberSnap.data() || {}).role).toLowerCase();
    if (MEMBER_ROLES.has(role)) return true;
  }

  if (sellerSnap.exists) {
    const seller = sellerSnap.data() || {};
    if (seller.ativo === true) return true;
  }

  return false;
}

export async function executeEstornarBaixaContaReceber({
  db,
  lojaId,
  contaReceberId,
  baixaId,
  serverTimestamp,
}) {
  const loja = asString(lojaId);
  const docId = asString(contaReceberId);
  const bx = asString(baixaId);
  const ref = db.collection("lojas").doc(loja).collection("contas_receber").doc(docId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new TrustedRefundError("not-found", "Conta a receber não encontrada.");
    }
    const data = { ...(snap.data() || {}) };
    const docLoja = asString(data.lojaId);
    if (docLoja && docLoja !== loja) {
      throw new TrustedRefundError(
        "permission-denied",
        "Conta a receber não pertence a esta loja.",
      );
    }

    const applied = applyEstornoBaixaToReceivable(data, bx);
    if (applied.kind === "baixa_missing") {
      throw new TrustedRefundError(
        "failed-precondition",
        "Baixa não encontrada para estorno.",
      );
    }
    if (applied.kind === "idempotent") {
      return {
        ok: true,
        idempotent: true,
        status: asString(data.status),
        pago: asBool(data.pago),
        saldoAtual: asNumber(data.saldoAtual, asNumber(data.valor)),
        valorPago: asNumber(data.valorPago),
      };
    }

    const next = {
      ...applied.data,
      lastWriteOrigin: "trusted_refund_fn",
    };
    if (serverTimestamp !== undefined) {
      next.updatedAt = serverTimestamp;
    } else {
      next.updatedAt = new Date().toISOString();
    }
    tx.set(ref, next, { merge: true });
    return {
      ok: true,
      idempotent: false,
      status: next.status,
      pago: next.pago,
      saldoAtual: next.saldoAtual,
      valorPago: next.valorPago,
    };
  });
}

export async function handleEstornarBaixaContaReceber({
  db,
  auth,
  data,
  isRootAccountEmail,
}) {
  if (!auth?.uid) {
    throw new TrustedRefundError("unauthenticated", "Faça login para estornar a baixa.");
  }
  const input = parseTrustedRefundInput(data);
  const allowed = await canAccessLojaFinanceiroServerSide({
    db,
    lojaId: input.lojaId,
    uid: auth.uid,
    email: auth.token?.email || "",
    isRootAccountEmail,
  });
  if (!allowed) {
    throw new TrustedRefundError(
      "permission-denied",
      "Sem permissão para estornar nesta loja.",
    );
  }
  return executeEstornarBaixaContaReceber({
    db,
    lojaId: input.lojaId,
    contaReceberId: input.contaReceberId,
    baixaId: input.baixaId,
  });
}
