/** Constantes compartilhadas — Web UI E2E R8.4.39 */

export const PROJECT_ID = 'masterpalm-r8433-web-e2e-local';
export const PRODUCTION_PROJECT_ID = 'masterpalm-58c46';

export const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8180';
export const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9199';

export const LOJA_ID = 'loja-r8439-qa';
export const USER_EMAIL = 'usuario-r8439-qa@masterpalm-e2e.local';
export const USER_PASSWORD = 'E2eTestR8439!Seguro';
export const USER_DISPLAY = 'usuario-r8439-qa';
export const EMPRESA_NOME = 'Empresa QA R8439';
export const CLIENTE_ID = 'cliente-r8439-sintetico';

export const PROD_SIMPLES_ID = 'prod-r8439-simples';
export const PROD_SIMPLES_NOME = 'Produto Simples QA';
export const PROD_VAR_ID = 'prod-r8439-variacoes';
export const PROD_VAR_NOME = 'Produto Variacoes QA';

export const PROD_REVENDA_IDS = [
  'prod-revenda-r8439-1',
  'prod-revenda-r8439-2',
  'prod-revenda-r8439-3',
];
export const PROD_REVENDA_NOMES = [
  'Peca Revenda QA 1',
  'Peca Revenda QA 2',
  'Peca Revenda QA 3',
];

export const PEDIDO_REVENDA_VAZIO_ID = 'pedido-revenda-r8439-vazio';
export const FORNECEDOR_ID = 'fornecedor-r8439-qa';
export const PEDIDO_REVENDA_CONTRACT_ID = 'pedido-revenda-r8439-contract';

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

/** Allowlist mínima documentada — não bloqueia o teste. */
export const NETWORK_ALLOWLIST = [
  {
    id: 'google-signin-headless-403',
    pattern: /accounts\.google\.com|gsi\/client|googleapis\.com\/auth/,
    reason: 'Google Sign-In não é usado no login por e-mail; 403 headless é conhecido e não bloqueante.',
    statuses: [403, 404],
  },
];
