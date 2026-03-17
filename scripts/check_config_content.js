const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkConfigContent() {
  console.log('🔍 VERIFICANDO CONTEÚDO DO CONFIG...\n');

  const lojaId = 'nathy-pratas-e-folheados';

  // 1. Verificar config publicado
  console.log(`📁 /lojas/${lojaId}/config/config`);
  const configDoc = await db.collection('lojas').doc(lojaId).collection('config').doc('config').get();

  if (!configDoc.exists) {
    console.log('   ❌ DOCUMENTO NÃO EXISTE!\n');
    return;
  }

  const data = configDoc.data();
  const keys = Object.keys(data);

  console.log(`   ✅ Documento existe`);
  console.log(`   📊 Total de campos: ${keys.length}\n`);

  if (keys.length === 0) {
    console.log('   🔴 PROBLEMA: Documento VAZIO! (0 campos)');
    console.log('   Isso faz o catálogo mostrar "Configuração da loja não encontrada"\n');
  } else {
    console.log('   ✅ Documento tem campos:');
    keys.forEach(key => {
      const value = data[key];
      if (typeof value === 'object' && value !== null) {
        console.log(`   - ${key}: [objeto/array com ${Object.keys(value).length || 0} itens]`);
      } else {
        console.log(`   - ${key}: ${value}`);
      }
    });
  }

  console.log('\n════════════════════════════════════════════════════\n');

  // 2. Verificar draft_config
  console.log(`📁 /lojas/${lojaId}/draft_config/config`);
  const draftConfigDoc = await db.collection('lojas').doc(lojaId).collection('draft_config').doc('config').get();

  if (!draftConfigDoc.exists) {
    console.log('   ❌ DOCUMENTO NÃO EXISTE!\n');
    return;
  }

  const draftData = draftConfigDoc.data();
  const draftKeys = Object.keys(draftData);

  console.log(`   ✅ Documento existe`);
  console.log(`   📊 Total de campos: ${draftKeys.length}\n`);

  if (draftKeys.length === 0) {
    console.log('   🔴 PROBLEMA: Documento VAZIO!\n');
  } else {
    console.log('   ✅ Documento tem campos:');
    draftKeys.forEach(key => {
      const value = draftData[key];
      if (typeof value === 'object' && value !== null) {
        console.log(`   - ${key}: [objeto/array]`);
      } else {
        console.log(`   - ${key}: ${value}`);
      }
    });
  }

  console.log('\n════════════════════════════════════════════════════\n');

  // 3. Comparar
  if (keys.length === 0 && draftKeys.length > 0) {
    console.log('🎯 DIAGNÓSTICO:');
    console.log('   - draft_config TEM dados ✅');
    console.log('   - config está VAZIO ❌');
    console.log('');
    console.log('💡 SOLUÇÃO: Executar publish novamente!');
    console.log('   node scripts/publish_naty_catalog.js');
  } else if (keys.length > 0) {
    console.log('✅ Config publicado está OK!');
    console.log('');
    console.log('🔍 Se ainda aparece erro, pode ser:');
    console.log('   1. Cache do Flutter web (precisa rebuild)');
    console.log('   2. Problema de permissões no Firestore');
    console.log('   3. Regras de segurança bloqueando leitura');
  }

  console.log('\n');

  process.exit(0);
}

checkConfigContent();
