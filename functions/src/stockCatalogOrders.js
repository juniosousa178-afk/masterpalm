import {createHash} from 'node:crypto';
import {executeStockCommandInTransaction, runStockTransaction} from './stockCatalogCommands.js';
import {authorizeStockTransaction, documentId, storeRef, SERVER_PAYMENT_AUTH} from './stockCatalogAccess.js';
import {isMap, quantity, stockError} from './catalogStockProjection.js';

export function orderStockOperationId(orderId) {
  return `order_${createHash('sha256').update(documentId(orderId, 'orderId')).digest('hex')}`;
}
function mapOrderItem(item) {
  if (!isMap(item)) throw stockError('failed-precondition', 'Invalid persisted order item');
  const productId = documentId(item.productId ?? item.produtosId ?? item.id, 'canonical productId');
  const count = quantity(item.qty ?? item.quantidade);
  if (!count) throw stockError('failed-precondition', 'Empty persisted order item');
  const result = {productId, quantity: count, size: item.tamanho ?? item.size ?? '',
    color: item.cor ?? item.color ?? '', extra: item.extraValor ?? item.variacaoExtra ?? ''};
  // Versioned configurable selections carry canonical group identities. A legacy
  // component list cannot override a fixed canonical recipe.
  if (item.stockSelection !== undefined) result.selection = item.stockSelection;
  return result;
}
/** Order snapshot must be read by this same transaction, never supplied through callable payload. */
export async function applyOrderStockInTransaction(tx, db, lojaId, orderId, order, reservedWrites = 0) {
  const rows = order.items ?? order.itens;
  if (!Array.isArray(rows) || !rows.length) throw stockError('failed-precondition', 'Persisted order items required');
  return executeStockCommandInTransaction(tx, db, {
    protocolVersion: 1, lojaId, operationId: orderStockOperationId(orderId), kind: 'sale', items: rows.map(mapOrderItem),
  }, SERVER_PAYMENT_AUTH, reservedWrites);
}
/** Manual confirmation and verified payment webhook converge on the same server identity and request. */
export async function executeOrderStockCommand(db, lojaId, orderId, auth) {
  const base = storeRef(db, lojaId); documentId(orderId, 'orderId');
  return runStockTransaction(db, async tx => {
    await authorizeStockTransaction(tx, base, auth, 'sale');
    const snapshots = await tx.getAll(...['pedidos', 'pre_pedidos', 'pedidos_pendentes'].map(name => base.collection(name).doc(orderId)));
    const order = snapshots.find(s => s.exists);
    if (!order) throw stockError('not-found', 'Order not found');
    return applyOrderStockInTransaction(tx, db, lojaId, orderId, order.data());
  });
}
