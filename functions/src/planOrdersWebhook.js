/**
 * Pedidos de plano (assinatura) — reconciliação via Mercado Pago no backend.
 * external_reference canônico = id do doc em plan_orders/{planOrderId}
 */

import crypto from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";

export const PLAN_ORDERS_COL = "plan_orders";

export function generatePlanOrderId() {
  return `po_${crypto.randomBytes(14).toString("hex")}`;
}

/**
 * Reembolso/chargeback: só desfaz se este pagamento ainda é o último que ativou o plano.
 */
export async function revokeIfLastPayment({ db, uid, paymentId, nowTs }) {
  const userRef = db.collection("users").doc(String(uid));
  const snap = await userRef.get();
  const d = snap.exists ? snap.data() || {} : {};
  if (String(d.planLastPaymentId || "") !== String(paymentId)) {
    console.log(
      JSON.stringify({
        evt: "plan_refund_skip",
        reason: "not_last_payment",
        uid,
        paymentId,
        last: d.planLastPaymentId || null,
      }),
    );
    return;
  }
  await userRef
    .collection("subscriptions")
    .doc(String(paymentId))
    .set(
      {
        status: "canceled",
        updatedAt: nowTs,
        revokeReason: "refunded_or_chargeback",
      },
      { merge: true },
    );
  await userRef.set(
    {
      currentPlanId: "free_limited",
      status: "active",
      trialing: false,
      currentPeriodEnd: null,
      planLastPaymentId: FieldValue.delete(),
      updatedAt: nowTs,
    },
    { merge: true },
  );
  console.log(
    JSON.stringify({
      evt: "plan_revoked_refund",
      uid,
      paymentId,
    }),
  );
}

/**
 * Processa webhook quando external_reference aponta para plan_orders/{id}.
 * @returns {Promise<boolean>} true se o evento foi consumido (não seguir legado)
 */
export async function tryProcessPlanOrderWebhook({
  db,
  payment,
  paymentId,
  nowTs,
  normalizePlanId,
  mapCheckoutStatus,
  activatePlanForUser,
}) {
  const externalRef = String(payment.external_reference || "").trim();
  if (!externalRef) return false;

  const orderRef = db.collection(PLAN_ORDERS_COL).doc(externalRef);
  const orderSnap = await orderRef.get();
  if (!orderSnap.exists) return false;

  const order = orderSnap.data() || {};
  const uid = order.userId;
  if (!uid) {
    console.error(
      JSON.stringify({
        evt: "plan_order_invalid",
        planOrderId: externalRef,
        err: "missing_userId",
      }),
    );
    return true;
  }

  const status = payment.status;
  const checkoutStatus = mapCheckoutStatus(status);
  const processedRef = db.collection("processed_plan_payments").doc(String(paymentId));

  await orderRef.set(
    {
      mpPaymentStatus: String(status || ""),
      mpStatusDetail: String(payment.status_detail || ""),
      checkoutMappedStatus: checkoutStatus,
      lastWebhookAt: nowTs,
      lastPaymentId: String(paymentId),
      updatedAt: nowTs,
    },
    { merge: true },
  );

  console.log(
    JSON.stringify({
      evt: "plan_order_webhook",
      planOrderId: externalRef,
      paymentId: String(paymentId),
      mpStatus: status,
      uid,
    }),
  );

  if (status === "approved") {
    let skipDup = false;
    await db.runTransaction(async (tx) => {
      const pr = await tx.get(processedRef);
      const pd = pr.exists ? pr.data() || {} : {};
      if (pr.exists && pd.status === "approved") {
        skipDup = true;
        return;
      }
      tx.set(
        processedRef,
        {
          paymentId: String(paymentId),
          status: "processing",
          planOrderId: externalRef,
          uid,
          updatedAt: nowTs,
          createdAt: pd.createdAt || nowTs,
        },
        { merge: true },
      );
    });
    if (skipDup) {
      console.warn(
        JSON.stringify({
          evt: "plan_order_webhook_duplicate",
          paymentId: String(paymentId),
          planOrderId: externalRef,
        }),
      );
      return true;
    }

    const plan = normalizePlanId(
      order.canonicalPlanId || order.legacyPlanAlias || "pro_monthly",
    );
    await activatePlanForUser({
      uid,
      plan,
      paymentId: String(paymentId),
      status: "active",
      amount: payment.transaction_amount,
      planOrderId: externalRef,
    });

    await orderRef.set(
      {
        orderStatus: "ATIVO",
        paymentConfirmation: "PAGO_CONFIRMADO",
        paidAt: nowTs,
        updatedAt: nowTs,
      },
      { merge: true },
    );

    await processedRef.set(
      {
        paymentId: String(paymentId),
        processedAt: nowTs,
        uid,
        planOrderId: externalRef,
        status: "approved",
        rawStatus: String(status || ""),
      },
      { merge: true },
    );

    console.log(
      JSON.stringify({
        evt: "plan_order_activated",
        planOrderId: externalRef,
        uid,
        paymentId: String(paymentId),
      }),
    );
    return true;
  }

  if (status === "pending" || status === "in_process") {
    await orderRef.set(
      { orderStatus: "PENDENTE", updatedAt: nowTs },
      { merge: true },
    );
    return true;
  }

  if (status === "refunded" || status === "charged_back") {
    await orderRef.set(
      {
        orderStatus: "REEMBOLSADO",
        refundNoticedAt: nowTs,
        updatedAt: nowTs,
      },
      { merge: true },
    );
    await revokeIfLastPayment({ db, uid, paymentId: String(paymentId), nowTs });
    return true;
  }

  if (
    status === "cancelled" ||
    status === "canceled" ||
    status === "rejected"
  ) {
    await orderRef.set(
      {
        orderStatus: status === "rejected" ? "FALHA" : "CANCELADO",
        updatedAt: nowTs,
      },
      { merge: true },
    );
    return true;
  }

  await orderRef.set(
    { orderStatus: "FALHA", updatedAt: nowTs },
    { merge: true },
  );
  return true;
}
