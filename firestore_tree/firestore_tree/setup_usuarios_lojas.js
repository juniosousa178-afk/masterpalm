// setup_usuarios_lojas.js
// Script para ajustar a coleção "usuarios" com tipo, lojaIdPrincipal e lojas[]

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Inicializa o Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

// Lista de usuários que queremos garantir no Firestore
const usuarios = [
  {
    id: 'admin@masterpalm.com',
    data: {
      tipo: 'admin',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
  },
  {
    id: 'masterpalm@gmail.com',
    data: {
      tipo: 'admin',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
  },
  {
    id: 'juniosousa178@gmail.com',
    data: {
      tipo: 'admin',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
  },
  {
    id: 'claudiokbk@gmail.com',
    data: {
      tipo: 'vendedor',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
  },
  {
    id: 'pikenaroll@gmail.com',
    data: {
      tipo: 'vendedor',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
  },
];

async function main() {
  console.log('🔥 Iniciando setup de usuarios...');

  for (const u of usuarios) {
    const ref = db.collection('usuarios').doc(u.id);
    await ref.set(u.data, { merge: true });
    console.log(`✅ Atualizado: usuarios/${u.id}`);
  }

  console.log('✨ Concluído com sucesso!');
  process.exit(0);
}

main().catch((err) => {
  console.error('💥 Erro ao executar setup_usuarios_lojas:', err);
  process.exit(1);
});
