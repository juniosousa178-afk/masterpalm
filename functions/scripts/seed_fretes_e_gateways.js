// scripts/seed_fretes_e_gateways.js
// Atualiza TODAS as lojas com configs padrão de:
// - Pagamentos (MP, PagSeguro, Ton, InfinitePay)
// - Fretes (Correios, Melhor Envio, Frenet)
// - Marketplaces (TikTok Shop, Shopee, Mercado Livre)
//
// RODAR:  node ./scripts/seed_fretes_e_gateways.js

import admin from "firebase-admin";
import * as dotenv from "dotenv";
import serviceAccount from "../masterpalm-service-account.json" with { type: "json" };

dotenv.config();

// Usa a COLLECTION_LOJAS se estiver definida nas env, senão "lojas"
const COLLECTION_LOJAS = process.env.COLLECTION_LOJAS || "lojas";

// Inicializa Admin SDK usando a chave de Service Account
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();


async function seedLoja(lojaId) {
  console.log(`\n➡ Atualizando loja: ${lojaId}`);

  const lojaRef = db.collection(COLLECTION_LOJAS).doc(String(lojaId));

  // -----------------------------
  // CONFIG/PAYMENTS
  // -----------------------------
  const paymentsRef = lojaRef.collection("config").doc("payments");
  const paymentsSnap = await paymentsRef.get();
  const paymentsOld = paymentsSnap.exists ? paymentsSnap.data() || {} : {};

  const paymentsNew = {
    // gateway padrão (você pode mudar depois na UI da loja)
    gateway_default: paymentsOld.gateway_default || "mercadopago",

    // MERCADO PAGO (já usado hoje)
    mp_access_token: paymentsOld.mp_access_token || null,
    mp_public_key: paymentsOld.mp_public_key || null,

    // PAGSEGURO
    pagseguro_token: paymentsOld.pagseguro_token || null,
    pagseguro_seller_id: paymentsOld.pagseguro_seller_id || null,

    // TON (Stone/Ton)
    ton_token: paymentsOld.ton_token || null,
    ton_pos_id: paymentsOld.ton_pos_id || null,

    // INFINITEPAY
    infinitepay_token: paymentsOld.infinitepay_token || null,
    infinitepay_account_id: paymentsOld.infinitepay_account_id || null,
  };

  await paymentsRef.set(paymentsNew, { merge: true });
  console.log("  ✔ config/payments atualizado");

  // -----------------------------
  // CONFIG/SHIPPING (fretes)
  // -----------------------------
  const shippingRef = lojaRef.collection("config").doc("shipping");
  const shippingSnap = await shippingRef.get();
  const shippingOld = shippingSnap.exists ? shippingSnap.data() || {} : {};

  const shippingNew = {
    // CEP padrão da loja (você ajusta depois no painel)
    cep_origem: shippingOld.cep_origem || null,

    // Correios
    correios_enabled:
      typeof shippingOld.correios_enabled === "boolean"
        ? shippingOld.correios_enabled
        : true,
    // Se tiver contrato próprio, você adiciona depois:
    correios_codigo_adm: shippingOld.correios_codigo_adm || null,
    correios_senha: shippingOld.correios_senha || null,

    // Melhor Envio
    melhorenvio_enabled:
      typeof shippingOld.melhorenvio_enabled === "boolean"
        ? shippingOld.melhorenvio_enabled
        : false,
    melhorenvio_token: shippingOld.melhorenvio_token || null,
    melhorenvio_user_id: shippingOld.melhorenvio_user_id || null,

    // Frenet
    frenet_enabled:
      typeof shippingOld.frenet_enabled === "boolean"
        ? shippingOld.frenet_enabled
        : false,
    frenet_token: shippingOld.frenet_token || null,
    frenet_store_id: shippingOld.frenet_store_id || null,

    // Regras simples (pra usar depois no front)
    free_shipping_min_value:
      typeof shippingOld.free_shipping_min_value === "number"
        ? shippingOld.free_shipping_min_value
        : null,
    handling_fee:
      typeof shippingOld.handling_fee === "number"
        ? shippingOld.handling_fee
        : 0,
  };

  await shippingRef.set(shippingNew, { merge: true });
  console.log("  ✔ config/shipping (fretes) atualizado");

  // -----------------------------
  // CONFIG/MARKETPLACES
  // -----------------------------
  const marketplacesRef = lojaRef.collection("config").doc("marketplaces");
  const marketplacesSnap = await marketplacesRef.get();
  const marketplacesOld = marketplacesSnap.exists ? marketplacesSnap.data() || {} : {};

  const marketplacesNew = {
    // TikTok Shop
    tiktok_enabled:
      typeof marketplacesOld.tiktok_enabled === "boolean"
        ? marketplacesOld.tiktok_enabled
        : false,
    tiktok_app_key: marketplacesOld.tiktok_app_key || null,
    tiktok_app_secret: marketplacesOld.tiktok_app_secret || null,
    tiktok_shop_id: marketplacesOld.tiktok_shop_id || null,

    // Shopee
    shopee_enabled:
      typeof marketplacesOld.shopee_enabled === "boolean"
        ? marketplacesOld.shopee_enabled
        : false,
    shopee_partner_id: marketplacesOld.shopee_partner_id || null,
    shopee_partner_key: marketplacesOld.shopee_partner_key || null,
    shopee_shop_id: marketplacesOld.shopee_shop_id || null,

    // Mercado Livre
    ml_enabled:
      typeof marketplacesOld.ml_enabled === "boolean"
        ? marketplacesOld.ml_enabled
        : false,
    ml_app_id: marketplacesOld.ml_app_id || null,
    ml_client_secret: marketplacesOld.ml_client_secret || null,
    ml_seller_id: marketplacesOld.ml_seller_id || null,
  };

  await marketplacesRef.set(marketplacesNew, { merge: true });
  console.log("  ✔ config/marketplaces atualizado");

  // -----------------------------
  // SETTINGS/GENERAL (garantia de campos base)
  // -----------------------------
  const generalRef = lojaRef.collection("settings").doc("general");
  const generalSnap = await generalRef.get();
  const generalOld = generalSnap.exists ? generalSnap.data() || {} : {};

  const generalNew = {
    catalog: {
      public:
        typeof generalOld.catalog?.public === "boolean"
          ? generalOld.catalog.public
          : true,
      createdAt: generalOld.catalog?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    },
    theme: generalOld.theme || {
      bg: "#FFFFFF",
      primary: "#111111",
      text: "#111111",
    },
    // só garante que existe a chave, sem sobrescrever número se já tiver
    whatsappE164: generalOld.whatsappE164 || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await generalRef.set(generalNew, { merge: true });
  console.log("  ✔ settings/general atualizado");
}

async function run() {
  console.log("== SEED FRETES + GATEWAYS + MARKETPLACES ==");

  const lojasSnap = await db.collection(COLLECTION_LOJAS).get();
  console.log(`Encontradas ${lojasSnap.size} lojas em "${COLLECTION_LOJAS}"`);

  if (lojasSnap.empty) {
    console.log("Nenhuma loja encontrada. Nada a fazer.");
    return;
  }

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    try {
      await seedLoja(lojaId);
    } catch (e) {
      console.error(`  ⚠ Erro ao atualizar loja ${lojaId}:`, e);
    }
  }

  console.log("\n✅ Seed concluído.");
}

run()
  .then(() => {
    console.log("Fim.");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Erro geral no seed:", err);
    process.exit(1);
  });
