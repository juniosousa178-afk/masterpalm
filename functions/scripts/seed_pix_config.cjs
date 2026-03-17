/**
 * Atualiza automaticamente o PIX no Firestore
 * Cole este arquivo em: functions/scripts/seed_pix_config.cjs
 * Execute com:  node seed_pix_config.cjs
 */

// ======================================================================
// 1. IMPORTAÇÕES
// ======================================================================
const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

// ======================================================================
// 2. LOCAL DO ARQUIVO DE CREDENCIAIS (serviceAccountKey.json)
// ======================================================================
// ⚠️ IMPORTANTE: este arquivo deve estar em:
// functions/serviceAccountKey.json

const serviceAccountPath = path.join(__dirname, "..", "serviceAccountKey.json");

if (!fs.existsSync(serviceAccountPath)) {
  console.error("❌ ERRO: Arquivo serviceAccountKey.json NÃO encontrado em:");
  console.error(serviceAccountPath);
  process.exit(1);
}

// Inicializa Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

// Firestore
const db = admin.firestore();

// ======================================================================
// 3. CONFIGURAÇÕES QUE SERÃO SALVAS
// ======================================================================
// Ajuste AQUI o que quiser atualizar
const lojaId = "masterpalm"; // 🔥 altere aqui sua loja
const pixKey = "00020126360014BR.GOV.BCB.PIX0114+55419999999990203BR403105204000530398654051.005802BR5925MASTER PALM STORE6009SAO PAULO62160512PIX12345678906304ABCD"; // chave PIX (string)
const pixType = "qrcode"; // OU "chave"
const pixIsEnabled = true;

// ======================================================================
// 4. FUNÇÃO PRINCIPAL
// ======================================================================
async function atualizarPix() {
  try {
    console.log("🚀 Iniciando atualização do PIX no Firestore...");

    const docRef = db
      .collection("lojas")
      .doc(lojaId)
      .collection("config")
      .doc("payments");

    await docRef.set(
      {
        gateway_default: "pix",

        pix: {
          enabled: pixIsEnabled,
          type: pixType, // "qrcode" ou "chave"
          qrcode: pixKey, // se for qrcode
          chave: pixKey, // se for chave direta
          updatedAt: new Date().toISOString(),
        },

        // preserva os outros gateways sem apagar
        mp: admin.firestore.FieldValue.delete(),
        pagseguro: admin.firestore.FieldValue.delete(),
        ton: admin.firestore.FieldValue.delete(),
        infinitepay: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );

    console.log("✅ PIX atualizado com sucesso!");
    process.exit(0);
  } catch (err) {
    console.error("❌ Erro ao atualizar PIX:", err);
    process.exit(1);
  }
}

// Executa
atualizarPix();
