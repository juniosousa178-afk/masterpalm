/**
 * Backfill: lojas/{lojaId}/config/payments → payments_public (sem segredos).
 * Uso: node ./scripts/backfill_payments_public.js [--dry-run]
 * Credenciais: masterpalm-service-account.json ou GOOGLE_APPLICATION_CREDENTIALS (igual aos outros scripts).
 */

import { createRequire } from "module";
import dotenv from "dotenv";
import admin from "firebase-admin";
import { stripPaymentsSecretsForPublic } from "../src/paymentsPublicStrip.js";

dotenv.config();
const require = createRequire(import.meta.url);

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const dryRun = process.argv.includes("--dry-run");

if (!admin.apps.length) {
  let options = {};
  try {
    const sa = require("../masterpalm-service-account.json");
    options = {
      credential: admin.credential.cert(sa),
      projectId: process.env.PROJECT_ID || "masterpalm-58c46",
    };
    console.log("Usando masterpalm-service-account.json.");
  } catch (_) {
    options = {
      credential: admin.credential.applicationDefault(),
      projectId: process.env.PROJECT_ID || "masterpalm-58c46",
    };
    console.log("Usando application default credentials.");
  }
  admin.initializeApp(options);
}

const db = admin.firestore();

async function main() {
  const lojasSnap = await db.collection(COLLECTION_LOJAS).get();
  let processed = 0;
  let skippedNoPayments = 0;
  const missingBefore = [];

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const payRef = db.collection(COLLECTION_LOJAS).doc(lojaId).collection("config").doc("payments");
    const pubRef = db.collection(COLLECTION_LOJAS).doc(lojaId).collection("config").doc("payments_public");
    const [paySnap, pubSnap] = await Promise.all([payRef.get(), pubRef.get()]);
    if (!paySnap.exists) {
      skippedNoPayments++;
      continue;
    }
    const raw = paySnap.data() || {};
    if (!pubSnap.exists) {
      missingBefore.push(lojaId);
      console.warn(
        JSON.stringify({
          event: "payments_public_missing_before_backfill",
          lojaId,
        }),
      );
    }
    const stripped = stripPaymentsSecretsForPublic(raw);
    if (dryRun) {
      console.log("[dry-run] escreveria payments_public", lojaId);
      processed++;
      continue;
    }
    await pubRef.set(
      { ...stripped, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: false },
    );
    processed++;
  }

  console.log(
    JSON.stringify({
      event: "backfill_payments_public_done",
      dryRun,
      lojasComPaymentsDoc: processed,
      lojasSemPaymentsDoc: skippedNoPayments,
      lojasComPublicAusenteAntes: missingBefore.length,
    }),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
