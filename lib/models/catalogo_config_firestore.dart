// lib/models/catalogo_config_firestore.dart
import 'package:flutter/material.dart';
import 'catalogo_config.dart';

/// Converte o CatalogoConfig (Hive) para Map do Firestore
extension CatalogoConfigFirestore on CatalogoConfig {
  Map<String, dynamic> toFirestore() {
    return {
      'corFundo': corFundo,
      'corTexto': corTexto,
      'corBotao': corBotao,
      'fonte': fonte,
      'tamanhoFonte': tamanhoFonte,
      'corCabecalho': corCabecalho,
    };
  }
}

/// Cria um CatalogoConfig a partir do Map do Firestore
CatalogoConfig catalogoConfigFromFirestore(Map<String, dynamic> data) {
  return CatalogoConfig(
    corFundo: data['corFundo'] as String? ?? '#000000',
    corTexto: data['corTexto'] as String? ?? '#FFFFFF',
    corBotao: data['corBotao'] as String? ?? '#FFD600',
    fonte: data['fonte'] as String? ?? 'Roboto',
    tamanhoFonte: (data['tamanhoFonte'] as num?)?.toDouble() ?? 14.0,
    corCabecalho: data['corCabecalho'] as String? ?? '',
  );
}

/// Helper pra transformar String '#000000' ou '0xFF000000' em Color
Color colorFromHex(String value, {Color fallback = Colors.black}) {
  var v = value.trim();
  if (v.isEmpty) return fallback;

  if (v.startsWith('#')) v = v.substring(1);
  if (v.length == 6) v = 'FF$v'; // adiciona alpha se vier só RGB

  try {
    final intVal = int.parse(v, radix: 16);
    return Color(intVal);
  } catch (_) {
    return fallback;
  }
}
