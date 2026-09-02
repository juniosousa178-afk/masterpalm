/**
 * Cálculo de período de plano — mesma semântica de activatePlanForUser,
 * com periodStart configurável (ex.: date_approved do provider).
 */

export function addMonths(d, n) {
  const x = new Date(d);
  x.setMonth(x.getMonth() + n);
  return x;
}

export function addYears(d, n) {
  const x = new Date(d);
  x.setFullYear(x.getFullYear() + n);
  return x;
}

/**
 * @param {string} planId
 * @param {Date|string|number} periodStart
 * @param {function(string): string} normalizePlanId
 * @returns {Date|null}
 */
export function computePlanPeriodEnd(planId, periodStart, normalizePlanId) {
  const start = periodStart instanceof Date ? periodStart : new Date(periodStart);
  if (Number.isNaN(start.getTime())) return null;
  const canonical = normalizePlanId(planId);
  if (canonical === "pro_yearly") return addYears(start, 1);
  if (
    canonical === "pro_monthly" ||
    canonical === "basic_monthly" ||
    canonical === "intermediate_monthly"
  ) {
    return addMonths(start, 1);
  }
  return addMonths(start, 1);
}
