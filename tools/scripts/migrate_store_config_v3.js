/**
 * migrate_store_config_v3.js
 *
 * Uso:
 *  DRY_RUN=true  node migrate_store_config_v3.js
 *  DRY_RUN=false node migrate_store_config_v3.js
 *  DRY_RUN=false DELETE_OLD=true node migrate_store_config_v3.js
 *  ONLY_STORE=masterpalm_gmail_com DRY_RUN=false node migrate_store_config_v3.js
 */

const admin = require('firebase-admin');

const DRY_RUN = (process.env.DRY_RUN ?? 'true').toLowerCase() === 'true';
const DELETE_OLD = (process.env.DELETE_OLD ?? 'false').toLowerCase() === 'true';
const ONLY_STORE = (process.env.ONLY_STORE ?? 'ALL').trim();

function logHeader() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🚀 MIGRAÇÃO STORE CONFIG V3');
  console.log(`DRY_RUN=${DRY_RUN} | DELETE_OLD=${DELETE_OLD} | ONLY_STORE=${ONLY_STORE}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

function deepMerge(a = {}, b = {}) {
  const out = { ...a };
  for (const [k, v] of Object.entries(b || {})) {
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      out[k] = deepMerge(out[k] || {}, v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

function pickThemeFromOld(settingsGeneral, rootDoc) {
  // tenta achar tema em settings/general.theme ou root.theme
  const t1 = settingsGeneral?.theme || {};
  const t2 = rootDoc?.theme || {};
  return deepMerge(t2, t1);
}

function normalizeConfigShape(raw = {}) {
  // aqui você pode padronizar nomes de campos, se quiser
  // (mantive minimalista pra não quebrar nada)
  return raw;
}

async function safeGet(ref) {
  try {
    const snap = await ref.get();
    return snap.exists ? snap.data() : null;
  } catch (_) {
    return null;
  }
}

async function markDeprecated(ref, reason) {
  if (DRY_RUN) {
    console.log(`🟡 [DRY_RUN] mark deprecated -> ${ref.path}`);
    return;
  }
  await ref.set(
    {
      _deprecated: true,
      _deprecatedReason: reason,
      _deprecatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function deleteDoc(ref) {
  if (DRY_RUN) {
    console.log(`🟡 [DRY_RUN] delete -> ${ref.path}`);
    return;
  }
  await ref.delete();
}

async function backupStore(lojaRef) {
  const lojaSnap = await lojaRef.get();
  if (!lojaSnap.exists) return null;

  const lojaId = lojaRef.id;
  const backupId = admin.firestore().collection('_tmp').doc().id; // id aleatório
  const backupRef = lojaRef.collection('_backups_migracao').doc(backupId);

  const payload = {
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    loja: lojaSnap.data(),
  };

  if (DRY_RUN) {
    console.log(`🟡 [DRY_RUN] backup -> ${backupRef.path}`);
    return backupRef.path;
  }
  await backupRef.set(payload, { merge: true });
  return backupRef.path;
}

async function migrateOneStore(lojaRef) {
  const lojaId = lojaRef.id;

  // fontes possíveis
  const rootData = (await lojaRef.get()).data() || {};

  const settingsGeneralRef = lojaRef.collection('settings').doc('general');
  const draftLegacyRef = lojaRef.collection('draft_config').doc('config');

  // seu "config" atual (pode já existir)
  const configDocRef = lojaRef.collection('config').doc('config');

  const settingsGeneral = await safeGet(settingsGeneralRef);
  const draftLegacy = await safeGet(draftLegacyRef);
  const configDoc = await safeGet(configDocRef);

  // Monta BASE mínima
  const base = {
    identidade: {
      nome: rootData?.name || rootData?.slug || lojaId,
      whatsappE164: rootData?.whatsappE164 || settingsGeneral?.whatsappE164 || null,
      pedidoBaseUrl: rootData?.pedido_link_base || rootData?.config?.pedido_link_base || null,
      slug: rootData?.slug || lojaId,
    },
    theme: pickThemeFromOld(settingsGeneral, rootData),
  };

  // published: prioriza config/config atual, senão settings/general, senão base
  const published = normalizeConfigShape(
    deepMerge(
      base,
      configDoc || settingsGeneral || {}
    )
  );

  // draft: prioriza draft_config/config (legacy), senão config/config, senão published
  const draft = normalizeConfigShape(
    deepMerge(
      published,
      draftLegacy || {}
    )
  );

  // documento final V3 (único)
  const v3Doc = {
    schemaVersion: 3,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    migratedFrom: {
      hasSettingsGeneral: !!settingsGeneral,
      hasDraftLegacy: !!draftLegacy,
      hasConfigDoc: !!configDoc,
    },
    draft,
    published,
  };

  // Backup
  await backupStore(lojaRef);

  console.log(`\n🏬 Loja: ${lojaId}`);
  console.log(`   - settings/general? ${!!settingsGeneral}`);
  console.log(`   - draft_config/config? ${!!draftLegacy}`);
  console.log(`   - config/config? ${!!configDoc}`);
  console.log(`   - escrever -> ${configDocRef.path} (schemaVersion=3 + draft/published)`);

  if (DRY_RUN) {
    console.log(`🟡 [DRY_RUN] set -> ${configDocRef.path} (merge=true)`);
  } else {
    await configDocRef.set(v3Doc, { merge: true });
  }

  // Deprecia (ou deleta)
  if (settingsGeneral) {
    if (DELETE_OLD) await deleteDoc(settingsGeneralRef);
    else await markDeprecated(settingsGeneralRef, 'Migrado para config/config (schemaVersion=3)');
  }

  if (draftLegacy) {
    if (DELETE_OLD) await deleteDoc(draftLegacyRef);
    else await markDeprecated(draftLegacyRef, 'Migrado para config/config.draft (schemaVersion=3)');
  }
}

async function main() {
  logHeader();

  // init admin
  if (!admin.apps.length) {
    admin.initializeApp(); // usa GOOGLE_APPLICATION_CREDENTIALS
  }

  const db = admin.firestore();
  const lojasSnap = await db.collection('lojas').get();

  const lojas = lojasSnap.docs
    .map((d) => d.id)
    .filter((id) => (ONLY_STORE === 'ALL' ? true : id === ONLY_STORE));

  if (lojas.length === 0) {
    console.log('⚠️ Nenhuma loja encontrada para migrar.');
    return;
  }

  for (const lojaId of lojas) {
    await migrateOneStore(db.collection('lojas').doc(lojaId));
  }

  console.log('\n✅ Concluído.');
}

main().catch((e) => {
  console.error('\n❌ Erro na migração:', e);
  process.exit(1);
});
