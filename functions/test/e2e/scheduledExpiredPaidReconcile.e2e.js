/**
 * E2E mínimo: Firestore Emulator + runScheduledReconcileBatch + computePlanState real.
 *
 * Pré-requisito (Firebase CLI atual): JDK 21 ou superior.
 * Se `firebase emulators:start` falhar com erro de Java, instale o JDK e reinicie o terminal.
 *
 * Ver: functions/test/e2e/README.md
 */

import net from "node:net";
import { describe, it, before, afterEach } from "node:test";
import assert from "node:assert/strict";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { runScheduledReconcileBatch } from "../../src/scheduledExpiredPaidReconcileBatch.js";

const PROJECT_ID = "demo-e2e-scheduled-plan";

/** UIDs criados no teste atual — removidos no afterEach para não contaminar o emulador. */
const uidsToCleanup = [];

function getDb() {
  if (!getApps().length) {
    initializeApp({ projectId: PROJECT_ID });
  }
  return getFirestore();
}

function pastDate() {
  return new Date("2020-06-01T12:00:00.000Z");
}

async function queryExpiredBatch(db, now) {
  const ts = Timestamp.fromDate(now);
  return db
    .collection("users")
    .where("currentPeriodEnd", "<", ts)
    .orderBy("currentPeriodEnd", "asc")
    .limit(50)
    .get();
}

/**
 * Restringe o snapshot ao(s) uid(s) do cenário para que os contadores do batch
 * reflitam só este documento (query real no emulador; lote passado ao batch = isolado).
 */
function snapshotForUids(snap, uids) {
  const allow = new Set(uids);
  const docs = snap.docs.filter((d) => allow.has(d.id));
  return { size: docs.length, docs };
}

/** Evita hang silencioso se o emulador não estiver escutando (prelude define FIRESTORE_EMULATOR_HOST). */
function assertFirestoreEmulatorReachable() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
  const parts = raw.split(":");
  const host = parts[0] || "127.0.0.1";
  const port = parseInt(parts[1] || "8080", 10);

  return new Promise((resolve, reject) => {
    const s = net.connect({ host, port }, () => {
      s.end();
      resolve(undefined);
    });
    s.setTimeout(4000, () => {
      s.destroy();
      reject(
        new Error(
          `Firestore Emulator não respondeu em ${host}:${port} (timeout). ` +
            `Suba o emulador na raiz do repositório: firebase emulators:start --only firestore. ` +
            `O Firebase CLI exige JDK 21+; em Windows: winget install EclipseAdoptium.Temurin.21.JDK`,
        ),
      );
    });
    s.on("error", (err) => {
      reject(
        new Error(
          `Sem Firestore Emulator em ${host}:${port}: ${err.message}. ` +
            `Instale JDK 21+ e rode: firebase emulators:start --only firestore (pasta do projeto com firebase.json). ` +
            `Depois, em outro terminal: cd functions && npm run test:e2e:only`,
        ),
      );
    });
  });
}

describe("E2E scheduled reconcile (Firestore emulator + computePlanState real)", () => {
  let db;

  before(async () => {
    assert.ok(
      process.env.FIRESTORE_EMULATOR_HOST,
      "Defina FIRESTORE_EMULATOR_HOST ou use: node --import ./test/e2e/prelude-firestore-emulator.mjs",
    );
    await assertFirestoreEmulatorReachable();
    db = getDb();
  });

  afterEach(async () => {
    for (const uid of uidsToCleanup) {
      try {
        await db.collection("users").doc(uid).delete();
      } catch (_) {
        /* ignore */
      }
    }
    uidsToCleanup.length = 0;
  });

  it("1) pago vencido elegível → free_limited + cancelAtPeriodEnd false", async () => {
    const uid = `e2e_paid_${Date.now()}`;
    uidsToCleanup.push(uid);
    const email = "e2e-paid@test.local";
    const dbRef = db;

    await dbRef
      .collection("users")
      .doc(uid)
      .set({
        email,
        currentPlanId: "pro_monthly",
        status: "active",
        trialing: false,
        currentPeriodEnd: Timestamp.fromDate(pastDate()),
        trialUsed: true,
        cancelAtPeriodEnd: true,
      });

    const now = new Date();
    const snapFull = await queryExpiredBatch(dbRef, now);
    const snap = snapshotForUids(snapFull, [uid]);
    assert.equal(
      snap.docs.length,
      1,
      "o doc do cenário deve aparecer na query currentPeriodEnd < now",
    );

    const stats = await runScheduledReconcileBatch({ db: dbRef, now, snap });

    assert.equal(stats.queryBatchSize, 1);
    assert.equal(stats.evaluated, 1);
    assert.equal(stats.skippedNotPaidPlan, 0);
    assert.equal(stats.skippedProtected, 0);
    assert.equal(stats.reconcileRuns, 1);
    assert.equal(stats.downgradedToFreeLimited, 1);
    assert.equal(stats.failed, 0);

    const after = await dbRef.collection("users").doc(uid).get();
    const d = after.data();
    assert.equal(d.currentPlanId, "free_limited");
    assert.equal(d.cancelAtPeriodEnd, false);
    assert.equal(d.trialing, false);
  });

  it("2) manualOverride.enabled — sem downgrade para free_limited", async () => {
    const uid = `e2e_mo_${Date.now()}`;
    uidsToCleanup.push(uid);
    const email = "e2e-mo@test.local";
    const dbRef = db;

    await dbRef
      .collection("users")
      .doc(uid)
      .set({
        email,
        currentPlanId: "pro_monthly",
        status: "active",
        trialing: false,
        currentPeriodEnd: Timestamp.fromDate(pastDate()),
        trialUsed: true,
        manualOverride: { enabled: true, planId: "pro_monthly" },
      });

    const now = new Date();
    const snapFull = await queryExpiredBatch(dbRef, now);
    const snap = snapshotForUids(snapFull, [uid]);
    assert.equal(snap.docs.length, 1);

    const stats = await runScheduledReconcileBatch({ db: dbRef, now, snap });

    assert.equal(stats.queryBatchSize, 1);
    assert.equal(stats.evaluated, 1);
    assert.equal(stats.skippedNotPaidPlan, 0);
    assert.equal(stats.skippedProtected, 1);
    assert.equal(stats.reconcileRuns, 0);
    assert.equal(stats.downgradedToFreeLimited, 0);
    assert.equal(stats.failed, 0);

    const after = await dbRef.collection("users").doc(uid).get();
    const d = after.data();
    assert.equal(d.currentPlanId, "pro_monthly");
    assert.equal(d.manualOverride.enabled, true);
  });

  it("3) já free_limited com currentPeriodEnd legado no passado — estável", async () => {
    const uid = `e2e_fl_${Date.now()}`;
    uidsToCleanup.push(uid);
    const email = "e2e-fl@test.local";
    const dbRef = db;

    await dbRef
      .collection("users")
      .doc(uid)
      .set({
        email,
        currentPlanId: "free_limited",
        status: "active",
        trialing: false,
        currentPeriodEnd: Timestamp.fromDate(pastDate()),
        trialUsed: true,
      });

    const beforeSnap = await dbRef.collection("users").doc(uid).get();
    const beforeData = beforeSnap.data();

    const now = new Date();
    const snapFull = await queryExpiredBatch(dbRef, now);
    const snap = snapshotForUids(snapFull, [uid]);
    assert.equal(snap.docs.length, 1);

    const stats = await runScheduledReconcileBatch({ db: dbRef, now, snap });

    assert.equal(stats.queryBatchSize, 1);
    assert.equal(stats.evaluated, 1);
    assert.equal(stats.skippedNotPaidPlan, 1);
    assert.equal(stats.skippedProtected, 0);
    assert.equal(stats.reconcileRuns, 0);
    assert.equal(stats.downgradedToFreeLimited, 0);
    assert.equal(stats.failed, 0);

    const after = await dbRef.collection("users").doc(uid).get();
    const afterData = after.data();
    assert.equal(afterData.currentPlanId, "free_limited");
    assert.equal(afterData.trialUsed, beforeData.trialUsed);
  });
});
