// functions/scripts/fix_payments_gateways.js
// Corrige o documento config/payments de todas as lojas
// - Cria estrutura:
//   mp.publicKey, mp.token
//   pagseguro.publicKey, pagseguro.token
//   ton.clientId, ton.clientSecret
//   infinitepay.merchantId, infinitepay.apiKey
// - Remove campos antigos planos (mp_token, pagseguro_client_id, etc.)

import { createRequire } from "module";
import dotenv from "dotenv";
import admin from "firebase-admin";

dotenv.config();
const require = createRequire(import.meta.url);

// ---------------------------------------------------------------------
// Inicializar Firebase Admin
// ---------------------------------------------------------------------
if (!admin.apps.length) {
  let options = {};
  try {
    // tenta usar o service account local
    const sa = require("../masterpalm-service-account.json");
    options = {
      credential: admin.credential.cert(sa),
      projectId: process.env.PROJECT_ID || "masterpalm-58c46",
    };
    console.log("🔥 Usando masterpalm-service-account.json para autenticar.");
  } catch (e) {
    console.warn(
      "⚠️ masterpalm-service-account.json não encontrado. Tentando credencial padrão (GOOGLE_APPLICATION_CREDENTIALS)..."
    );
    options = {
      credential: admin.credential.applicationDefault(),
      projectId: process.env.PROJECT_ID || "masterpalm-58c46",
    };
  }
  admin.initializeApp(options);
}

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";

// ---------------------------------------------------------------------
// Função que corrige UMA loja
// ---------------------------------------------------------------------
async function fixLojaPayments(lojaId) {
  const paymentsRef = db
    .collection(COLLECTION_LOJAS)
    .doc(lojaId)
    .collection("config")
    .doc("payments");

  const snap = await paymentsRef.get();
  const data = snap.exists ? snap.data() || {} : {};

  console.log(`\n✅ Corrigindo loja: ${lojaId}`);

  // --- Leitura dos campos antigos/atuais ---
  const mpOld = data.mp || {};
  const pagOld = data.pagseguro || {};
  const tonOld = data.ton || {};
  const infOld = data.infinitepay || {};

  // Monta objeto final, preservando o que já existe
  const mp = {
    publicKey:
      mpOld.publicKey ??
      data.mp_publicKey ??
      null,
    token:
      mpOld.token ??
      data.mp_token ??
      null,
  };

  const pagseguro = {
    publicKey:
      pagOld.publicKey ??
      data.pagseguro_publicKey ??
      null,
    token:
      pagOld.token ??
      data.pagseguro_token ??
      null,
  };

  const ton = {
    clientId:
      tonOld.clientId ??
      data.ton_client_id ??
      null,
    clientSecret:
      tonOld.clientSecret ??
      data.ton_client_secret ??
      null,
  };

  const infinitepay = {
    merchantId:
      infOld.merchantId ??
      data.infinitepay_account_id ??
      null,
    apiKey:
      infOld.apiKey ??
      data.infinitepay_token ??
      null,
  };

  // Campos antigos que queremos remover
  const deletes = {
    mp_publicKey: FieldValue.delete(),
    mp_token: FieldValue.delete(),
    pagseguro_client_id: FieldValue.delete(),
    pagseguro_client_secret: FieldValue.delete(),
    pagseguro_publicKey: FieldValue.delete(),
    pagseguro_token: FieldValue.delete(),
    ton_client_id: FieldValue.delete(),
    ton_client_secret: FieldValue.delete(),
    ton_token: FieldValue.delete(),
    infinitepay_account_id: FieldValue.delete(),
    infinitepay_token: FieldValue.delete(),
  };

  const payload = {
    mp,
    pagseguro,
    ton,
    infinitepay,
    ...deletes,
    updatedAt: admin.firestore.Timestamp.now(),
  };

  await paymentsRef.set(payload, { merge: true });
  console.log(`   ✔ payments atualizado para loja ${lojaId}`);
}

// ---------------------------------------------------------------------
// MAIN
//   - se passar --loja=ID corrige só aquela
//   - senão, corrige todas as lojas da coleção
// ---------------------------------------------------------------------
async function main() {
  const argLoja = process.argv
    .find((a) => a.startsWith("--loja="))
    ?.split("=")[1];

  if (argLoja) {
    console.log(`🔎 Corrigindo apenas lojaId=${argLoja}`);
    await fixLojaPayments(argLoja);
    console.log("🏁 Concluído.");
    process.exit(0);
  }

  console.log("🔎 Buscando todas as lojas...");
  const lojasSnap = await db.collection(COLLECTION_LOJAS).get();
  if (lojasSnap.empty) {
    console.log("⚠️ Nenhuma loja encontrada em", COLLECTION_LOJAS);
    process.exit(0);
  }

  const total = lojasSnap.size;
  console.log(`Encontradas ${total} lojas. Corrigindo...`);

  let i = 0;
  for (const doc of lojasSnap.docs) {
    i++;
    const lojaId = doc.id;
    console.log(`\n[${i}/${total}] --------------------------`);
    await fixLojaPayments(lojaId);
  }

  console.log("\n🏁 Finalizado: todos os payments foram normalizados.");
  process.exit(0);
}

main().catch((err) => {
  console.error("❌ Erro geral no script:", err);
  process.exit(1);
});
