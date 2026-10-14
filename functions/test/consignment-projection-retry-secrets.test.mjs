/** consignmentProjectionRetry must not inherit the global Mercado Pago secrets (least privilege). */
import test from 'node:test';
import assert from 'node:assert/strict';

process.env.GCLOUD_PROJECT ||= 'masterpalm-58c46';
const fns = await import('../index.js');
const secretsOf = name => (fns[name].__endpoint.secretEnvironmentVariables ?? []).map(s => s.key);

test('consignmentProjectionRetry deploy manifest has no secrets; consignmentCommand keeps its own', () => {
  assert.deepEqual(secretsOf('consignmentProjectionRetry'), []);
  assert.deepEqual(secretsOf('consignmentCommand').sort(), ['MP_ACCESS_TOKEN', 'WEB_BASE_URL']);
});
