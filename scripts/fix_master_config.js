// Script para corrigir configuração master após limpeza
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixMasterConfig() {
  console.log('🔧 Corrigindo configuração master...\n');

  try {
    const masterConfigRef = db.collection('app_config').doc('master_config');
    const masterConfigDoc = await masterConfigRef.get();

    if (masterConfigDoc.exists) {
      const data = masterConfigDoc.data();

      // Remover usuários deletados da lista de acesso ilimitado
      const usersWithUnlimitedAccess = data.usersWithUnlimitedAccess || [];
      console.log('📋 Usuários com acesso ilimitado (antes):');
      usersWithUnlimitedAccess.forEach(user => console.log(`   - ${user}`));

      // Manter apenas masterpalm@gmail.com
      const updatedUsers = ['masterpalm@gmail.com'];

      console.log('\n📋 Usuários com acesso ilimitado (depois):');
      updatedUsers.forEach(user => console.log(`   - ${user}`));

      await masterConfigRef.update({
        usersWithUnlimitedAccess: updatedUsers,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: 'cleanup_script'
      });

      console.log('\n✅ Configuração master atualizada com sucesso!');
    } else {
      console.log('⚠️ Master config não encontrado');
    }

  } catch (error) {
    console.error('❌ Erro ao corrigir master config:', error);
  }

  process.exit(0);
}

fixMasterConfig();
