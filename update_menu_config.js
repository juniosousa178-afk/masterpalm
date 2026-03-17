// Script para atualizar configurações do menu no Firestore
const admin = require('firebase-admin');

// Inicializar Firebase Admin
const serviceAccount = require('./functions/serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function updateMenuConfig() {
  const lojaId = 'nathy-pratas-e-folheados';

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🔧 Atualizando configurações do menu');
  console.log(`   Loja: ${lojaId}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Configurações do menu (ajuste conforme necessário)
  const menuConfig = {
    'menu.categorias': true,      // Mostrar categorias
    'menu.entrar': true,          // ✅ MOSTRAR botões "Entrar" e "Cadastrar"
    'menu.contato': true,          // Mostrar contato rápido
    'menu.sac': true,              // Mostrar SAC
    'menu.quemSomos': true,        // Mostrar Quem Somos
    'menu.mobileMenuGrid': true,   // Menu mobile em grid
  };

  try {
    // Atualizar em draft_config
    const draftRef = db.collection('lojas').doc(lojaId).collection('draft_config').doc('config');
    await draftRef.update(menuConfig);
    console.log('✅ Atualizado em draft_config/config');

    // Atualizar em config (publicado)
    const configRef = db.collection('lojas').doc(lojaId).collection('config').doc('config');
    await configRef.update(menuConfig);
    console.log('✅ Atualizado em config/config (PUBLICADO)');

    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('✅ Configurações atualizadas com sucesso!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('');
    console.log('📋 Configurações aplicadas:');
    console.log('   Categorias: SIM');
    console.log('   Entrar: SIM ⭐');
    console.log('   Cadastrar: SIM ⭐');
    console.log('   Contato Rápido: SIM');
    console.log('   SAC: SIM');
    console.log('   Quem Somos: SIM');
    console.log('');
    console.log('🌐 Teste agora em: https://mastepalm.com.br/loja/nathy-pratas-e-folheados');
    console.log('   (Limpe o cache do navegador com Ctrl + Shift + Delete)');
    console.log('');

  } catch (error) {
    console.error('❌ Erro ao atualizar:', error);
  } finally {
    process.exit(0);
  }
}

updateMenuConfig();
