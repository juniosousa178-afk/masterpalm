/**
 * Trava atômica (Firestore transaction) para mpCatalogPayment — mesma chave que _idempotency.
 * Elimina corrida entre checkIdempotency e saveIdempotency em instâncias concorrentes.
 *
 * Campos extras no doc _idempotency (somente endpoint mpCatalogPayment):
 * - mpCreating: boolean
 * - mpLockUntil: Timestamp (expiração da trava; após isso nova tentativa pode assumir)
 */

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { getIdempotencyTtlMs } from "./rateLimiter.js";

const IDEMPOTENCY_COL = "_idempotency";
const ENDPOINT = "mpCatalogPayment";

/** Janela em que outra instância não pode criar segunda cobrança (MP timeout ~20s). */
export const MP_CATALOG_LOCK_MS = 90_000;

function idempotencyDocRef(db, catalogIdemKey) {
  if (!catalogIdemKey || catalogIdemKey.length > 128) return null;
  const safeKey = String(catalogIdemKey).replace(/[^a-zA-Z0-9_-]/g, "_");
  const docId = `${ENDPOINT}:${safeKey}`.slice(0, 150);
  return db.collection(IDEMPOTENCY_COL).doc(docId);
}

/**
 * Estado puro para testes — espelha a decisão dentro da transação.
 * @param {object} data — doc.data() ou {}
 */
export function evaluateMpCatalogPaymentLockState(data, nowMs, ttlMs) {
  const d = data && typeof data === "object" ? data : {};
  const createdAt = d.createdAt?.toMillis?.() ?? 0;
  if (d.result != null && createdAt > 0 && nowMs - createdAt < ttlMs) {
    return { kind: "reuse", result: d.result };
  }
  const lockUntil = d.mpLockUntil?.toMillis?.() ?? 0;
  if (d.mpCreating === true && lockUntil > nowMs) {
    return { kind: "busy" };
  }
  return { kind: "acquire" };
}

/**
 * Transação: reusar resultado recente, ou ocupar trava, ou indicar concorrente ativo.
 * @returns {Promise<{ kind: 'reuse', result: object } | { kind: 'busy' } | { kind: 'acquired' } | { kind: 'error', message: string }>}
 */
export async function tryBeginMpCatalogPaymentOrReuse(db, catalogIdemKey) {
  const ref = idempotencyDocRef(db, catalogIdemKey);
  if (!ref) {
    return { kind: "error", message: "idempotency_key_invalid" };
  }
  const ttlMs = getIdempotencyTtlMs(ENDPOINT);
  const now = Date.now();
  const lockExpiry = now + MP_CATALOG_LOCK_MS;

  try {
    return await db.runTransaction(async (txn) => {
      const snap = await txn.get(ref);
      const data = snap.exists ? snap.data() || {} : {};
      const decision = evaluateMpCatalogPaymentLockState(data, now, ttlMs);
      if (decision.kind === "reuse") {
        return { kind: "reuse", result: decision.result };
      }
      if (decision.kind === "busy") {
        return { kind: "busy" };
      }
      txn.set(
        ref,
        {
          mpCreating: true,
          mpLockUntil: Timestamp.fromMillis(lockExpiry),
          endpoint: ENDPOINT,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { kind: "acquired" };
    });
  } catch (e) {
    console.warn(
      JSON.stringify({
        event: "mpCatalogPayment_lock_acquire_failed",
        err: String(e?.message || e),
      }),
    );
    return { kind: "error", message: String(e?.message || e) };
  }
}

/**
 * Persiste resultado (como saveIdempotency) e libera trava numa única escrita transacional.
 */
export async function commitMpCatalogPaymentSuccess(db, catalogIdemKey, result) {
  const ref = idempotencyDocRef(db, catalogIdemKey);
  if (!ref || !result) return;
  try {
    await db.runTransaction(async (txn) => {
      txn.set(
        ref,
        {
          result,
          createdAt: FieldValue.serverTimestamp(),
          endpoint: ENDPOINT,
          mpCreating: false,
          mpLockUntil: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
  } catch (e) {
    console.warn(
      JSON.stringify({
        event: "mpCatalogPayment_lock_commit_failed",
        phase: "success",
        err: String(e?.message || e),
      }),
    );
    throw e;
  }
}

/**
 * Libera trava após falha na API MP ou exceção antes de sucesso (fail-safe).
 */
export async function releaseMpCatalogPaymentLock(db, catalogIdemKey) {
  const ref = idempotencyDocRef(db, catalogIdemKey);
  if (!ref) return;
  try {
    await db.runTransaction(async (txn) => {
      txn.set(
        ref,
        {
          mpCreating: false,
          mpLockUntil: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
  } catch (e) {
    console.warn(
      JSON.stringify({
        event: "mpCatalogPayment_lock_release_failed",
        err: String(e?.message || e),
      }),
    );
  }
}
