/**
 * Ativação de premioRoleta / cupom pós-pagamento MP (catálogo).
 *
 * Chamado após transação principal de estoque em processMpWebhook.
 * Idempotência: _mp_webhook_premio_roleta_processed/{paymentId}
 *
 * Não bloqueia estoque/venda se falhar — side-effect recuperável.
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { carregarPedidoParaPromo } from "./mpWebhookPromo.js";

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
export const PREMIO_ROLETA_PROCESSED_COL = "_mp_webhook_premio_roleta_processed";

const CUPOM_VALIDADE_DIAS = 60;

function logPremio(tag, msg, extra = {}) {
  console.log(`[PREMIO-WEBHOOK] ${tag}`, msg, Object.keys(extra).length ? extra : "");
}

function isAlreadyExistsError(e) {
  return !!(e && (e.code === 6 || e.code === "already-exists"));
}

function isTerminalPremioStatus(st) {
  return (
    st === "done" ||
    st === "skipped_no_premio" ||
    st === "skipped_tipo_nenhum" ||
    st === "skipped_sem_codigo" ||
    st === "skipped_sem_email" ||
    st === "skipped_premio_usado" ||
    st === "skipped_cupom_usado"
  );
}

/**
 * Avaliação pura do premioRoleta para ativação pós-MP.
 */
export function parsePremioRoletaForActivation(orderData) {
  const premio = orderData?.premioRoleta;
  if (!premio || typeof premio !== "object") {
    return { action: "skip", reason: "no_premio" };
  }

  const tipo = String(premio.tipo ?? "nenhum").toLowerCase().trim();
  if (tipo === "nenhum") {
    return { action: "skip", reason: "tipo_nenhum", premio };
  }

  const status = String(premio.status ?? "pendente").toLowerCase().trim();
  if (status === "usado") {
    return { action: "skip", reason: "premio_usado", premio };
  }

  const codigo = String(premio.codigo ?? "").trim();
  const cliente = orderData?.cliente || {};
  const email = String(cliente.email ?? "")
    .trim()
    .toLowerCase();

  if (tipo === "desconto" || tipo === "frete_gratis") {
    if (!codigo) return { action: "skip", reason: "sem_codigo", premio };
    if (!email) return { action: "skip", reason: "sem_email", premio };
    return { action: "activate_cupom", premio, codigo, email, tipo };
  }

  // brinde e outros: ativa apenas no documento do pedido
  return { action: "activate_pedido_only", premio, tipo };
}

export function buildCupomPerfilPayload({ premio, codigo, tipo }) {
  const valor = Number(premio.valor ?? 0);
  const descricaoRaw = String(premio.descricao ?? "").trim();
  const descricao =
    descricaoRaw ||
    (tipo === "frete_gratis" ? "Frete grátis" : `${valor.toFixed(0)}% de desconto`);
  const exp = new Date();
  exp.setDate(exp.getDate() + CUPOM_VALIDADE_DIAS);

  return {
    codigo,
    descricao,
    tipo,
    valor,
    dataGanho: premio.dataGanho ?? FieldValue.serverTimestamp(),
    dataExpiracao: Timestamp.fromDate(exp),
    usado: false,
    ativo: true,
    origem: "roleta_sorte",
  };
}

export function shouldSkipCupomRegression(existing) {
  if (!existing || typeof existing !== "object") return false;
  return existing.usado === true;
}

/**
 * Ativa premioRoleta e cupom no perfil catálogo (idempotente por paymentId).
 */
export async function ativarPremioRoletaPosPagamentoMp(
  db,
  { lojaId, orderId, paymentId, orderData, orderRef },
) {
  const paymentKey = String(paymentId);
  const processedRef = db.collection(PREMIO_ROLETA_PROCESSED_COL).doc(paymentKey);

  if (!lojaId || !orderId) {
    logPremio("[SKIP]", "lojaId/orderId ausente", { paymentId: paymentKey });
    return { ok: false, reason: "missing_ids" };
  }

  let ownLock = false;
  try {
    try {
      await processedRef.create({
        status: "processing",
        lojaId: String(lojaId),
        orderId: String(orderId),
        paymentId: paymentKey,
        lockAt: FieldValue.serverTimestamp(),
      });
      ownLock = true;
    } catch (e) {
      if (!isAlreadyExistsError(e)) throw e;
      const snap = await processedRef.get();
      const st = snap.exists ? snap.data()?.status : null;
      if (isTerminalPremioStatus(st)) {
        logPremio("[IDEMPOTENTE]", "já processado", { paymentId: paymentKey, status: st });
        return { ok: true, skipped: true };
      }
      logPremio("[IDEMPOTENTE]", "lock em curso", { paymentId: paymentKey, status: st });
      return { ok: true, skipped: true };
    }

    const parsed = parsePremioRoletaForActivation(orderData);
    if (parsed.action === "skip") {
      const statusMap = {
        no_premio: "skipped_no_premio",
        tipo_nenhum: "skipped_tipo_nenhum",
        sem_codigo: "skipped_sem_codigo",
        sem_email: "skipped_sem_email",
        premio_usado: "skipped_premio_usado",
      };
      const terminal = statusMap[parsed.reason] || "skipped_no_premio";
      await processedRef.set(
        {
          status: terminal,
          processedAt: FieldValue.serverTimestamp(),
          lojaId: String(lojaId),
          orderId: String(orderId),
        },
        { merge: true },
      );
      return { ok: true, skipped: true, reason: parsed.reason };
    }

    const ref = orderRef;
    if (!ref) {
      throw new Error("orderRef ausente para ativar premioRoleta");
    }

    await ref.set(
      {
        "premioRoleta.status": "ativo",
        "premioRoleta.valido": true,
        "premioRoleta.dataAtivacao": FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    if (parsed.action === "activate_cupom") {
      const cupomRef = db
        .collection(COLLECTION_LOJAS)
        .doc(String(lojaId))
        .collection("clientes_catalogo")
        .doc(parsed.email)
        .collection("cupons")
        .doc(parsed.codigo);

      const existing = await cupomRef.get();
      if (shouldSkipCupomRegression(existing.exists ? existing.data() : null)) {
        await processedRef.set(
          {
            status: "skipped_cupom_usado",
            processedAt: FieldValue.serverTimestamp(),
            cupomCodigo: parsed.codigo,
          },
          { merge: true },
        );
        return { ok: true, skipped: true, reason: "cupom_usado" };
      }

      const payload = buildCupomPerfilPayload({
        premio: parsed.premio,
        codigo: parsed.codigo,
        tipo: parsed.tipo,
      });
      await cupomRef.set(payload, { merge: true });
      logPremio("[CUPOM]", "ativado no perfil", {
        paymentId: paymentKey,
        codigo: parsed.codigo,
        email: parsed.email,
      });
    }

    await processedRef.set(
      {
        status: "done",
        processedAt: FieldValue.serverTimestamp(),
        lojaId: String(lojaId),
        orderId: String(orderId),
        paymentId: paymentKey,
      },
      { merge: true },
    );
    return { ok: true, skipped: false };
  } catch (e) {
    if (ownLock) {
      try {
        await processedRef.delete();
      } catch (delErr) {
        console.error("[PREMIO-ERROR] falha ao liberar lock", delErr?.message);
      }
    }
    console.error("[PREMIO-ERROR]", e?.message || e);
    return { ok: false, error: String(e?.message || e) };
  }
}

export async function ativarPremioRoletaPosPagamentoMpRecovery(
  db,
  { lojaId, orderId, paymentId },
) {
  const loaded = await carregarPedidoParaPromo(db, lojaId, orderId);
  if (!loaded) {
    console.warn("[PREMIO-SKIP] recovery: pedido não encontrado", { lojaId, orderId });
    return { ok: false, reason: "order_not_found" };
  }
  return ativarPremioRoletaPosPagamentoMp(db, {
    lojaId,
    orderId,
    paymentId,
    orderData: loaded.data,
    orderRef: loaded.ref,
  });
}
