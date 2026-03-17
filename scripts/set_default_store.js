// Script para definir loja padrão com logo/banners configurados
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const ROOT_EMAIL = 'masterpalm@gmail.com';
const ROOT_UID = 'vd0X6xXlq4be0cKhmIOiDtXTvKb2';

async function setDefaultStore() {
  console.log('🔧 Configurando loja padrão...\n');

  try {
    const targetLojaId = `loja_uid_${ROOT_UID}`;

    console.log(`✅ Loja escolhida: ${targetLojaId}`);
    console.log(`   (Esta loja TEM logo e banners configurados)\n`);

    // Atualizar documento do usuário root para apontar para esta loja
    const usuarioRef = db.collection('usuarios').doc(ROOT_EMAIL);
    await usuarioRef.set({
      email: ROOT_EMAIL,
      lojaId: targetLojaId,
      tipo: 'admin',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Usuário ${ROOT_EMAIL} vinculado à loja ${targetLojaId}`);

    // Atualizar documento da loja
    const lojaRef = db.collection('lojas').doc(targetLojaId);
    await lojaRef.set({
      slug: targetLojaId,
      owner: ROOT_EMAIL,
      nome: 'MasterPalm - Loja Principal',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      publishedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ Loja ${targetLojaId} atualizada`);

    // Verificar se configuração está OK
    const configRef = db.collection('lojas').doc(targetLojaId).collection('config').doc('config');
    const configSnap = await configRef.get();

    if (configSnap.exists) {
      const cfg = configSnap.data();
      const media = cfg.media || {};

      console.log(`\n📱 Configurações da loja:`);
      console.log(`   Logo Mobile: ${media.mobile?.logoUrl ? '✅ CONFIGURADO' : '❌ NÃO CONFIGURADO'}`);
      console.log(`   Logo Desktop: ${media.desktop?.logoUrl ? '✅ CONFIGURADO' : '❌ NÃO CONFIGURADO'}`);
      console.log(`   Banners Mobile: ${media.mobile?.banners?.length || 0} banner(s)`);
      console.log(`   Banners Desktop: ${media.desktop?.banners?.length || 0} banner(s)`);
    }

    console.log('\n✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ LOJA PADRÃO CONFIGURADA COM SUCESSO!');
    console.log('✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`\n📝 Próximo passo: Reinicie o app e faça login novamente`);

  } catch (error) {
    console.error('❌ Erro:', error);
  }

  process.exit(0);
}

setDefaultStore();
