// lib/utils/dev_bootstrap.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Prepara dados iniciais no modo desenvolvedor (seed)
Future<void> seedDev() async {
  if (!kDebugMode) return;
  final db = FirebaseFirestore.instance;
  await db.collection('debug').doc('status').set({
    'createdAt': DateTime.now().toIso8601String(),
    'env': 'development',
  });
  debugPrint('✅ seedDev executado com sucesso');
}
