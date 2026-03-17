// tools/bootstrap_firestore.js
//
// Script para atualizar/normalizar a estrutura do Firestore do MasterPalm
// SEM apagar nada. Ele apenas garante que:
//
//  - lojas/{lojaId} existe com campos mínimos
//  - lojas/{lojaId}/draft_config/config existe com todos os campos esperados
//  - lojas/{lojaId}/config/config é espelho do draft_config
//  - lojas/{lojaId}/settings/general existe com defaults
//
// Rode com:  node tools/bootstrap_firestore.js

const admin = require('firebase-admin');
const path = require('path');

// ===== 1) INICIALIZA FIREBASE ADMIN =====
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

// ===== 2) CONFIGURE AQUI QUAIS LOJAS VAI ATUALIZAR =====
// Pode ser ['minha-loja'] ou buscar automaticamente todas.
const LOJAS_FIXAS = ['minha-loja']; // <-- coloque os slugs das lojas que vc usa

async function getTodasLojas() {
  const snap = await db.collection('lojas').get();
  return snap.docs.map((d) => d.id);
}

// Defaults de cores
function defaultColors() {
  return {
    bg: 0xFF050816,       // fundo escuro
    card: 0xFF111827,     // card
    text: 0xFFF9FAFB,     // texto
    primary: 0xFF6366F1,  // roxinho
    btnText: 0xFFFFFFFF,  // texto do botão
  };
}

// Defaults de frete
function defaultFretes() {
  return [
    { nome: 'Retirada', valor: 0.0 },
    { nome: 'Entrega local', valor: 10.0 },
  ];
}

// Defaults de mídia
function defaultMedia(slug) {
  return {
    desktop: {
      logoUrl: '',
      logoW: 327,
      logoH: 105,
      bannerW: 1280,
      bannerH: 256,
      banners: [],
    },
    mobile: {
      logoUrl: '',
      logoW: 327,
      logoH: 105,
      bannerW: 562,
      bannerH: 300,
      banners: [],
    },
  };
}

// Defaults de rodapé
function defaultFooter() {
  return {
    links: {
      instagram: '',
      facebook: '',
      sobre: '',
      trocas: '',
      login: '',
    },
    empresa: {
      razao: '',
      cnpj: '',
    },
    payments: [], // visa, mastercard, pix...
  };
}

// Settings gerais
function defaultSettingsGeneral() {
  return {
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    public: true,
    theme: 'masterPadrao',
  };
}

// ===== 3) FUNÇÃO PRINCIPAL POR LOJA =====
async function ensureLojaStructure(lojaId) {
  console.log('\n=== Atualizando loja: ${lojaId} ===');

  const lojaRef = db.collection('lojas').doc(lojaId);
  const draftCfgRef = lojaRef.collection('draft_config').doc('config');
  const liveCfgRef = lojaRef.collection('config').doc('config');
  const settingsGeneralRef = lojaRef.collection('settings').doc('general');

  // -------- DOC RAIZ DA LOJA --------
  const lojaSnap = await lojaRef.get();
  const baseData = {
    slug: lojaId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!lojaSnap.exists) {
    console.log(' - Criando doc raiz da loja...');
    await lojaRef.set(baseData, { merge: true });
  } else {
    console.log(' - Loja já existe, fazendo merge...');
    await lojaRef.set(baseData, { merge: true });
  }

  // -------- DRAFT CONFIG (config de rascunho) --------
  const draftSnap = await draftCfgRef.get();
  let draftData = draftSnap.data() || {};

  const hasColors = !!draftData.colors;
  const hasMedia = !!draftData.media;
  const hasFretes = Array.isArray(draftData.fretes);
  const hasLinks = !!draftData.links;
  const hasEmpresa = !!draftData.empresa;

  const patch = {
    slug: lojaId,
    name: draftData.name || 'Minha Loja',
    whatsapp: draftData.whatsapp || '',
    whatsapp_vendedor: draftData.whatsapp_vendedor || draftData.whatsapp || '',
    pedido_link_base:
      draftData.pedido_link_base || 'https://mastepalm.com.br/pedido',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!hasColors) {
    console.log(' - Adicionando bloco "colors" padrão...');
    patch.colors = defaultColors();
  }
  if (!hasMedia) {
    console.log(' - Adicionando bloco "media" padrão...');
    patch.media = defaultMedia(lojaId);
  }
  if (!hasFretes) {
    console.log(' - Adicionando fretes padrão...');
    patch.fretes = defaultFretes();
  }
  if (!hasLinks || !hasEmpresa) {
    console.log(' - Adicionando rodapé padrão (links/empresa/payments)...');
    const footer = defaultFooter();
    patch.links = { ...(draftData.links || {}), ...footer.links };
    patch.empresa = { ...(draftData.empresa || {}), ...footer.empresa };
    patch.payments = draftData.payments || footer.payments;
  }

  await draftCfgRef.set(patch, { merge: true });
  console.log(' - draft_config/config atualizado.');

  // -------- LIVE CONFIG (espelho) --------
  const draftFinalSnap = await draftCfgRef.get();
  const draftFinalData = draftFinalSnap.data() || {};
  await liveCfgRef.set(draftFinalData, { merge: false });
  console.log(' - config/config espelhado a partir do draft.');

  // -------- DOC ROOT: campo "config" (compat) --------
  await lojaRef.set(
    {
      config: draftFinalData,
      ...draftFinalData,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  console.log(' - Campo lojas/{lojaId}.config atualizado.');

  // -------- SETTINGS/GENERAL --------
  const settingsSnap = await settingsGeneralRef.get();
  if (!settingsSnap.exists) {
    console.log(' - Criando settings/general padrão...');
    await settingsGeneralRef.set(defaultSettingsGeneral(), { merge: true });
  } else {
    console.log(' - Atualizando updatedAt em settings/general...');
    await settingsGeneralRef.set(
      { updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  console.log('=== Loja ${lojaId} OK ===');
}

// ===== 4) EXECUÇÃO =====
(async () => {
  try {
    let lojaIds = LOJAS_FIXAS;

    // Se quiser pegar TODAS automaticamente, descomente:
    // lojaIds = await getTodasLojas();

    console.log('Lojas a atualizar:', lojaIds);

    for (const id of lojaIds) {
      await ensureLojaStructure(id);
    }

    console.log('\n✅ Migração finalizada com sucesso.');
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Erro durante a migração:', err);
    process.exit(1);
  }
})();
