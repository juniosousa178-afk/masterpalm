/**
 * Contrato E2E emulator — estoque não reverte + 3 linhas revenda (Firestore REST).
 * Requer: FIRESTORE_EMULATOR_HOST + seed executado.
 */
const PROJECT_ID = 'masterpalm-r8433-web-e2e-local';
const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const base = `http://${host}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function getDoc(path) {
  const res = await fetch(`${base}/${path}`);
  if (!res.ok) throw new Error(`GET ${path} ${res.status}`);
  return res.json();
}

async function main() {
  if (PROJECT_ID === 'masterpalm-58c46') {
    console.error('WEB_E2E_SYNTHETIC_SEED_PRODUCTION_BLOCKED');
    process.exit(2);
  }

  const lojaId = 'loja-r8433-qa';
  const produtoId = 'prod-r8433-simples';
  const pedidoId = 'pedido-revenda-r8433';

  const est1 = await getDoc(`lojas/${lojaId}/estoque_produtos/${produtoId}`);
  const qty1 = Number(est1.fields?.quantidade?.integerValue ?? -1);
  const rev1 = Number(est1.fields?.stockRevision?.integerValue ?? 0);

  await new Promise((r) => setTimeout(r, 5000));

  const est2 = await getDoc(`lojas/${lojaId}/estoque_produtos/${produtoId}`);
  const qty2 = Number(est2.fields?.quantidade?.integerValue ?? -1);
  const rev2 = Number(est2.fields?.stockRevision?.integerValue ?? 0);

  const ped = await getDoc(`lojas/${lojaId}/compras_fornecedor/${pedidoId}`);
  const itens = ped.fields?.itens?.arrayValue?.values ?? [];

  console.log(JSON.stringify({
    stock: { qtyBefore: qty1, qtyAfter: qty2, revBefore: rev1, revAfter: rev2 },
    revenda: { lineCount: itens.length, lineIds: itens.map((v) => v.mapValue?.fields?.itemId?.stringValue) },
  }, null, 2));

  if (qty2 !== 7 || qty1 !== 7) {
    console.error('WEB_STOCK_E2E_NO_REVERSION_FAIL: estoque reverteu');
    process.exit(3);
  }
  if (rev2 < rev1) {
    console.error('WEB_STOCK_E2E_NO_REVERSION_FAIL: stockRevision regrediu');
    process.exit(4);
  }
  if (itens.length !== 3) {
    console.error('REVENDAS_ITEMS_DISAPPEAR_REPRODUCED: linhas=' + itens.length);
    process.exit(5);
  }
  console.log('WEB_STOCK_E2E_NO_REVERSION_GREEN');
  console.log('REVENDAS_ITEMS_PERSISTENCE_WEB_E2E_GREEN');
}

main().catch((e) => { console.error(e); process.exit(1); });
