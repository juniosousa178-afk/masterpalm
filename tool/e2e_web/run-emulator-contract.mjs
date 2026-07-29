/**
 * Contrato E2E emulator — estoque não reverte + 3 linhas revenda (Firestore REST).
 * Requer: FIRESTORE_EMULATOR_HOST + seed executado.
 * Classificações: WEB_STOCK_EMULATOR_CONTRACT_* / REVENDAS_ITEMS_PERSISTENCE_EMULATOR_CONTRACT_*
 */
import {
  LOJA_ID,
  PROD_SIMPLES_ID,
  PROJECT_ID,
} from './lib/constants.mjs';
import { parseIntField } from './lib/firestore-rest.mjs';

const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
const base = `http://${host}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function getDocPath(path) {
  const res = await fetch(`${base}/${path}`);
  if (!res.ok) throw new Error(`GET ${path} ${res.status}`);
  return res.json();
}

async function main() {
  if (PROJECT_ID === 'masterpalm-58c46') {
    console.error('WEB_E2E_SYNTHETIC_SEED_PRODUCTION_BLOCKED');
    process.exit(2);
  }

  const pedidoId = 'pedido-revenda-r8438-contract';

  const est1 = await getDocPath(`lojas/${LOJA_ID}/estoque_produtos/${PROD_SIMPLES_ID}`);
  const qty1 = parseIntField(est1.fields, 'quantidade', -1);
  const rev1 = parseIntField(est1.fields, 'stockRevision', 0);

  await new Promise((r) => setTimeout(r, 5000));

  const est2 = await getDocPath(`lojas/${LOJA_ID}/estoque_produtos/${PROD_SIMPLES_ID}`);
  const qty2 = parseIntField(est2.fields, 'quantidade', -1);
  const rev2 = parseIntField(est2.fields, 'stockRevision', 0);

  const ped = await getDocPath(`lojas/${LOJA_ID}/compras_fornecedor/${pedidoId}`);
  const itens = ped.fields?.itens?.arrayValue?.values ?? [];

  console.log(JSON.stringify({
    stock: { qtyBefore: qty1, qtyAfter: qty2, revBefore: rev1, revAfter: rev2 },
    revenda: { lineCount: itens.length, lineIds: itens.map((v) => v.mapValue?.fields?.itemId?.stringValue) },
  }, null, 2));

  if (qty2 !== qty1 || qty1 !== 10) {
    console.error('WEB_STOCK_EMULATOR_CONTRACT_NO_REVERSION_FAIL: estoque reverteu');
    process.exit(3);
  }
  if (rev2 < rev1) {
    console.error('WEB_STOCK_EMULATOR_CONTRACT_NO_REVERSION_FAIL: stockRevision regrediu');
    process.exit(4);
  }
  if (itens.length !== 3) {
    console.error('REVENDAS_ITEMS_DISAPPEAR_REPRODUCED_EMULATOR_CONTRACT: linhas=' + itens.length);
    process.exit(5);
  }
  console.log('WEB_STOCK_EMULATOR_CONTRACT_NO_REVERSION_GREEN');
  console.log('REVENDAS_ITEMS_PERSISTENCE_EMULATOR_CONTRACT_GREEN');
  console.log('EMULATOR_CONTRACT_NAMING_CORRECTED');
}

main().catch((e) => { console.error(e); process.exit(1); });
