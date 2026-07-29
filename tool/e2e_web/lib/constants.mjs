/** Constantes compartilhadas — Web UI E2E R8.4.38 */

export const PROJECT_ID = 'masterpalm-r8433-web-e2e-local';
export const PRODUCTION_PROJECT_ID = 'masterpalm-58c46';

export const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
export const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';

export const LOJA_ID = 'loja-r8438-qa';
export const USER_EMAIL = 'usuario-r8438-qa@masterpalm-e2e.local';
export const USER_PASSWORD = 'E2eTestR8438!Seguro';
export const USER_DISPLAY = 'usuario-r8438-qa';
export const CLIENTE_ID = 'cliente-r8438-sintetico';

export const PROD_SIMPLES_ID = 'prod-r8438-simples';
export const PROD_SIMPLES_NOME = 'Produto Simples QA';
export const PROD_VAR_ID = 'prod-r8438-variacoes';
export const PROD_VAR_NOME = 'Produto Variacoes QA';

export const PROD_REVENDA_IDS = [
  'prod-revenda-r8438-1',
  'prod-revenda-r8438-2',
  'prod-revenda-r8438-3',
];
export const PROD_REVENDA_NOMES = [
  'Peca Revenda QA 1',
  'Peca Revenda QA 2',
  'Peca Revenda QA 3',
];

export const PEDIDO_REVENDA_VAZIO_ID = 'pedido-revenda-r8438-vazio';
export const FORNECEDOR_ID = 'fornecedor-r8438-qa';

export const WAIT_1_MS = Number(process.env.E2E_STOCK_WAIT_1_MS || 60_000);
export const WAIT_5_MS = Number(process.env.E2E_STOCK_WAIT_5_MS || 300_000);

export const QA_BUILD_DIR = process.env.R8438_UI_BUILD_DIR || 'build/web-qa-e2e';
export const QA_SERVE_PORT = Number(process.env.R8438_UI_PORT || 8793);

export const BLOCKED_HOST_PATTERNS = [
  'masterpalm-58c46',
  'app.mastepalm.com.br',
  'masterpalm-58c46.firebaseio.com',
  'southamerica-east1-masterpalm-58c46.cloudfunctions.net',
];
