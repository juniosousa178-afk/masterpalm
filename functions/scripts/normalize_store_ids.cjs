/**
 * Script de Migração: Normalização de Store IDs
 *
 * Este script:
 * 1. Encontra todas as lojas com IDs em mixed-case (loja_uid_ABC...)
 * 2. Cria versão normalizada (lowercase)
 * 3. Copia todos os dados (produtos, config, etc)
 * 4. Configura redirect no doc original
 * 5. Atualiza referências em users/usuarios
 *
 * Uso:
 *   node scripts/normalize_store_ids.js [--dry-run]
 *
 * --dry-run: Apenas mostra o que seria feito, sem modificar dados
 */

const admin = require('firebase-admin');

// Inicializar Firebase Admin
if (!admin.apps.length) {
  const serviceAccount = require('../masterpalm-service-account.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

// Configuração
const DRY_RUN = process.argv.includes('--dry-run');
const BATCH_SIZE = 400; // Firestore limit is 500

// Subcoleções para copiar
const SUBCOLLECTIONS = [
  'produtos',
  'draft_produtos',
  'config',
  'draft_config',
  'pedidos_pendentes',
  'pedidos',
  'clientes',
  'comissoes',
  'comissoes_vendedores',
  'configuracoes',
  'trackings',
  'members',
  'banners',
  'categorias',
];

/**
 * Verifica se um storeId precisa ser normalizado
 */
function needsNormalization(storeId) {
  if (!storeId) return false;
  const lower = storeId.toLowerCase();
  return lower !== storeId && (storeId.startsWith('loja_uid_') || storeId.startsWith('loja_email_'));
}

/**
 * Copia uma subcoleção de uma loja para outra
 */
async function copySubcollection(sourceLojaId, targetLojaId, subcollection) {
  const sourceRef = db.collection('lojas').doc(sourceLojaId).collection(subcollection);
  const targetRef = db.collection('lojas').doc(targetLojaId).collection(subcollection);

  const snapshot = await sourceRef.get();

  if (snapshot.empty) {
    return 0;
  }

  let copied = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();

    // Atualizar referências ao lojaId nos dados
    const updatedData = JSON.parse(
      JSON.stringify(data).replace(new RegExp(sourceLojaId, 'g'), targetLojaId)
    );

    if (!DRY_RUN) {
      batch.set(targetRef.doc(doc.id), updatedData, { merge: true });
      batchCount++;

      if (batchCount >= BATCH_SIZE) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }
    copied++;
  }

  if (!DRY_RUN && batchCount > 0) {
    await batch.commit();
  }

  return copied;
}

/**
 * Migra uma loja para versão normalizada
 */
async function migrateStore(sourceLojaId) {
  const targetLojaId = sourceLojaId.toLowerCase();

  console.log(`\n${'='.repeat(60)}`);
  console.log(`🔄 Migrando: ${sourceLojaId}`);
  console.log(`   Para:     ${targetLojaId}`);
  console.log(`${'='.repeat(60)}`);

  // 1. Verificar se o doc original existe
  const sourceDoc = await db.collection('lojas').doc(sourceLojaId).get();
  if (!sourceDoc.exists) {
    console.log(`   ⚠️  Doc original não existe, pulando...`);
    return { success: false, reason: 'source_not_found' };
  }

  // 2. Verificar se já tem redirect configurado
  const sourceData = sourceDoc.data();
  if (sourceData.redirectTo === targetLojaId) {
    console.log(`   ✅ Já está migrado (redirect configurado)`);
    return { success: true, reason: 'already_migrated' };
  }

  // 3. Verificar se o doc de destino já existe
  const targetDoc = await db.collection('lojas').doc(targetLojaId).get();

  // 4. Criar/atualizar doc de destino
  const targetData = {
    ...sourceData,
    lojaId: targetLojaId,
    id: targetLojaId,
    slug: sourceData.slug || targetLojaId,
    migratedFrom: sourceLojaId,
    migratedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  delete targetData.redirectTo; // Remover redirectTo do destino

  console.log(`   📝 ${DRY_RUN ? '[DRY-RUN] Criaria' : 'Criando'} doc de destino...`);

  if (!DRY_RUN) {
    await db.collection('lojas').doc(targetLojaId).set(targetData, { merge: true });
  }

  // 5. Copiar subcoleções
  const stats = {};
  for (const subcol of SUBCOLLECTIONS) {
    const count = await copySubcollection(sourceLojaId, targetLojaId, subcol);
    if (count > 0) {
      stats[subcol] = count;
      console.log(`   📦 ${subcol}: ${count} docs ${DRY_RUN ? '(simulado)' : 'copiados'}`);
    }
  }

  // 6. Configurar redirect no doc original
  console.log(`   🔀 ${DRY_RUN ? '[DRY-RUN] Configuraria' : 'Configurando'} redirect...`);

  if (!DRY_RUN) {
    await db.collection('lojas').doc(sourceLojaId).update({
      redirectTo: targetLojaId,
      redirectConfiguredAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  // 7. Atualizar referências em users/{uid}
  const usersQuery = await db.collection('users')
    .where('store_id', '==', sourceLojaId)
    .get();

  if (!usersQuery.empty) {
    console.log(`   👤 ${DRY_RUN ? '[DRY-RUN] Atualizaria' : 'Atualizando'} ${usersQuery.size} users...`);

    if (!DRY_RUN) {
      const batch = db.batch();
      for (const doc of usersQuery.docs) {
        batch.update(doc.ref, {
          store_id: targetLojaId,
          store_id_migrated_from: sourceLojaId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  // 8. Atualizar referências em usuarios/{email}
  const usuariosQuery = await db.collection('usuarios')
    .where('store_id', '==', sourceLojaId)
    .get();

  if (!usuariosQuery.empty) {
    console.log(`   📧 ${DRY_RUN ? '[DRY-RUN] Atualizaria' : 'Atualizando'} ${usuariosQuery.size} usuarios...`);

    if (!DRY_RUN) {
      const batch = db.batch();
      for (const doc of usuariosQuery.docs) {
        batch.update(doc.ref, {
          store_id: targetLojaId,
          store_id_migrated_from: sourceLojaId,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  console.log(`   ✅ ${DRY_RUN ? '[DRY-RUN] Migração simulada' : 'Migração concluída'}`);

  return { success: true, stats };
}

/**
 * Encontra todas as lojas que precisam de normalização
 */
async function findStoresToMigrate() {
  console.log('🔍 Buscando lojas com IDs mixed-case...\n');

  const lojasSnapshot = await db.collection('lojas').get();
  const storesToMigrate = [];

  for (const doc of lojasSnapshot.docs) {
    const lojaId = doc.id;

    if (needsNormalization(lojaId)) {
      const data = doc.data();

      // Pular se já tem redirect configurado
      if (data.redirectTo) {
        console.log(`   ⏭️  ${lojaId} → já tem redirect para ${data.redirectTo}`);
        continue;
      }

      storesToMigrate.push({
        lojaId,
        ownerUid: data.ownerUid,
        slug: data.slug,
      });

      console.log(`   📌 ${lojaId}`);
      console.log(`      slug: ${data.slug || '(não definido)'}`);
      console.log(`      ownerUid: ${data.ownerUid || '(não definido)'}`);
    }
  }

  return storesToMigrate;
}

/**
 * Função principal
 */
async function main() {
  console.log('━'.repeat(60));
  console.log('🔧 SCRIPT DE NORMALIZAÇÃO DE STORE IDs');
  console.log(`   Modo: ${DRY_RUN ? '🔍 DRY-RUN (simulação)' : '⚠️  PRODUÇÃO (vai modificar dados!)'}`);
  console.log('━'.repeat(60));

  try {
    // 1. Encontrar lojas para migrar
    const storesToMigrate = await findStoresToMigrate();

    if (storesToMigrate.length === 0) {
      console.log('\n✅ Nenhuma loja precisa de normalização!');
      process.exit(0);
    }

    console.log(`\n📊 Total de lojas para migrar: ${storesToMigrate.length}`);

    if (DRY_RUN) {
      console.log('\n⚠️  Modo DRY-RUN: Nenhuma alteração será feita.');
      console.log('   Para executar de verdade, remova --dry-run\n');
    }

    // 2. Migrar cada loja
    const results = {
      success: 0,
      failed: 0,
      skipped: 0,
    };

    for (const store of storesToMigrate) {
      try {
        const result = await migrateStore(store.lojaId);

        if (result.success) {
          if (result.reason === 'already_migrated') {
            results.skipped++;
          } else {
            results.success++;
          }
        } else {
          results.failed++;
        }
      } catch (error) {
        console.error(`   ❌ Erro ao migrar ${store.lojaId}: ${error.message}`);
        results.failed++;
      }
    }

    // 3. Resumo
    console.log('\n' + '━'.repeat(60));
    console.log('📊 RESUMO DA MIGRAÇÃO');
    console.log('━'.repeat(60));
    console.log(`   ✅ Sucesso:  ${results.success}`);
    console.log(`   ⏭️  Puladas:  ${results.skipped}`);
    console.log(`   ❌ Falhas:   ${results.failed}`);
    console.log('━'.repeat(60));

    if (DRY_RUN) {
      console.log('\n💡 Execute sem --dry-run para aplicar as mudanças.');
    }

  } catch (error) {
    console.error('❌ Erro fatal:', error);
    process.exit(1);
  }

  process.exit(0);
}

// Executar
main();
