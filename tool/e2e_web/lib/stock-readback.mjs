/** Readback técnico pós-operação UI — somente leitura (R8.4.38) */

import { LOJA_ID } from './constants.mjs';
import { getDoc, parseIntField, parseStringField } from './firestore-rest.mjs';

export async function readStockProduct(produtoId) {
  const doc = await getDoc(`lojas/${LOJA_ID}/estoque_produtos/${produtoId}`);
  const f = doc.fields ?? {};
  const estoquePorTamanho = {};
  const raw = f.estoquePorTamanho?.mapValue?.fields ?? {};
  for (const [k, v] of Object.entries(raw)) {
    estoquePorTamanho[k] = Number(v.integerValue ?? v.doubleValue ?? 0);
  }
  return {
    produtoId,
    quantidade: parseIntField(f, 'quantidade'),
    stockRevision: parseIntField(f, 'stockRevision'),
    stockOperationId: parseStringField(f, 'stockOperationId'),
    stockSyncState: parseStringField(f, 'stockSyncState'),
    pendingStockOperationId: parseStringField(f, 'pendingStockOperationId'),
    estoquePorTamanho,
  };
}

export async function readRevendaPedido(pedidoId) {
  const doc = await getDoc(`lojas/${LOJA_ID}/compras_fornecedor/${pedidoId}`);
  const itens = doc.fields?.itens?.arrayValue?.values ?? [];
  return {
    pedidoId,
    lineCount: itens.length,
    lineIds: itens.map((v) => v.mapValue?.fields?.itemId?.stringValue).filter(Boolean),
    itens,
  };
}
