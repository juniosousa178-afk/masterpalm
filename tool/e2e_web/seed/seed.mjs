/**
 * Seed sintético Firestore + Auth Emulator — R8.4.38
 * Uso: FIRESTORE_EMULATOR_HOST=127.0.0.1:8180 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9199 node seed/seed.mjs
 */
import {
  AUTH_HOST,
  CLIENTE_ID,
  FORNECEDOR_ID,
  LOJA_ID,
  PEDIDO_REVENDA_VAZIO_ID,
  PROD_REVENDA_IDS,
  PROD_REVENDA_NOMES,
  PROD_SIMPLES_ID,
  PROD_SIMPLES_NOME,
  PROD_VAR_ID,
  PROD_VAR_NOME,
  PROJECT_ID,
  USER_DISPLAY,
  USER_EMAIL,
  USER_PASSWORD,
} from '../lib/constants.mjs';
import {
  assertSeedSafe,
  bool,
  dbl,
  int,
  putDoc,
  str,
} from '../lib/firestore-rest.mjs';

assertSeedSafe();

async function ensureAuthUser() {
  const base = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1`;
  const key = 'fake-api-key';
  const body = { email: USER_EMAIL, password: USER_PASSWORD, returnSecureToken: true };

  let res = await fetch(`${base}/accounts:signUp?key=${key}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    res = await fetch(`${base}/accounts:signInWithPassword?key=${key}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`Auth seed failed: ${res.status} ${t}`);
  }
  const data = await res.json();
  return data.localId;
}

function produtoBase(nome, quantidade, extra = {}) {
  return {
    nome: str(nome),
    quantidade: int(quantidade),
    stockRevision: int(1),
    lojaId: str(LOJA_ID),
    precoFinal: dbl(50),
    precoUnitario: dbl(50),
    custoReal: dbl(25),
    slug: str(nome.toLowerCase().replace(/\s+/g, '-')),
    ativo: bool(true),
    publicadoNoCatalogo: bool(false),
    ...extra,
  };
}

async function main() {
  const uid = await ensureAuthUser();

  await putDoc(`lojas/${LOJA_ID}`, {
    nome: str('Empresa QA R8438'),
    ativo: bool(true),
    ownerEmail: str(USER_EMAIL),
  });

  const periodEnd = new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString();

  await putDoc(`users/${uid}`, {
    email: str(USER_EMAIL),
    role: str('admin'),
    lojaId: str(LOJA_ID),
    store_id: str(LOJA_ID),
    currentPlanId: str('lifetime'),
    status: str('active'),
    manualOverride: {
      mapValue: {
        fields: {
          enabled: bool(true),
          planId: str('lifetime'),
        },
      },
    },
    currentPeriodEnd: { timestampValue: periodEnd },
  });

  await putDoc(`usuarios/${USER_EMAIL}`, {
    email: str(USER_EMAIL),
    role: str('admin'),
    loja_id: str(LOJA_ID),
    planoAtivo: bool(true),
    planoId: str('lifetime'),
    tipo: str('admin'),
  });

  await putDoc(`lojas/${LOJA_ID}/clientes/${CLIENTE_ID}`, {
    nome: str('Cliente Sintetico QA'),
    email: str('cliente-sintetico@e2e.local'),
    ativo: bool(true),
  });

  await putDoc(`lojas/${LOJA_ID}/fornecedores/${FORNECEDOR_ID}`, {
    nome: str('Fornecedor QA R8438'),
    ativo: bool(true),
  });

  // Produto simples — estoque 10
  await putDoc(
    `lojas/${LOJA_ID}/estoque_produtos/${PROD_SIMPLES_ID}`,
    produtoBase(PROD_SIMPLES_NOME, 10),
  );

  // Produto com variações P=5, M=6, G=7
  await putDoc(`lojas/${LOJA_ID}/estoque_produtos/${PROD_VAR_ID}`, produtoBase(PROD_VAR_NOME, 18, {
    usaVariacoes: bool(true),
    estoquePorTamanho: {
      mapValue: {
        fields: {
          P: int(5),
          M: int(6),
          G: int(7),
        },
      },
    },
    variacoes: {
      mapValue: {
        fields: {
          P: int(5),
          M: int(6),
          G: int(7),
        },
      },
    },
    tamanhos: {
      arrayValue: {
        values: [str('P'), str('M'), str('G')],
      },
    },
  }));

  // Três produtos para revenda
  for (let i = 0; i < PROD_REVENDA_IDS.length; i++) {
    await putDoc(
      `lojas/${LOJA_ID}/estoque_produtos/${PROD_REVENDA_IDS[i]}`,
      produtoBase(PROD_REVENDA_NOMES[i], 8),
    );
  }

  // Pedido revenda vazio (rascunho)
  await putDoc(`lojas/${LOJA_ID}/compras_fornecedor/${PEDIDO_REVENDA_VAZIO_ID}`, {
    tipoCompra: str('revenda_detalhar_depois'),
    statusCompra: str('rascunho'),
    fornecedorId: str(FORNECEDOR_ID),
    fornecedorNome: str('Fornecedor QA R8438'),
    itens: { arrayValue: { values: [] } },
    estoqueIntegrado: bool(false),
    valorTotal: dbl(0),
  });

  // Contrato emulator REST — 3 linhas + estoque baixado (somente leitura pós-seed)
  const contractItens = [
    { itemId: str('linha-c1'), productId: str(PROD_SIMPLES_ID), quantidade: int(1) },
    { itemId: str('linha-c2'), productId: str(PROD_SIMPLES_ID), quantidade: int(1) },
    { itemId: str('linha-c3'), productId: str(PROD_SIMPLES_ID), quantidade: int(1) },
  ];
  await putDoc(`lojas/${LOJA_ID}/compras_fornecedor/pedido-revenda-r8438-contract`, {
    tipoCompra: str('revenda_detalhar_depois'),
    statusCompra: str('confirmada'),
    itens: { arrayValue: { values: contractItens.map((i) => ({ mapValue: { fields: i } })) } },
    estoqueIntegrado: bool(true),
  });

  const summary = {
    ok: true,
    projectId: PROJECT_ID,
    lojaId: LOJA_ID,
    uid,
    userEmail: USER_EMAIL,
    produtoSimples: PROD_SIMPLES_ID,
    produtoVariacoes: PROD_VAR_ID,
    produtosRevenda: PROD_REVENDA_IDS,
    pedidoRevendaVazio: PEDIDO_REVENDA_VAZIO_ID,
    stockSimples: 10,
    stockVariacoes: { P: 5, M: 6, G: 7 },
  };
  console.log(JSON.stringify(summary));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
