// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

String? catalogDomainBrowserStorageGet(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void catalogDomainBrowserStorageSet(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {}
}

void catalogDomainBrowserStorageRemove(String key) {
  try {
    html.window.localStorage.remove(key);
  } catch (_) {}
}
