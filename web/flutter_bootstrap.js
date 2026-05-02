// Bootstrap explícito sem Service Worker: usar `flutter build web --pwa-strategy=none`.
// Não passar serviceWorkerSettings — evita SW antigo e index.html no URL do worker (MIME/HTML).
// web/flutter_service_worker.js (stub) existe só para o Hosting servir JS real se o URL for pedido.
// Placeholders processados por `flutter build web` (ver flutter_tools web_templated_files).
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();
