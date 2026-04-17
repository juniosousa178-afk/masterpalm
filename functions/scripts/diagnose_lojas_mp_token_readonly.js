/**
 * Diagnóstico READ-ONLY: quais lojas falhariam / avisariam com a política MP endurecida.
 *
 * Uso (na pasta functions/):
 *   node ./scripts/diagnose_lojas_mp_token_readonly.js
 *   node ./scripts/diagnose_lojas_mp_token_readonly.js --summary
 *   COLLECTION_LOJAS=outras node ./scripts/diagnose_lojas_mp_token_readonly.js
 *
 * Credenciais: masterpalm-service-account.json ou GOOGLE_APPLICATION_CREDENTIALS.
 * Não escreve no Firestore. Não imprime tokens — apenas tokenLen e flags.
 */

import { createRequire } from "module";
import dotenv from "dotenv";
import admin from "firebase-admin";
import { classifyLojaMpPaymentsData } from "../src/mpLojaPaymentsDiagnostics.js";

dotenv.config();
const require = createRequire(import.meta.url);

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";
const summaryOnly = process.argv.includes("--summary");

if (!admin.apps.length) {
  let options = {};
  try {
    const sa = require("../masterpalm-service-account.json");
    options = {
      credential: admin.credential.cert(sa),
      projectId: process.env.PROJECT_ID || "masterpalm-58c46",
    };
    console.error("[diagnose_mp] Usando masterpalm-service-account.json.");
  } catch (_) {
    options = {
      credential: admin.credential.applicationDefault(),
      projectId: process.env.PROJECT_ID || "masterpalm-58c46",
    };
    console.error("[diagnose_mp] Usando application default credentials.");
  }
  admin.initializeApp(options);
}

const db = admin.firestore();

function lojaDisplayName(lojaData) {
  if (!lojaData || typeof lojaData !== "object") return "";
  return (
    String(lojaData.nome || lojaData.name || lojaData.slug || lojaData.titulo || "").trim() || ""
  );
}

async function main() {
  const lojasSnap = await db.collection(COLLECTION_LOJAS).get();
  const counts = {};
  let wouldFailCount = 0;
  const rows = [];

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const lojaData = lojaDoc.data() || {};
    const nome = lojaDisplayName(lojaData);

    const payRef = db.collection(COLLECTION_LOJAS).doc(lojaId).collection("config").doc("payments");
    const paySnap = await payRef.get();

    let row;
    if (!paySnap.exists) {
      row = {
        lojaId,
        nome,
        paymentsDocExists: false,
        status: "no_config_payments_document",
        wouldFailMpLojaTokenRequired: true,
        tokenLen: 0,
        connected: false,
        hasEmail: false,
        hasUserId: false,
        hasNickname: false,
        publicKeyShape: "missing",
        motivoPrincipal: "documento_config_payments_ausente",
        suggestedAction: "Publicar ou criar config/payments para a loja.",
      };
    } else {
      const classified = classifyLojaMpPaymentsData(paySnap.data() || {});
      row = {
        lojaId,
        nome,
        paymentsDocExists: true,
        ...classified,
      };
    }

    if (row.wouldFailMpLojaTokenRequired) wouldFailCount += 1;
    counts[row.status] = (counts[row.status] || 0) + 1;
    rows.push(row);
  }

  if (summaryOnly) {
    console.log(
      JSON.stringify(
        {
          event: "mp_loja_token_diagnosis_summary",
          collection: COLLECTION_LOJAS,
          totalLojas: lojasSnap.size,
          wouldFailMpLojaTokenRequiredCount: wouldFailCount,
          byStatus: counts,
        },
        null,
        2,
      ),
    );
    return;
  }

  for (const row of rows) {
    console.log(JSON.stringify(row));
  }

  console.error(
    JSON.stringify({
      event: "mp_loja_token_diagnosis_done",
      totalLojas: rows.length,
      wouldFailMpLojaTokenRequiredCount: wouldFailCount,
      byStatus: counts,
    }),
  );
}

main().catch((e) => {
  console.error("[diagnose_mp] erro:", e);
  process.exit(1);
});
