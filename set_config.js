// set_config.js
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

async function main() {
  const slug = 'masterpalm'; // altere se o ID da loja for outro

  const data = {
    slug: slug,
    name: 'Master Palm Store',
    pedido_link_base: 'https://gestao.mastepalm.com.br/pedido',
    whatsapp: '5533999998888',
    whatsapp_vendedor: '5533999998888',
    colors: {
      bg: 4293980407,
      card: 4294967295,
      text: 4279176977,
      primary: 4279176977,
      btnText: 4294967295
    },
    fretes: [
      { nome: 'Retirada', valor: 0.0 },
      { nome: 'Entrega local', valor: 10.0 },
      { nome: 'Outros estados', valor: 25.0 }
    ],
    payments: [
      'mastercard','visa','hipercard','amex','diners','elo',
      'pix','boleto','transfer','barcode'
    ],
    links: {
      instagram: 'https://instagram.com/masterpalm',
      facebook: 'https://facebook.com/masterpalm',
      sobre: 'https://gestao.mastepalm.com.br/sobre',
      trocas: 'https://gestao.mastepalm.com.br/trocas',
      login: 'https://gestao.mastepalm.com.br/login'
    },
    empresa: {
      razao: 'Master Palm LTDA',
      cnpj: '12.345.678/0001-90'
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  };

  await db.collection('lojas').doc(slug).collection('draft_config').doc('config').set(data);
  console.log('✅ Configuração enviada com sucesso para Firestore!');
}

main()
  .then(() => process.exit(0))
  .catch((err) => { console.error('❌ Erro:', err); process.exit(1); });
