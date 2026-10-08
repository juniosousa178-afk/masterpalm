/**
 * Safe manual physical stock reconciliation helpers.
 * Absolute counts only — never infer structure from legacy metadata alone.
 */
import {isMap, stockError, normalizeStock, quantity, cellTotal} from './catalogStockProjection.js';

export const PHYSICAL_RECONCILIATION_TYPE = 'PHYSICAL_RECONCILIATION';
export const PHYSICAL_RECONCILIATION_SOURCE = 'MANUAL_PHYSICAL_COUNT';
export const PHYSICAL_RECONCILIATION_CONFLICT =
  'Este estoque foi alterado enquanto você conferia. Atualize os dados e confirme novamente.';
export const PHYSICAL_RECONCILIATION_PENDING =
  'Existe uma movimentação de estoque em processamento. Aguarde a conclusão antes de corrigir o estoque.';
export const PHYSICAL_RECONCILIATION_COMBO =
  'Reconciliação física de estoque não está disponível para produtos combo.';

const STRUCTURES = new Set(['simple', 'variation', 'grade', 'no_control']);

function isMapLike(v) {
  return isMap(v);
}

/** Flatten canonical stock into cell list for audit. */
export function snapshotStockCells(stock) {
  const cells = [];
  if (!stock || stock.stockKind === 'simple') return cells;
  if (isMapLike(stock.variacoes) && Object.keys(stock.variacoes).length) {
    for (const [size, colors] of Object.entries(stock.variacoes)) {
      if (!isMapLike(colors)) continue;
      for (const [color, value] of Object.entries(colors)) {
        if (isMapLike(value)) {
          for (const [extra, q] of Object.entries(value)) {
            cells.push({
              size: String(size),
              color: String(color),
              extra: String(extra),
              quantity: quantity(cellTotal(q)),
            });
          }
        } else {
          cells.push({
            size: String(size),
            color: String(color),
            extra: '',
            quantity: quantity(value),
          });
        }
      }
    }
    return cells;
  }
  if (isMapLike(stock.estoquePorTamanho) && Object.keys(stock.estoquePorTamanho).length) {
    for (const [size, q] of Object.entries(stock.estoquePorTamanho)) {
      cells.push({size: String(size), color: 'sem-cor', extra: '', quantity: quantity(q)});
    }
  }
  if (isMapLike(stock.estoquePorCor) && Object.keys(stock.estoquePorCor).length) {
    for (const [color, q] of Object.entries(stock.estoquePorCor)) {
      cells.push({size: 'sem-tamanho', color: String(color), extra: '', quantity: quantity(q)});
    }
  }
  return cells;
}

export function parseReconciliation(raw) {
  if (!isMapLike(raw)) throw stockError('invalid-argument', 'reconciliation required');
  const allowed = [
    'physicalCountConfirmed', 'reason', 'operatorNote', 'productStructure',
    'activateStockControl', 'physicalQty', 'cells', 'NO_CONTROL_TO_CONTROLLED',
  ];
  for (const k of Object.keys(raw)) {
    if (!allowed.includes(k)) throw stockError('invalid-argument', 'Unknown reconciliation field');
  }
  if (raw.physicalCountConfirmed !== true) {
    throw stockError('invalid-argument', 'physicalCountConfirmed must be true');
  }
  if (typeof raw.reason !== 'string' || !raw.reason.trim()) {
    throw stockError('invalid-argument', 'reason required');
  }
  let productStructure = null;
  if ('productStructure' in raw) {
    const s = String(raw.productStructure || '').trim().toLowerCase();
    if (!STRUCTURES.has(s)) throw stockError('invalid-argument', 'Invalid productStructure');
    productStructure = s;
  }
  if (productStructure === 'no_control') {
    throw stockError(
      'failed-precondition',
      'NO_CONTROL não cria estoque controlado. Ative o controle de estoque e informe a contagem física.',
    );
  }
  let cells = null;
  if ('cells' in raw) {
    if (!Array.isArray(raw.cells) || raw.cells.length > 500) {
      throw stockError('invalid-argument', 'Invalid cells');
    }
    cells = raw.cells.map((cell, i) => {
      if (!isMapLike(cell)) throw stockError('invalid-argument', `Invalid cell at ${i}`);
      for (const k of Object.keys(cell)) {
        if (!['size', 'color', 'extra', 'quantity'].includes(k)) {
          throw stockError('invalid-argument', `Unknown cell field at ${i}`);
        }
      }
      if (!('quantity' in cell)) throw stockError('invalid-argument', `Cell quantity required at ${i}`);
      if (!('color' in cell) || typeof cell.color !== 'string') {
        throw stockError('invalid-argument', `Cell color identity required at ${i}`);
      }
      const size = typeof cell.size === 'string' ? cell.size : '';
      const color = cell.color;
      const extra = typeof cell.extra === 'string' ? cell.extra : '';
      return {size, color, extra, quantity: quantity(cell.quantity)};
    });
  }
  let physicalQty = null;
  if ('physicalQty' in raw) {
    physicalQty = quantity(raw.physicalQty);
  }
  return {
    physicalCountConfirmed: true,
    reason: raw.reason.trim(),
    operatorNote: typeof raw.operatorNote === 'string' ? raw.operatorNote.trim() : null,
    productStructure,
    activateStockControl: raw.activateStockControl === true,
    physicalQty,
    cells,
  };
}

/**
 * Resolve target stockKind without metadata inference.
 * @returns {'simple'|'variation'}
 */
export function resolveDeclaredStockKind({existingKind, productStructure, activateStockControl, legacyCompat}) {
  const existing = existingKind == null || existingKind === '' ? null : String(existingKind);
  if (existing === 'combo') {
    throw stockError('failed-precondition', PHYSICAL_RECONCILIATION_COMBO);
  }

  // NO_CONTROL store / missing kind: require explicit activate before establishing controlled stock.
  if (legacyCompat && !existing && !activateStockControl) {
    throw stockError(
      'failed-precondition',
      'Ative o controle de estoque antes de corrigir a contagem física.',
    );
  }

  if (productStructure === 'simple') return 'simple';
  if (productStructure === 'variation' || productStructure === 'grade') return 'variation';

  if (existing === 'simple' || existing === 'variation') return existing;

  // Null/missing stockKind: operator must declare structure.
  if (!productStructure) {
    throw stockError(
      'failed-precondition',
      'Estrutura de estoque não definida. Informe se o produto é simples, variação ou grade.',
    );
  }
  throw stockError('failed-precondition', 'Estrutura de estoque inválida para reconciliação física.');
}

/** Build absolute stock patch from physical count (no metadata inference). */
export function buildPhysicalStockDefinition(kind, recon) {
  if (kind === 'simple') {
    if (recon.physicalQty == null) {
      throw stockError('invalid-argument', 'physicalQty required for simple reconciliation');
    }
    // Reject total-only disguised as variation: simple must not send cells as authority.
    if (recon.cells != null && recon.cells.length > 0) {
      throw stockError('invalid-argument', 'Simple reconciliation cannot include variation cells');
    }
    return {
      stockKind: 'simple',
      quantidade: recon.physicalQty,
      variacoes: null,
      estoquePorTamanho: {},
      estoquePorCor: {},
      tamanhos: [],
      cores: [],
      tipoProduto: 'simples',
      itensCombo: [],
      comboConfig: null,
    };
  }

  if (recon.cells == null) {
    throw stockError('invalid-argument', 'cells required for variation/grade reconciliation');
  }
  if (recon.physicalQty != null) {
    throw stockError(
      'invalid-argument',
      'Não informe total agregado para variação/grade — reconcilie célula a célula.',
    );
  }

  const variacoes = Object.create(null);
  const tamanhos = new Set();
  const cores = new Set();
  for (const cell of recon.cells) {
    const size = cell.size.trim() || 'sem-tamanho';
    const color = cell.color.trim();
    if (!color) {
      throw stockError('invalid-argument', 'Cor da variação deve ser confirmada pelo operador');
    }
    const extra = (cell.extra || '').trim();
    tamanhos.add(size);
    cores.add(color);
    if (!variacoes[size]) variacoes[size] = Object.create(null);
    if (extra) {
      if (!isMapLike(variacoes[size][color]) && variacoes[size][color] !== undefined) {
        throw stockError('invalid-argument', 'Conflicting cell shape');
      }
      if (!isMapLike(variacoes[size][color])) variacoes[size][color] = Object.create(null);
      variacoes[size][color][extra] = cell.quantity;
    } else {
      if (isMapLike(variacoes[size][color])) {
        throw stockError('invalid-argument', 'Conflicting cell shape');
      }
      variacoes[size][color] = cell.quantity;
    }
  }

  return {
    stockKind: 'variation',
    quantidade: 0, // normalizeStock derives from cells
    variacoes,
    estoquePorTamanho: {},
    estoquePorCor: {},
    tamanhos: [...tamanhos],
    cores: [...cores].filter((c) => c !== 'sem-cor'),
    tipoProduto: 'variacao',
    itensCombo: [],
    comboConfig: null,
  };
}

/** Apply physical reconciliation onto a loaded record (mutates r.data). Returns audit blob. */
export function applyPhysicalReconciliation(r, recon, {legacyCompat}) {
  if (r.data.pendingSoftDelete) {
    throw stockError('failed-precondition', PHYSICAL_RECONCILIATION_PENDING);
  }
  if (r.data.stockKind === 'combo' || r.data.tipoProduto === 'combo' ||
      (Array.isArray(r.data.itensCombo) && r.data.itensCombo.length)) {
    throw stockError('failed-precondition', PHYSICAL_RECONCILIATION_COMBO);
  }

  const rawKind = Object.prototype.hasOwnProperty.call(r, 'rawStockKind')
    ? r.rawStockKind
    : r.data.stockKind; // may be null
  const declaredKind = resolveDeclaredStockKind({
    existingKind: rawKind,
    productStructure: recon.productStructure,
    activateStockControl: recon.activateStockControl,
    legacyCompat,
  });

  const beforeQty = r.physicalBefore
    ? quantity(r.physicalBefore.quantidade ?? 0)
    : quantity(r.data.quantidade ?? 0);
  const beforeCells = r.physicalBefore?.cells
    ? r.physicalBefore.cells
    : snapshotStockCells(r.data);
  const beforeRevision = r.originalRevision;

  const definition = buildPhysicalStockDefinition(declaredKind, recon);
  const candidate = {
    ...r.data,
    ...definition,
    stockKind: definition.stockKind,
    stockRevision: r.originalRevision,
  };
  // Strip combo leftovers when converting into controlled simple/variation.
  candidate.itensCombo = [];
  candidate.comboConfig = null;
  r.data = normalizeStock(candidate);

  const afterQty = quantity(r.data.quantidade ?? 0);
  const afterCells = snapshotStockCells(r.data);
  const noControlToControlled = Boolean(
    recon.activateStockControl ||
    ((rawKind == null || rawKind === '') && recon.productStructure),
  );

  return {
    type: PHYSICAL_RECONCILIATION_TYPE,
    source: PHYSICAL_RECONCILIATION_SOURCE,
    physicalCountConfirmed: true,
    beforeQty,
    afterQty,
    delta: afterQty - beforeQty,
    beforeCells,
    afterCells,
    beforeRevision,
    // afterRevision stamped later when stockRevision increments
    reason: recon.reason,
    operatorNote: recon.operatorNote,
    NO_CONTROL_TO_CONTROLLED: noControlToControlled || undefined,
    productStructure: recon.productStructure || declaredKind,
  };
}
