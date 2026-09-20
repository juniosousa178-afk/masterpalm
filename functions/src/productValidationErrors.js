/** Shared product validation issues for SALE and CONSIGNMENT.
 * Structured, PT-BR actionable. No stack traces / Firestore paths.
 */
import {isMap} from './catalogStockProjection.js';

export const REASON = Object.freeze({
  PRODUCT_NOT_FOUND: 'PRODUCT_NOT_FOUND',
  PRODUCT_INACTIVE: 'PRODUCT_INACTIVE',
  VARIATION_REQUIRED: 'VARIATION_REQUIRED',
  VARIATION_NOT_FOUND: 'VARIATION_NOT_FOUND',
  VARIATION_AMBIGUOUS: 'VARIATION_AMBIGUOUS',
  GRADE_SELECTION_REQUIRED: 'GRADE_SELECTION_REQUIRED',
  GRADE_CELL_NOT_FOUND: 'GRADE_CELL_NOT_FOUND',
  GRADE_CELL_AMBIGUOUS: 'GRADE_CELL_AMBIGUOUS',
  INVALID_STOCK_STATE: 'INVALID_STOCK_STATE',
  MISSING_STOCK_METADATA: 'MISSING_STOCK_METADATA',
  MISSING_DEPENDENCY: 'MISSING_DEPENDENCY',
  STOCK_CONFLICT: 'STOCK_CONFLICT',
  INSUFFICIENT_STOCK: 'INSUFFICIENT_STOCK',
  COMBO_NOT_SUPPORTED: 'COMBO_NOT_SUPPORTED',
  CROSS_STORE_PRODUCT: 'CROSS_STORE_PRODUCT',
  ZERO_STOCK: 'ZERO_STOCK',
  OTHER_PRODUCT_BLOCK: 'OTHER_PRODUCT_BLOCK',
});

export const PRODUCT_VALIDATION_FAILED = 'PRODUCT_VALIDATION_FAILED';

/** Deterministic grade / variation identity. Order: size, color, extra. */
export function gradeKey({size = '', color = '', extra = ''} = {}) {
  const norm = (v) => String(v ?? '').trim();
  return `${norm(size)}\u001e${norm(color)}\u001e${norm(extra)}`;
}

export function gradeKeyLabel({size = '', color = '', extra = ''} = {}) {
  return [size, color, extra].map((v) => String(v ?? '').trim()).filter(Boolean).join(' / ');
}

export function userMessageForReason(reasonCode, {requestedQty, availableQty} = {}) {
  switch (reasonCode) {
    case REASON.INSUFFICIENT_STOCK:
      return `Estoque insuficiente. Disponível: ${availableQty ?? 0}. Solicitado: ${requestedQty ?? 0}.`;
    case REASON.ZERO_STOCK:
      return 'Este produto está sem estoque disponível.';
    case REASON.VARIATION_REQUIRED:
      return 'Selecione a variação deste produto.';
    case REASON.VARIATION_NOT_FOUND:
      return 'Essa variação não está mais disponível.';
    case REASON.VARIATION_AMBIGUOUS:
      return 'A variação deste produto precisa ser atualizada antes de continuar.';
    case REASON.GRADE_SELECTION_REQUIRED:
      return 'Selecione todas as opções deste produto.';
    case REASON.GRADE_CELL_NOT_FOUND:
      return 'Essa combinação não está mais disponível.';
    case REASON.GRADE_CELL_AMBIGUOUS:
      return 'A grade deste produto precisa ser atualizada antes de continuar.';
    case REASON.MISSING_STOCK_METADATA:
      return 'Este produto precisa ser atualizado para o novo controle de estoque.';
    case REASON.MISSING_DEPENDENCY:
      return 'Este produto precisa ser atualizado para o novo controle de estoque.';
    case REASON.INVALID_STOCK_STATE:
      return 'O estoque deste produto precisa ser atualizado antes de continuar.';
    case REASON.STOCK_CONFLICT:
      return 'Há um conflito de estoque neste produto. Tente novamente.';
    case REASON.COMBO_NOT_SUPPORTED:
      return 'Produtos do tipo combo ainda não são suportados nesta operação.';
    case REASON.PRODUCT_NOT_FOUND:
      return 'Produto não encontrado.';
    case REASON.PRODUCT_INACTIVE:
      return 'Este produto está inativo.';
    case REASON.CROSS_STORE_PRODUCT:
      return 'Este produto não pertence a esta loja.';
    case REASON.OTHER_PRODUCT_BLOCK:
    default:
      return 'Este produto não pode ser usado nesta operação.';
  }
}

export function makeIssue({
  productId,
  productName,
  lineIndex = 0,
  selectionLabel = '',
  reasonCode,
  requestedQty = null,
  availableQty = null,
} = {}) {
  const code = REASON[reasonCode] ? reasonCode : REASON.OTHER_PRODUCT_BLOCK;
  return {
    productId: String(productId || ''),
    productName: String(productName || productId || ''),
    lineIndex: Number.isInteger(lineIndex) ? lineIndex : 0,
    selectionLabel: String(selectionLabel || ''),
    reasonCode: code,
    userMessage: userMessageForReason(code, {requestedQty, availableQty}),
    requestedQty: requestedQty == null ? null : requestedQty,
    availableQty: availableQty == null ? null : availableQty,
  };
}

export function productValidationError(issues) {
  const list = Array.isArray(issues) ? issues.filter(isMap) : [];
  const error = new Error(PRODUCT_VALIDATION_FAILED);
  error.code = 'failed-precondition';
  error.consignmentCode = PRODUCT_VALIDATION_FAILED;
  error.stockCode = PRODUCT_VALIDATION_FAILED;
  error.issues = list;
  error.details = {
    code: PRODUCT_VALIDATION_FAILED,
    issues: list,
  };
  return error;
}
