/**
 * Business-output parity: the identical consignment lifecycle run on this repository's source and on each source
 * root in CONSIGNMENT_PARITY_SRC (path-delimiter separated, e.g. an unpacked deployed artifact's src). Everything
 * except the category fields of draft_produtos/produtos must match: command results, every document (stock, sales,
 * finance, consignments, operations, audit), the write set of every step and the protocol limits.
 * Skipped when CONSIGNMENT_PARITY_SRC is not set.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import {delimiter, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {
  CATEGORY_KEYS, businessView, diffBusinessViews, loadConsignmentSource, runConsignmentLifecycle,
} from './consignment-category-lifecycle.mjs';

const SRC = fileURLToPath(new URL('../src/', import.meta.url));
const roots = (process.env.CONSIGNMENT_PARITY_SRC || '').split(delimiter).filter(Boolean);
const LIMITS = ['MAX_DISTINCT_PRODUCTS_PER_CONSIGNMENT', 'MAX_LINES', 'MAX_STOCK_RECORDS_PER_TRANSACTION',
  'MAX_TRANSACTION_WRITE_UNITS', 'MAX_CONSIGNMENT_DOC_BYTES', 'MAX_SETTLEMENT_COMMAND_BYTES', 'MAX_COMMAND_BYTES',
  'WRITE_UNITS_PER_STOCK_RECORD'];

const opsOf = (run, i) => run.db.commits
  .slice(i ? run.steps[i - 1].commitsSoFar : 0, run.steps[i].commitsSoFar)
  .map(c => c.ops.map(o => `${o.type} ${o.path}`));

for (const root of roots) {
  test(`business output equals ${root}`, async () => {
    const candidate = await runConsignmentLifecycle(await loadConsignmentSource(SRC));
    const reference = await runConsignmentLifecycle(await loadConsignmentSource(root));
    assert.deepEqual(reference.steps.map(s => s.name), candidate.steps.map(s => s.name));
    let diffs = 0;
    let categoryDocsDiffering = 0;
    candidate.steps.forEach((step, i) => {
      const ref = reference.steps[i];
      if (JSON.stringify(ref.result) !== JSON.stringify(step.result)) {
        diffs++;
        console.log(`RESULT_DIFF step=${step.name}`);
      }
      const fieldDiffs = diffBusinessViews(businessView(ref.snapshot), businessView(step.snapshot));
      for (const d of fieldDiffs) console.log(`DOC_DIFF step=${step.name} ${d.path} ${d.key}`);
      diffs += fieldDiffs.length;
      if (JSON.stringify(opsOf(reference, i)) !== JSON.stringify(opsOf(candidate, i))) {
        diffs++;
        console.log(`WRITE_SET_DIFF step=${step.name}`);
      }
      for (const [path, data] of step.snapshot) {
        if (!/\/(draft_produtos|produtos)\//.test(path)) continue;
        const pick = d => JSON.stringify(CATEGORY_KEYS.map(k => d?.[k]));
        if (pick(data) !== pick(ref.snapshot.get(path))) categoryDocsDiffering++;
      }
    });
    const [refProtocol, candProtocol] = await Promise.all([root, SRC].map(r =>
      import(pathToFileURL(join(r, 'consignmentProtocol.js')).href)));
    for (const k of LIMITS) assert.deepEqual(candProtocol[k], refProtocol[k], k);
    const added = candProtocol.OPERATIONS.filter(op => !refProtocol.OPERATIONS.includes(op));
    assert.deepEqual(refProtocol.OPERATIONS.filter(op => !candProtocol.OPERATIONS.includes(op)), [], 'no operation removed');
    console.log(`OPERATIONS_ADDED_VS_REFERENCE=${JSON.stringify(added)}`);
    console.log(`CONSIGNMENT_BUSINESS_OUTPUT_DIFF=${diffs} CATEGORY_ONLY_DOC_DIFFERENCES=${categoryDocsDiffering}`);
    assert.equal(diffs, 0);
  });
}
