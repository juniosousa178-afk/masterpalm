// lib/utils/instagram_launcher.dart
// Utilitário para abrir perfil do Instagram no app nativo (Android/iOS).

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';

/// Extrai o username do Instagram de uma URL ou string (@user, user, https://instagram.com/user).
String extractInstagramUsername(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('@')) {
    return trimmed.substring(1).split(RegExp(r'[\s/]')).first.trim();
  }
  final match = RegExp(
    r'(?:https?://)?(?:www\.)?instagram\.com/([a-zA-Z0-9_.]+)',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match != null) return match.group(1) ?? '';
  return trimmed.split(RegExp(r'[\s/]')).first.trim();
}

/// Verifica se é um path reservado do Instagram (explore, reel, etc).
bool isInstagramReservedPath(String path) {
  const reserved = ['explore', 'reel', 'reels', 'p', 'stories', 'direct', 'accounts'];
  return reserved.contains(path.toLowerCase());
}

/// Tenta abrir o perfil do Instagram no app nativo.
/// Retorna true se abriu no app, false para fallback (abrir no browser).
Future<bool> openInstagramInApp(String urlOrUsername) async {
  if (kIsWeb) return false;

  final username = extractInstagramUsername(urlOrUsername);
  if (username.isEmpty) return false;
  if (isInstagramReservedPath(username)) return false;

  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

  if (isAndroid) {
    // 1) AndroidIntent com _u (formato nativo)
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: 'https://www.instagram.com/_u/$username',
        package: 'com.instagram.android',
      );
      await intent.launch();
      return true;
    } catch (_) {
      // 2) Fallback: intent URL
      try {
        final webUrl = 'https://www.instagram.com/$username/';
        final intentUrl =
            'intent://www.instagram.com/$username/#Intent;scheme=https;package=com.instagram.android;S.browser_fallback_url=${Uri.encodeComponent(webUrl)};end';
        final uri = Uri.parse(intentUrl);
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {}
    }
  } else if (isIOS) {
    final nativeUri = Uri.parse('instagram://user?username=$username');
    if (await canLaunchUrl(nativeUri)) {
      if (await launchUrl(nativeUri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    }
  }

  return false;
}
