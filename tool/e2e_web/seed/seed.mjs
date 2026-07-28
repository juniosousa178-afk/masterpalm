/**
 * Seed sintético Firestore Emulator — R8.4.33
 * Uso: node tool/e2e_web/seed/seed.mjs
 * Requer: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 */
const PROJECT_ID = 'masterpalm-r8433-web-e2e-local';
const PRODUCTION_BLOCKED = 'masterpalm-58c46';

if (process.env.GCLOUD_PROJECT === PRODUCTION_BLOCKED) {
  console.error('WEB_E2E_SYNTHETIC_SEED_PRODUCTION_BLOCKED');
  process.exit(2);
}

const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const base = `http://${host}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function putDoc(path, fields) {
  const url = `${base}/${path}`;
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`PUT ${path} failed: ${res.status} ${t}`);
  }
}

function str(v) {
  return { stringValue: String(v) };
}
function int(v) {
  return { integerValue: String(v) };
}

async function main() {
  const lojaId = 'loja-r8433-qa';
  const produtoId = 'prod-r8433-simples';
  const pedidoId = 'pedido-revenda-r8433';

  await putDoc(`lojas/${lojaId}`, {
    nome: str('Empresa QA R8433'),
    ativo: { booleanValue: true },
  });

  await putDoc(`lojas/${lojaId}/estoque_produtos/${produtoId}`, {
    nome: str('Produto QA'),
    quantidade: int(10),
    stockRevision: int(1),
    lojaId: str(lojaId),
  });

  const itens = [
    { itemId: str('linha-1'), productId: str(produtoId), quantidade: int(1) },
    { itemId: str('linha-2'), productId: str(produtoId), quantidade: int(1) },
    { itemId: str('linha-3'), productId: str(produtoId), quantidade: int(1) },
  ];

  await putDoc(`lojas/${lojaId}/compras_fornecedor/${pedidoId}`, {
    tipoCompra: str('revenda_detalhar_depois'),
    statusCompra: str('confirmada'),
    itens: {
      arrayValue: {
        values: itens.map((i) => ({
          mapValue: { fields: i },
        })),
      },
    },
    estoqueIntegrado: { booleanValue: true },
  });

  // Estoque baixado (7) — não deve reverter
  await putDoc(`lojas/${lojaId}/estoque_produtos/${produtoId}`, {
    nome: str('Produto QA'),
    quantidade: int(7),
    stockRevision: int(2),
    stockOperationId: str('op-r8433-baixa'),
    lojaId: str(lojaId),
  });

  console.log(
    JSON.stringify({
      ok: true,
      projectId: PROJECT_ID,
      lojaId,
      produtoId,
      pedidoId,
      lineIds: ['linha-1', 'linha-2', 'linha-3'],
      stockQty: 7,
      stockRevision: 2,
    }),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
