const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Inicializa o Firebase Admin com a service account
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function main() {
  // 🔐 Aqui definimos os usuários que vão ter tipo + lojaIdPrincipal + lojas[]
  const usuarios = [
    {
      email: 'masterpalm@gmail.com',
      tipo: 'admin',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
    {
      email: 'admin@masterpalm.com',
      tipo: 'admin',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
    {
      email: 'juniosousa178@gmail.com',
      tipo: 'admin',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
    {
      email: 'claudiokbk@gmail.com',
      tipo: 'vendedor',
      lojaIdPrincipal: 'masterpalm',
      lojas: ['masterpalm'],
    },
    // Se quiser adicionar mais, só copiar esse bloco e trocar os dados
    // {
    //   email: 'outro@email.com',
    //   tipo: 'vendedor',
    //   lojaIdPrincipal: 'minha-loja',
    //   lojas: ['minha-loja'],
    // },
  ];

  for (const u of usuarios) {
    const ref = db.collection('usuarios').doc(u.email);
    console.log('🔄 Atualizando usuário:', ref.path, '=>', u);

    await ref.set(
      {
        tipo: u.tipo,
        lojaIdPrincipal: u.lojaIdPrincipal,
        lojas: u.lojas,
      },
      { merge: true },
    );
  }

  console.log('✅ Configuração de usuarios/lojas concluída!');
  process.exit(0);
}

main().catch((err) => {
  console.error('💥 Erro geral no script:', err);
  process.exit(1);
});
