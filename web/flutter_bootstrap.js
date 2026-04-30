// Bootstrap explícito sem Service Worker: evita registo a um flutter_service_worker.js
// inexistente (Hosting devolvia index.html e o browser reportava MIME text/html).
// Placeholders processados por `flutter build web` (ver flutter_tools web_templated_files).
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();
