import 'dart:html' as html;

bool markOauthCallbackAttemptOnce(String key) {
  final k = 'mp_oauth_callback_done_$key';
  if (html.window.sessionStorage.containsKey(k)) {
    return false;
  }
  html.window.sessionStorage[k] = DateTime.now().toIso8601String();
  return true;
}
