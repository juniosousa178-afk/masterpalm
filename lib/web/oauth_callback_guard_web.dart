// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:crypto/crypto.dart';

/// [key] (o state OAuth) nunca é gravado: só o SHA-256 entra no sessionStorage.
bool markOauthCallbackAttemptOnce(String key) {
  final k = 'mp_oauth_callback_done_${sha256.convert(utf8.encode(key))}';
  if (html.window.sessionStorage.containsKey(k)) {
    return false;
  }
  html.window.sessionStorage[k] = DateTime.now().toIso8601String();
  return true;
}
