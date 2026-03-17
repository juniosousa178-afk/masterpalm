// Script para limpeza final - remove documentos órfãos
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const ROOT_EMAIL = 'masterpalm@gmail.com';
const ROOT_UID = 'vd0X6xXlq4be0cKhmIOiDtXTvKb2';

async function finalCleanup() {
  console.log('🧹 Limpeza final - removendo documentos órfãos...\n');

  try {
    // 1. Limpar documentos órfãos em /usuarios
    console.log('1️⃣ Limpando documentos órfãos em /usuarios...');
    const usuariosSnapshot = await db.collection('usuarios').get();
    let deletedDocs = 0;

    for (const doc of usuariosSnapshot.docs) {
      const data = doc.data();
      const docId = doc.id;

      // Manter apenas documentos do root
      const isRoot = docId === ROOT_EMAIL ||
                     docId === ROOT_UID ||
                     data.email === ROOT_EMAIL;

      if (!isRoot) {
        await doc.ref.delete();
        deletedDocs++;
        console.log(`   ❌ Deletado: ${docId} (${data.email || 'sem email'})`);
      } else {
        console.log(`   ✅ Mantido: ${docId} (root)`);
      }
    }
    console.log(`✅ ${deletedDocs} documento(s) órfão(s) removido(s)\n`);

    // 2. Limpar master config de usuários deletados
    console.log('2️⃣ Limpando master config...');
    const masterConfigRef = db.collection('app_config').doc('master_config');
    await masterConfigRef.update({
      usersWithUnlimitedAccess: [ROOT_EMAIL],
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: 'final_cleanup_script'
    });
    console.log('✅ Master config atualizado\n');

    // 3. Verificação final
    console.log('3️⃣ Verificação final...');
    const finalUsuarios = await db.collection('usuarios').get();
    console.log(`   Usuários restantes: ${finalUsuarios.size}`);
    finalUsuarios.forEach(doc => {
      const data = doc.data();
      console.log(`      - ${doc.id} (${data.email || 'sem email'})`);
    });

    const finalLojas = await db.collection('lojas').get();
    console.log(`   Lojas restantes: ${finalLojas.size}`);
    finalLojas.forEach(doc => {
      console.log(`      - ${doc.id}`);
    });

    console.log('\n✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ LIMPEZA FINAL CONCLUÍDA!');
    console.log('✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  } catch (error) {
    console.error('❌ Erro durante limpeza final:', error);
    process.exit(1);
  }

  process.exit(0);
}

finalCleanup();
