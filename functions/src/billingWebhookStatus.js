/**
 * P1C — writes de billing no webhook legado sem degradar users.status.
 */

export function billingPatchForNonApprovedPayment(checkoutStatus, nowTs) {
  const pending =
    String(checkoutStatus || "").toLowerCase() === "pending" ||
    String(checkoutStatus || "").toLowerCase() === "in_process";
  return {
    billingStatus: pending ? "checkout_pending" : "failed",
    updatedAt: nowTs,
  };
}

export function billingPatchContainsAccountStatus(patch) {
  if (!patch || typeof patch !== "object") return false;
  return Object.prototype.hasOwnProperty.call(patch, "status");
}

/**
 * Não-approved nunca despromove conta nem entitlement já activo.
 */
export async function applyLegacyNonApprovedBillingWrite(db, {
  uid,
  checkoutStatus,
  nowTs,
}) {
  const ref = db.collection("users").doc(String(uid));
  const snap = await ref.get();
  const existing = snap.exists ? snap.data() || {} : {};
  const billingStatus = String(existing.billingStatus || "").toLowerCase();
  const accountStatus = String(existing.status || "").toLowerCase();
  if (billingStatus === "active" || accountStatus === "active") {
    const paidPlan = String(existing.currentPlanId || "").toLowerCase();
    const paid = [
      "basic_monthly",
      "intermediate_monthly",
      "pro_monthly",
      "pro_yearly",
    ].includes(paidPlan);
    if (billingStatus === "active" || paid) {
      return { skipped: true, reason: "already_active_no_downgrade" };
    }
  }
  const patch = billingPatchForNonApprovedPayment(checkoutStatus, nowTs);
  await ref.set(patch, { merge: true });
  return { skipped: false, patch };
}
