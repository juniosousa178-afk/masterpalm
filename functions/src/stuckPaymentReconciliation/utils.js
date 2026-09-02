/** Utilitários sem PII para monitor/reconciliation. */

export function maskPaymentId(id) {
  const s = String(id || "");
  if (s.length <= 4) return "****";
  return `${"*".repeat(Math.max(0, s.length - 4))}${s.slice(-4)}`;
}

export function toDate(value) {
  if (value == null) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value?.toDate === "function") {
    try {
      const d = value.toDate();
      return d instanceof Date && !Number.isNaN(d.getTime()) ? d : null;
    } catch {
      return null;
    }
  }
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function ageMs(updatedAt, now = new Date()) {
  const d = toDate(updatedAt);
  if (!d) return null;
  return now.getTime() - d.getTime();
}

export const DEFAULT_STALE_THRESHOLD_MS = 5 * 60 * 1000;
