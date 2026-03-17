// tools/scripts/update_produtos_schema.js
// Normaliza os documentos de produtos para o catálogo web (draft + publicados)

const path = require('path');
const admin = require('firebase-admin');

function initAdmin() {
  if (admin.apps.length > 0) return admin;

  // ⚠️ Usa a mesma serviceAccountKey.json que você já usou no migrate_firestore.js
  const serviceAccount = require(path.join(__dirname, 'serviceAccountKey.json'));

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  return admin;
}

const app = initAdmin();
const db = app.firestore();

async function normalizeProdutos(lojaId, collectionName) {
  console.log(`\n📂 Normalizando coleção: lojas/${lojaId}/${collectionName}`);

  const colRef = db.collection('lojas').doc(lojaId).collection(collectionName);
  const snap = await colRef.get();

  if (snap.empty) {
    console.log(`  ⚠️ Nenhum documento encontrado em ${collectionName}`);
    return;
  }

  let count = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const id = doc.id;

    // --------- CAMPOS PRINCIPAIS ---------
    const nome =
      (data.nome && String(data.nome).trim()) ||
      (data.name && String(data.name).trim()) ||
      id;

    const descricaoCurta =
      (data.descricao_curta && String(data.descricao_curta).trim()) ||
      (data.descricao && String(data.descricao).trim()) ||
      '';

    // preço: tenta vários campos
    const precoRaw =
      data.preco ??
      data.preco_venda ??
      data.price ??
      data.precoFinal ??
      0;

    let preco = 0;
    if (typeof precoRaw === 'number') {
      preco = precoRaw;
    } else {
      const parsed = parseFloat(String(precoRaw).replace(',', '.'));
      preco = isNaN(parsed) ? 0 : parsed;
    }

    // imagens
    let imagens = [];
    if (Array.isArray(data.imagens)) {
      imagens = data.imagens.map((e) => String(e));
    }

    let imagemPrincipal =
      (data.imagem_principal && String(data.imagem_principal)) ||
      (data.imageUrl && String(data.imageUrl)) ||
      (imagens.length > 0 ? imagens[0] : '');

    // se não tem array de imagens mas tem principal, cria lista
    if (imagens.length === 0 && imagemPrincipal) {
      imagens = [imagemPrincipal];
    }

    const ativo =
      typeof data.ativo === 'boolean' ? data.ativo : true; // padrão true

    const patch = {
      nome,
      descricao_curta: descricaoCurta,
      preco,
      imagem_principal: imagemPrincipal,
      imagens,
      ativo,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await doc.ref.set(patch, { merge: true });
    count++;
    console.log(`  ✅ Atualizado: ${doc.ref.path}`);
  }

  console.log(`\n✅ Coleção ${collectionName} normalizada (${count} docs).`);
}

async function main() {
  const lojaId = process.argv[2];
  if (!lojaId) {
    console.error('Uso: node update_produtos_schema.js <lojaId>');
    process.exit(1);
  }

  console.log(`🚀 Iniciando normalização de produtos da loja: ${lojaId}`);

  try {
    // atualiza todas as coleções ligadas ao catálogo
    await normalizeProdutos(lojaId, 'produtos');
    await normalizeProdutos(lojaId, 'produtos_draft');
    await normalizeProdutos(lojaId, 'produtos_publicos');

    console.log('\n🎉 Finalizado com sucesso!');
    process.exit(0);
  } catch (e) {
    console.error('❌ Erro ao normalizar produtos:', e);
    process.exit(1);
  }
}

main();
