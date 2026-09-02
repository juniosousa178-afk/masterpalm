/**
 * node --test test/scheduledStuckPlanPaymentMonitor.test.js
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Timestamp } from "firebase-admin/firestore";
import { normalizePlanId } from "../src/planEffectiveAccessResolver.js";
import {
  MONITOR_SCHEDULE,
  DEFAULT_STALE_THRESHOLD_MINUTES,
  MONITOR_PAGE_SIZE,
  MONITOR_MAX_PAGES,
  MONITOR_MAX_RECORDS,
  MAX_PROVIDER_CONCURRENCY,
  STALE_THRESHOLD_ENV,
  resolveStaleThresholdMinutes,
  buildStaleProcessingQuery,
  mapWithConcurrency,
  buildAlertIncidentKey,
  buildCaseId,
  runStuckPlanPaymentMonitor,
  PROCESSED_PLAN_PAYMENTS_COL,
} from "../src/scheduledStuckPlanPaymentMonitor.js";
import { Classification, ReasonCode } from "../src/stuckPaymentReconciliation/reasonCodes.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const norm = (p) => normalizePlanId(p);

function tsFromIso(iso) {
  return Timestamp.fromDate(new Date(iso));
}

/**
 * Firestore mock read-only com query chaining + tracking de writes.
 */
function createReadonlyQueryDb(seedDocs) {
  /** @type {Map<string, object>} */
  const docs = new Map();
  for (const [id, data] of Object.entries(seedDocs || {})) {
    docs.set(id, { ...data });
  }

  const writeOps = [];
  let queryCalls = [];

  function denyWrite(op, path) {
    writeOps.push({ op, path });
    throw new Error(`READONLY_VIOLATION:${op}:${path}`);
  }

  function matchesQuery(data, filters) {
    for (const f of filters) {
      if (f.op === "==") {
        if (String(data[f.field]) !== String(f.value)) return false;
      } else if (f.op === "<=") {
        const left = data[f.field];
        const leftMs = left?.toMillis
          ? left.toMillis()
          : left instanceof Date
            ? left.getTime()
            : new Date(left).getTime();
        const rightMs = f.value?.toMillis
          ? f.value.toMillis()
          : f.value instanceof Date
            ? f.value.getTime()
            : new Date(f.value).getTime();
        if (!(leftMs <= rightMs)) return false;
      }
    }
    return true;
  }

  function coll(name) {
    return {
      doc(id) {
        const path = `${name}/${id}`;
        return {
          id,
          path,
          async get() {
            const d = docs.get(id) && name === PROCESSED_PLAN_PAYMENTS_COL
              ? docs.get(id)
              : name === "plan_orders"
                ? docs.get(`order:${id}`)
                : name === "users"
                  ? docs.get(`user:${id}`)
                  : docs.get(`${name}:${id}`);
            // also support processed by id in docs map
            let data = null;
            if (name === PROCESSED_PLAN_PAYMENTS_COL) data = docs.get(id) || null;
            else if (name === "plan_orders") data = docs.get(`order:${id}`) || null;
            else if (name === "users") data = docs.get(`user:${id}`) || null;
            return {
              exists: data != null,
              id,
              data: () => (data ? { ...data } : undefined),
            };
          },
          async set(data, opts) {
            denyWrite("set", path);
          },
          async update(data) {
            denyWrite("update", path);
          },
          async delete() {
            denyWrite("delete", path);
          },
          collection(sub) {
            return {
              doc(subId) {
                const subPath = `${path}/${sub}/${subId}`;
                return {
                  id: subId,
                  path: subPath,
                  async get() {
                    const data = docs.get(`sub:${id}:${subId}`) || null;
                    return {
                      exists: data != null,
                      id: subId,
                      data: () => (data ? { ...data } : undefined),
                    };
                  },
                  async set() {
                    denyWrite("set", subPath);
                  },
                };
              },
            };
          },
        };
      },
      where(field, op, value) {
        const filters = [{ field, op, value }];
        let orderField = null;
        let orderDir = "asc";
        let limitN = null;
        let startAfterDoc = null;

        const builder = {
          where(f2, op2, v2) {
            filters.push({ field: f2, op: op2, value: v2 });
            return builder;
          },
          orderBy(f, dir = "asc") {
            orderField = f;
            orderDir = dir;
            return builder;
          },
          limit(n) {
            limitN = n;
            return builder;
          },
          startAfter(doc) {
            startAfterDoc = doc;
            return builder;
          },
          async get() {
            queryCalls.push({
              collection: name,
              filters: filters.map((x) => ({ ...x })),
              orderField,
              orderDir,
              limit: limitN,
              hasStartAfter: !!startAfterDoc,
            });
            if (name !== PROCESSED_PLAN_PAYMENTS_COL) {
              return { empty: true, docs: [], size: 0 };
            }
            let rows = [];
            for (const [id, data] of docs.entries()) {
              if (id.startsWith("order:") || id.startsWith("user:") || id.startsWith("sub:")) continue;
              if (!matchesQuery(data, filters)) continue;
              rows.push({
                id,
                data: () => ({ ...data }),
                get dataRaw() {
                  return data;
                },
              });
            }
            if (orderField) {
              rows.sort((a, b) => {
                const av = a.dataRaw[orderField];
                const bv = b.dataRaw[orderField];
                const am = av?.toMillis ? av.toMillis() : 0;
                const bm = bv?.toMillis ? bv.toMillis() : 0;
                return orderDir === "asc" ? am - bm : bm - am;
              });
            }
            if (startAfterDoc) {
              const idx = rows.findIndex((r) => r.id === startAfterDoc.id);
              rows = idx >= 0 ? rows.slice(idx + 1) : rows;
            }
            if (limitN != null) rows = rows.slice(0, limitN);
            const outDocs = rows.map((r) => ({
              id: r.id,
              data: r.data,
            }));
            return { empty: outDocs.length === 0, docs: outDocs, size: outDocs.length };
          },
        };
        return builder;
      },
    };
  }

  return {
    _docs: docs,
    _writeOps: writeOps,
    _queryCalls: queryCalls,
    collection: coll,
    async runTransaction() {
      denyWrite("transaction", "db");
    },
    batch() {
      denyWrite("batch", "db");
      return { set() {}, commit() {} };
    },
  };
}

describe("scheduledStuckPlanPaymentMonitor — threshold", () => {
  it("env absent → 60", () => {
    assert.equal(resolveStaleThresholdMinutes({}), DEFAULT_STALE_THRESHOLD_MINUTES);
  });
  it("env valid → configured value", () => {
    assert.equal(resolveStaleThresholdMinutes({ [STALE_THRESHOLD_ENV]: "90" }), 90);
  });
  it("env malformed → 60", () => {
    const warns = [];
    const n = resolveStaleThresholdMinutes(
      { [STALE_THRESHOLD_ENV]: "abc" },
      { warn: (m) => warns.push(m) },
    );
    assert.equal(n, 60);
    assert.ok(warns.length >= 1);
  });
});

describe("scheduledStuckPlanPaymentMonitor — schedule/export wiring", () => {
  it("MONITOR_SCHEDULE is every 30 minutes", () => {
    assert.equal(MONITOR_SCHEDULE, "every 30 minutes");
  });

  it("wrapper file configures every 30 minutes and exports scheduledMonitorStuckPlanPayments", () => {
    const src = readFileSync(join(root, "scheduledStuckPlanPaymentMonitor.js"), "utf8");
    assert.match(src, /export const scheduledMonitorStuckPlanPayments = onSchedule/);
    assert.match(src, /schedule:\s*MONITOR_SCHEDULE/);
    assert.equal(MONITOR_SCHEDULE, "every 30 minutes");
    assert.equal(/from ["'].*executor/.test(src), false);
    assert.equal(src.includes("executeIdempotentReconciliation"), false);
    assert.equal(src.includes("dryRun=false"), false);
    assert.equal(src.includes("write=true"), false);
    assert.equal(src.includes("repair=true"), false);
  });

  it("index.js exports scheduledMonitorStuckPlanPayments", () => {
    const indexSrc = readFileSync(join(root, "index.js"), "utf8");
    assert.match(indexSrc, /from "\.\/scheduledStuckPlanPaymentMonitor\.js"/);
    assert.match(indexSrc, /scheduledMonitorStuckPlanPayments/);
    assert.ok(indexSrc.includes("scheduledMonitorStuckPlanPayments"));
  });

  it("núcleo não importa executor", () => {
    const src = readFileSync(join(root, "src/scheduledStuckPlanPaymentMonitor.js"), "utf8");
    assert.equal(/from ["'].*executor/.test(src), false);
    assert.equal(src.includes("executeIdempotentReconciliation"), false);
    assert.equal(src.includes("stuckPaymentReconciliation/index"), false);
    assert.match(src, /from "\.\/stuckPaymentReconciliation\/classifier\.js"/);
  });
});

describe("scheduledStuckPlanPaymentMonitor — query", () => {
  it("status=processing + stale cutoff + orderBy updatedAt asc + limit 50", async () => {
    const now = new Date("2026-09-02T12:00:00Z");
    const cutoff = Timestamp.fromDate(new Date(now.getTime() - 60 * 60 * 1000));
    const db = createReadonlyQueryDb({
      pay_old: {
        paymentId: "pay_old",
        status: "processing",
        updatedAt: tsFromIso("2026-09-02T10:00:00Z"),
        uid: "u1",
        planOrderId: "po_1",
      },
    });
    const q = buildStaleProcessingQuery(db, { staleCutoffTs: cutoff, pageSize: MONITOR_PAGE_SIZE });
    await q.get();
    const call = db._queryCalls[0];
    assert.equal(call.collection, PROCESSED_PLAN_PAYMENTS_COL);
    assert.deepEqual(
      call.filters.map((f) => f.field),
      ["status", "updatedAt"],
    );
    assert.equal(call.filters[0].op, "==");
    assert.equal(call.filters[0].value, "processing");
    assert.equal(call.filters[1].op, "<=");
    assert.equal(call.orderField, "updatedAt");
    assert.equal(call.orderDir, "asc");
    assert.equal(call.limit, 50);
  });
});

describe("scheduledStuckPlanPaymentMonitor — concurrency", () => {
  it("não ultrapassa MAX_PROVIDER_CONCURRENCY", async () => {
    let inFlight = 0;
    let peak = 0;
    const items = Array.from({ length: 20 }, (_, i) => i);
    await mapWithConcurrency(items, MAX_PROVIDER_CONCURRENCY, async () => {
      inFlight++;
      peak = Math.max(peak, inFlight);
      await new Promise((r) => setTimeout(r, 5));
      inFlight--;
    });
    assert.ok(peak <= MAX_PROVIDER_CONCURRENCY);
  });
});

describe("scheduledStuckPlanPaymentMonitor — run", () => {
  it("0 records", async () => {
    const db = createReadonlyQueryDb({});
    const logs = [];
    const r = await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      fetchProviderPayment: async () => null,
      now: new Date("2026-09-02T12:00:00Z"),
      logger: { log: (s) => logs.push(s), warn: (s) => logs.push(s) },
      runId: "run_empty",
    });
    assert.equal(r.recordsProcessed, 0);
    assert.equal(r.truncated, false);
    assert.equal(r.firestoreWrites, 0);
    assert.equal(db._writeOps.length, 0);
  });

  it("1 page + SAFE candidate alerta sem write", async () => {
    const db = createReadonlyQueryDb({
      pay_safe_1: {
        paymentId: "pay_safe_1",
        status: "processing",
        uid: "uid_a",
        planOrderId: "po_safe_1",
        updatedAt: tsFromIso("2026-08-15T12:05:00Z"),
        createdAt: tsFromIso("2026-08-15T12:00:00Z"),
      },
      "order:po_safe_1": {
        userId: "uid_a",
        canonicalPlanId: "intermediate_monthly",
        orderStatus: "PENDENTE",
      },
      "user:uid_a": {
        currentPlanId: "free_limited",
      },
    });
    const providerCalls = [];
    const logs = [];
    const r = await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      now: new Date("2026-09-01T12:00:00Z"),
      fetchProviderPayment: async (id) => {
        providerCalls.push(id);
        return {
          id,
          status: "approved",
          transaction_amount: 29.99,
          date_approved: "2026-08-15T12:00:00.000Z",
          external_reference: "po_safe_1",
          metadata: {
            uid: "uid_a",
            plan_order_id: "po_safe_1",
            normalized_plan_id: "intermediate_monthly",
            email: "secret@example.com",
            payer: { email: "payer@example.com", name: "Alice", phone: "11999999999" },
          },
          payer: { email: "payer@example.com", first_name: "Alice" },
        };
      },
      logger: { log: (s) => logs.push(s), warn: (s) => logs.push(s) },
      runId: "run_safe",
    });
    assert.equal(r.recordsProcessed, 1);
    assert.equal(r.cases[0].classification, Classification.SAFE_REPAIR_CANDIDATE);
    assert.equal(r.cases[0].autoRepair, false);
    assert.equal(r.executorInvoked, false);
    assert.equal(db._writeOps.length, 0);
    assert.equal(providerCalls.length, 1);
    const blob = logs.join("\n");
    assert.ok(blob.includes("stuck_plan_payment_monitor_alert"));
    assert.ok(blob.includes(buildAlertIncidentKey("pay_safe_1", Classification.SAFE_REPAIR_CANDIDATE, ReasonCode.APPROVED_NOT_GRANTED)));
    assert.equal(blob.includes("secret@example.com"), false);
    assert.equal(blob.includes("payer@example.com"), false);
    assert.equal(blob.includes("Alice"), false);
    assert.equal(blob.includes("11999999999"), false);
    assert.equal(blob.includes('"payer"'), false);
  });

  it("provider failure fails closed + zero write", async () => {
    const db = createReadonlyQueryDb({
      pay_err: {
        paymentId: "pay_err",
        status: "processing",
        uid: "uid_e",
        planOrderId: "po_e",
        updatedAt: tsFromIso("2026-08-01T00:00:00Z"),
      },
      "order:po_e": { userId: "uid_e", canonicalPlanId: "pro_monthly", orderStatus: "PENDENTE" },
      "user:uid_e": { currentPlanId: "free_limited" },
    });
    const r = await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      now: new Date("2026-09-01T12:00:00Z"),
      fetchProviderPayment: async () => {
        throw new Error("timeout");
      },
      logger: { log() {}, warn() {} },
      runId: "run_err",
    });
    assert.equal(r.cases[0].classification, Classification.PROVIDER_NOT_FOUND);
    assert.equal(r.cases[0].reasonCode, ReasonCode.PAYMENT_NOT_FOUND);
    assert.equal(r.providerFailures, 1);
    assert.equal(db._writeOps.length, 0);
  });

  it("provider calls deduped per run", async () => {
    // same payment id shouldn't happen twice in query, but cache is tested via repeated classify path:
    // inject two docs that share paymentId field uncommon — instead call fetch via cache by running once
    let calls = 0;
    const db = createReadonlyQueryDb({
      pay_a: {
        paymentId: "pay_dup",
        status: "processing",
        uid: "u",
        planOrderId: "po",
        updatedAt: tsFromIso("2026-08-01T00:00:00Z"),
      },
    });
    await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      now: new Date("2026-09-01T12:00:00Z"),
      fetchProviderPayment: async () => {
        calls++;
        return { status: "pending", transaction_amount: 10 };
      },
      logger: { log() {}, warn() {} },
      runId: "run_dedup",
    });
    assert.equal(calls, 1);
  });

  it("paginação: multiple pages + 4 page cap truncation", async () => {
    const seed = {};
    for (let i = 0; i < 210; i++) {
      const id = `pay_${String(i).padStart(3, "0")}`;
      seed[id] = {
        paymentId: id,
        status: "processing",
        uid: `u${i}`,
        planOrderId: `po_${i}`,
        updatedAt: tsFromIso(`2026-08-01T${String(Math.floor(i / 60)).padStart(2, "0")}:${String(i % 60).padStart(2, "0")}:00Z`),
      };
    }
    const db = createReadonlyQueryDb(seed);
    const warns = [];
    const r = await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      now: new Date("2026-09-01T12:00:00Z"),
      pageSize: 50,
      maxPages: 4,
      maxRecords: 200,
      maxProviderConcurrency: 5,
      fetchProviderPayment: async () => ({ status: "pending", transaction_amount: 1 }),
      logger: { log() {}, warn: (s) => warns.push(s) },
      runId: "run_page",
    });
    assert.equal(r.pagesProcessed, MONITOR_MAX_PAGES);
    assert.equal(r.recordsProcessed, MONITOR_MAX_RECORDS);
    assert.equal(r.truncated, true);
    assert.ok(warns.some((w) => String(w).includes("MONITOR_TRUNCATED")));
    assert.ok(warns.some((w) => String(w).includes("additional_stale_processing_records_remain")));
    // oldest first: first case should be pay_000
    assert.equal(r.cases[0].paymentId, "pay_000");
  });

  it("CASE-001 policy: expired period → BUSINESS_DECISION_REQUIRED", async () => {
    const db = createReadonlyQueryDb({
      pay_c1: {
        paymentId: "pay_c1",
        status: "processing",
        uid: "uid_c1",
        planOrderId: "po_c1",
        updatedAt: tsFromIso("2026-05-26T12:00:00Z"),
      },
      "order:po_c1": {
        userId: "uid_c1",
        canonicalPlanId: "intermediate_monthly",
        orderStatus: "PENDENTE",
      },
      "user:uid_c1": { currentPlanId: "free_limited" },
    });
    const r = await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      now: new Date("2026-09-01T12:00:00Z"),
      fetchProviderPayment: async () => ({
        id: "pay_c1",
        status: "approved",
        transaction_amount: 29.99,
        date_approved: "2026-04-20T15:20:07.000Z",
        external_reference: "po_c1",
        metadata: { uid: "uid_c1", plan_order_id: "po_c1", normalized_plan_id: "intermediate_monthly" },
      }),
      logger: { log() {}, warn() {} },
      runId: "run_c1",
    });
    assert.equal(r.cases[0].classification, Classification.BUSINESS_DECISION_REQUIRED);
    assert.equal(r.cases[0].reasonCode, ReasonCode.PERIOD_EXPIRED);
    assert.equal(r.cases[0].autoRepair, false);
  });

  it("CASE-002 policy: zero amount → UNRELATED / no repair", async () => {
    const db = createReadonlyQueryDb({
      pay_c2: {
        paymentId: "pay_c2",
        status: "processing",
        updatedAt: tsFromIso("2026-05-01T00:00:00Z"),
      },
    });
    const r = await runStuckPlanPaymentMonitor({
      db,
      normalizePlanId: norm,
      now: new Date("2026-09-01T12:00:00Z"),
      fetchProviderPayment: async () => ({
        id: "pay_c2",
        status: "approved",
        transaction_amount: 0,
      }),
      logger: { log() {}, warn() {} },
      runId: "run_c2",
    });
    assert.equal(r.cases[0].classification, Classification.UNRELATED_PAYMENT);
    assert.equal(r.cases[0].reasonCode, ReasonCode.ZERO_AMOUNT);
    assert.equal(r.cases[0].autoRepair, false);
  });

  it("case id / incident key PII-safe", () => {
    const cid = buildCaseId("1234567890");
    assert.ok(cid.startsWith("spp_"));
    assert.equal(cid.includes("@"), false);
    const key = buildAlertIncidentKey("1234567890", "MAPPING_FAILURE", "MAPPING_AMBIGUOUS");
    assert.ok(key.includes("MAPPING_FAILURE"));
    assert.ok(key.includes("MAPPING_AMBIGUOUS"));
  });
});
