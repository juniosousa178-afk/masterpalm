// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void publishCatStartTrace(List<Map<String, Object?>> events) {
  js.context['__CAT_START_TRACE__'] = js.JsObject.jsify(events);
}

void publishCatStartSummary(Map<String, Object?> summary) {
  js.context['__CAT_START_SUMMARY__'] = js.JsObject.jsify(summary);
}
