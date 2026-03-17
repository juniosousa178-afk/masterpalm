// migrate_lojas_schema.js
// Normaliza a estrutura das lojas usando uma loja "template" como base
// e cria uma ROLETA PADRÃO em /lojas/{lojaId}/campanhas_sorteio, se a loja ainda não tiver nenhuma.

const admin = require('firebase-admin');

// ⚠️ Ajuste o caminho do service account se precisar
const serviceAccount = require('./serviceAccountKey.json');

// Loja que será usada como MODELO de estrutura (a sua já está completa)
const TEMPLATE_LOJA_ID = 'masterpalm_gmail_com';

// Se quiser primeiro só ver o que seria feito, deixe DRY_RUN = true
const DRY_RUN = false;
 // depois troque para false para aplicar de verdade

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

/**
 * Clona um objeto profundamente
 */
function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj || {}));
}

/**
 * Ajusta campos específicos do template para uma loja alvo
 */
function sanitizeTemplateForLoja(templateData, lojaId, lojaRootData) {
  const data = deepClone(templateData);

  const slug = lojaRootData.slug || lojaId;
  const ownerUid = lojaRootData.ownerUid || (lojaRootData.owner && lojaRootData.owner.uid);
  const pedidoLinkBase = lojaRootData.pedido_link_base || data.pedido_link_base;
  const whatsappE164 = lojaRootData.whatsappE164 || null;

  // slug
  if (data.slug !== undefined) data.slug = slug;

  // ownerUid
  if (data.ownerUid !== undefined && ownerUid) {
    data.ownerUid = ownerUid;
  }

  // owner (caso exista)
  if (data.owner) {
    data.owner = {
      ...data.owner,
      uid: ownerUid || data.owner.uid,
      email: (lojaRootData.owner && lojaRootData.owner.email) || data.owner.email,
      emailPrefix:
        (lojaRootData.owner && lojaRootData.owner.emailPrefix) ||
        slug.replace(/[^a-z0-9_]/gi, '_'),
    };
  }

  // pedido_link_base
  if (pedidoLinkBase) {
    data.pedido_link_base = pedidoLinkBase;
  }

  // whatsappE164 / whatsapp
  if (data.whatsappE164 !== undefined && whatsappE164) {
    data.whatsappE164 = whatsappE164;
  }
  if (data.whatsapp !== undefined && lojaRootData.whatsapp) {
    data.whatsapp = lojaRootData.whatsapp;
  }

  return data;
}

/**
 * Cria um documento se ele não existir, usando um builder de dados
 */
async function ensureDoc(path, buildDataFn) {
  const ref = db.doc(path);
  const snap = await ref.get();
  if (snap.exists) {
    console.log(`✔ Já existe: ${path}`);
    return;
  }

  const data = await buildDataFn();
  if (!data) {
    console.warn(`⚠ Sem dados para criar ${path}, pulando...`);
    return;
  }

  console.log(`🆕 Vai criar: ${path}`);
  if (!DRY_RUN) {
    await ref.set(data, { merge: true });
  }
}

/**
 * Cria uma ROLETA PADRÃO em /lojas/{lojaId}/campanhas_sorteio
 * apenas se a loja ainda não tiver nenhuma campanha.
 */
async function ensureDefaultRoleta(lojaId, lojaRootData) {
  const collRef = db.collection(`lojas/${lojaId}/campanhas_sorteio`);

  const existing = await collRef.limit(1).get();
  if (!existing.empty) {
    console.log(`✔ Loja ${lojaId} já tem campanhas_sorteio, não vou criar roleta padrão.`);
    return;
  }

  const docRef = collRef.doc(); // id aleatório

  const agora = admin.firestore.Timestamp.now();

  const defaultData = {
    tipo: 'roleta',
    titulo: 'Roleta padrão',
    descricao:
      'Configuração inicial de roleta criada automaticamente. Edite livremente no app.',
    status: 'aberta', // o app pode filtrar por "aberta"
    lojaId,
    criadoEm: agora,
    atualizadoEm: agora,
    // 🔹 valor mínimo padrão (pode ser alterado no app)
    valorMinimoCompra: 150.0,
    // 🔹 lista de prêmios padrão (igual ao layout que te mostrei)
    premios: [
      {
        texto: '5% OFF',
        tipo: 'percent', // % de desconto
        valor: 5,
        ativo: true,
      },
      {
        texto: '10% OFF',
        tipo: 'percent',
        valor: 10,
        ativo: true,
      },
      {
        texto: 'R$ 20 OFF',
        tipo: 'valor', // desconto em reais
        valor: 20,
        ativo: true,
      },
      {
        texto: 'Frete grátis',
        tipo: 'frete_gratis',
        valor: 0,
        ativo: true,
      },
      {
        texto: 'Brinde surpresa',
        tipo: 'brinde',
        valor: 0,
        ativo: true,
      },
      {
        texto: 'Tente novamente',
        tipo: 'nada',
        valor: 0,
        ativo: true,
      },
    ],
  };

  console.log(`🆕 Vai criar ROLETA PADRÃO em lojas/${lojaId}/campanhas_sorteio/${docRef.id}`);
  if (!DRY_RUN) {
    await docRef.set(defaultData, { merge: true });
  }
}

/**
 * Carrega os documentos do template que vamos reutilizar
 */
async function loadTemplateDocs() {
  const paths = [
    `lojas/${TEMPLATE_LOJA_ID}/config/config`,
    `lojas/${TEMPLATE_LOJA_ID}/config/marketplaces`,
    `lojas/${TEMPLATE_LOJA_ID}/config/payments`,
    `lojas/${TEMPLATE_LOJA_ID}/config/shipping`,
    `lojas/${TEMPLATE_LOJA_ID}/draft_config/config`,
    `lojas/${TEMPLATE_LOJA_ID}/settings/general`,
  ];

  const result = {};
  for (const path of paths) {
    const snap = await db.doc(path).get();
    if (!snap.exists) {
      console.warn(`⚠ Template não tem o doc esperado: ${path}`);
      continue;
    }
    result[path] = snap.data();
  }

  return result;
}

async function main() {
  console.log('════════ MIGRAÇÃO DE LOJAS – INÍCIO ════════');
  console.log(`Usando loja template: ${TEMPLATE_LOJA_ID}`);
  console.log(`Modo DRY_RUN = ${DRY_RUN ? 'SIM (não grava nada)' : 'NÃO (vai escrever no Firestore)'}`);
  console.log('────────────────────────────────────────────\n');

  const templateDocs = await loadTemplateDocs();

  const lojasSnap = await db.collection('lojas').get();
  if (lojasSnap.empty) {
    console.log('Nenhuma loja encontrada em /lojas.');
    return;
  }

  for (const lojaDoc of lojasSnap.docs) {
    const lojaId = lojaDoc.id;
    const lojaData = lojaDoc.data() || {};

    console.log('\n================================================');
    console.log(`🏬 LOJA: ${lojaId}`);
    console.log('================================================');

    //
    // 1) config/config
    //
    await ensureDoc(
      `lojas/${lojaId}/config/config`,
      async () => {
        const template = templateDocs[`lojas/${TEMPLATE_LOJA_ID}/config/config`];
        if (!template) return null;
        return sanitizeTemplateForLoja(template, lojaId, lojaData);
      },
    );

    //
    // 2) config/marketplaces
    //
    await ensureDoc(
      `lojas/${lojaId}/config/marketplaces`,
      async () => {
        const template = templateDocs[`lojas/${TEMPLATE_LOJA_ID}/config/marketplaces`];
        if (!template) return null;
        return deepClone(template);
      },
    );

    //
    // 3) config/payments
    //
    await ensureDoc(
      `lojas/${lojaId}/config/payments`,
      async () => {
        const template = templateDocs[`lojas/${TEMPLATE_LOJA_ID}/config/payments`];
        if (!template) return null;
        return deepClone(template);
      },
    );

    //
    // 4) config/shipping
    //
    await ensureDoc(
      `lojas/${lojaId}/config/shipping`,
      async () => {
        const template = templateDocs[`lojas/${TEMPLATE_LOJA_ID}/config/shipping`];
        if (!template) return null;
        return deepClone(template);
      },
    );

    //
    // 5) draft_config/config
    //
    await ensureDoc(
      `lojas/${lojaId}/draft_config/config`,
      async () => {
        const template = templateDocs[`lojas/${TEMPLATE_LOJA_ID}/draft_config/config`];
        if (!template) return null;
        return sanitizeTemplateForLoja(template, lojaId, lojaData);
      },
    );

    //
    // 6) settings/general
    //
    await ensureDoc(
      `lojas/${lojaId}/settings/general`,
      async () => {
        const template = templateDocs[`lojas/${TEMPLATE_LOJA_ID}/settings/general`];
        if (!template) return null;
        return sanitizeTemplateForLoja(template, lojaId, lojaData);
      },
    );

    //
    // 7) campanhas_sorteio: cria uma roleta padrão, se a loja ainda não tiver nenhuma
    //
    await ensureDefaultRoleta(lojaId, lojaData);
  }

  console.log('\n✔ Migração concluída.');
  if (DRY_RUN) {
    console.log('Obs: DRY_RUN estava ativado, nada foi escrito. Mude para false para aplicar de verdade.');
  }
}

main().catch((err) => {
  console.error('❌ Erro na migração:', err);
  process.exit(1);
});
