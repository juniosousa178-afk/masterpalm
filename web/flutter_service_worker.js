/**
 * Stub de Service Worker — MasterPalm Web com `--pwa-strategy=none`.
 *
 * Motivo: sem este ficheiro estático, o Firebase Hosting aplica o rewrite SPA
 * (`**` → /index.html) e o URL `flutter_service_worker.js` devolvia HTML,
 * quebrando clientes com SW antigo e gerando erros de MIME / Unexpected token '<'.
 *
 * Este script não implementa cache offline: apenas pass-through à rede.
 * O registo de SW é evitado pelo bootstrap (ver web/flutter_bootstrap.js).
 * Utilizadores com SW legado podem receber este stub após deploy e deixar
 * de servir shell/cache antigo; a limpeza em index.html desregista SW por buildId.
 */
self.addEventListener('install', function (event) {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', function (event) {
  event.respondWith(fetch(event.request));
});
