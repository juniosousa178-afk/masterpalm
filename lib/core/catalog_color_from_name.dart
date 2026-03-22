// Mapeia nome de cor cadastrado (PT/EN, com ou sem acento) para exibição na bolinha do catálogo.
import 'package:flutter/material.dart';

/// Remove acentos para bater chaves como "lilás" → "lilas".
String normalizeCatalogColorKey(String raw) {
  var s = raw.trim().toLowerCase();
  const from =
      'àáâãäåèéêëìíîïòóôõöùúûüñçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÑÇ';
  const to =
      'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final idx = from.indexOf(ch);
    buf.write(idx >= 0 ? to[idx] : ch);
  }
  s = buf.toString();
  s = s.replaceAll(RegExp(r'[ßẞ]'), 'ss');
  s = s.replaceAll(RegExp(r'[_\-/]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

/// Corrige erros frequentes de digitação em nomes de cor (antes do lookup).
String _typoFixColorPhrase(String normalized) {
  var s = normalized;
  // "tumalina" (sem o R) → turmalina
  s = s.replaceAll('tumalina', 'turmalina');
  // erros comuns
  s = s.replaceAll('oseano', 'oceano');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

Color? _tryParseHexColor(String normalized) {
  var t = normalized.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 3) {
    final r = int.tryParse(t[0] + t[0], radix: 16);
    final g = int.tryParse(t[1] + t[1], radix: 16);
    final b = int.tryParse(t[2] + t[2], radix: 16);
    if (r != null && g != null && b != null) {
      return Color.fromARGB(255, r, g, b);
    }
  }
  if (t.length == 6 || t.length == 8) {
    final v = int.tryParse(t, radix: 16);
    if (v != null) {
      if (t.length == 8) return Color(v);
      return Color(0xFF000000 | v);
    }
  }
  return null;
}

/// Nomes sem acento; chaves sempre [normalizeCatalogColorKey].
final Map<String, Color> _kCatalogColors = {
  // Básicas PT / EN
  'preto': Colors.black,
  'black': Colors.black,
  'negro': Colors.black,
  'branco': Colors.white,
  'white': Colors.white,
  'blanco': Colors.white,
  'branca': Colors.white,
  'vermelho': Colors.red,
  'vermelha': Colors.red,
  'red': Colors.red,
  'azul': Colors.blue,
  'blue': Colors.blue,
  'verde': Colors.green,
  'green': Colors.green,
  'amarelo': Colors.yellow,
  'yellow': Colors.yellow,
  'rosa': Colors.pink,
  'pink': Colors.pink,
  'rose': const Color(0xFFFF66AA),
  'roxo': Colors.purple,
  'roxa': Colors.purple,
  'purple': Colors.purple,
  'violet': const Color(0xFF8B00FF),
  'violeta': Colors.purple,
  'laranja': Colors.orange,
  'orange': Colors.orange,
  'cinza': Colors.grey,
  'gray': Colors.grey,
  'grey': Colors.grey,
  'marrom': Colors.brown,
  'brown': Colors.brown,
  'bege': const Color(0xFFF5F5DC),
  'beige': const Color(0xFFF5F5DC),
  'dourado': const Color(0xFFFFD700),
  'gold': const Color(0xFFFFD700),
  'golden': const Color(0xFFFFD700),
  'prata': const Color(0xFFC0C0C0),
  'silver': const Color(0xFFC0C0C0),
  'navy': const Color(0xFF000080),
  'vinho': const Color(0xFF722F37),
  'bordo': const Color(0xFF800020),
  'burgundy': const Color(0xFF800020),
  'burgundy red': const Color(0xFF800020),
  'coral': const Color(0xFFFF7F50),
  'turquesa': const Color(0xFF40E0D0),
  'turquoise': const Color(0xFF40E0D0),
  'lilas': const Color(0xFFC8A2C8),
  'lilac': const Color(0xFFC8A2C8),
  'lavender': const Color(0xFFE6E6FA),
  'lavanda': const Color(0xFFE6E6FA),
  'nude': const Color(0xFFE3BC9A),
  'off white': const Color(0xFFFAF9F6),
  'offwhite': const Color(0xFFFAF9F6),
  'creme': const Color(0xFFFFFDD0),
  'cream': const Color(0xFFFFFDD0),
  'caramelo': const Color(0xFFFFD59A),
  'caramel': const Color(0xFFFFD59A),
  'mostarda': const Color(0xFFFFDB58),
  'mustard': const Color(0xFFFFDB58),
  'terracota': const Color(0xFFE2725B),
  'terracotta': const Color(0xFFE2725B),
  'ferrugem': const Color(0xFFB7410E),
  'rust': const Color(0xFFB7410E),
  'magenta': const Color(0xFFFF00FF),
  'fucsia': const Color(0xFFFF00FF),
  'fuchsia': const Color(0xFFFF00FF),
  'salmao': const Color(0xFFFA8072),
  'salmon': const Color(0xFFFA8072),
  'pessego': const Color(0xFFFFDAB9),
  'peach': const Color(0xFFFFDAB9),
  'menta': const Color(0xFF98FF98),
  'mint': const Color(0xFF98FF98),
  'caqui': const Color(0xFFC3B091),
  'khaki': const Color(0xFFC3B091),
  'petroleo': const Color(0xFF004953),
  'petroleum': const Color(0xFF004953),
  'champagne': const Color(0xFFF7E7CE),
  // Cristal / translúcido (referência clara, não cinza uniforme)
  'cristal': const Color(0xFFE8EDF5),
  'crystal': const Color(0xFFE8EDF5),
  'cristalino': const Color(0xFFE8EDF5),
  'transparente': const Color(0xFFE8EDF5),
  // Turmalina / tons verdes específicos
  'turmalina': const Color(0xFF0F766E),
  'tourmaline': const Color(0xFF0F766E),
  'verde turmalina': const Color(0xFF0F766E),
  'turmalina verde': const Color(0xFF0F766E),
  'green tourmaline': const Color(0xFF0F766E),
  'tourmaline green': const Color(0xFF0F766E),
  'esmeralda': const Color(0xFF50C878),
  'emerald': const Color(0xFF50C878),
  'jade': const Color(0xFF00A86B),
  'oliva': const Color(0xFF808000),
  'olive': const Color(0xFF808000),
  'lima': const Color(0xFF32CD32),
  'lime': const Color(0xFF32CD32),
  'azul marinho': const Color(0xFF000080),
  'midnight blue': const Color(0xFF191970),
  'azul celeste': const Color(0xFF87CEEB),
  'azul ceu': const Color(0xFF87CEEB),
  'sky blue': const Color(0xFF87CEEB),
  'baby blue': const Color(0xFF89CFF0),
  'azul bebe': const Color(0xFF89CFF0),
  'azul baby': const Color(0xFF89CFF0),
  'bebe azul': const Color(0xFF89CFF0),
  'azul claro': const Color(0xFFADD8E6),
  'light blue': const Color(0xFFADD8E6),
  'azul pastel': const Color(0xFFAEC6CF),
  'pastel blue': const Color(0xFFAEC6CF),
  'azul acinzentado': const Color(0xFF6699CC),
  'azul aco': const Color(0xFF6C7A89),
  'steel blue': const Color(0xFF4682B4),
  'azul aco escuro': const Color(0xFF4A5568),
  'azul royal': const Color(0xFF4169E1),
  'royal blue': const Color(0xFF4169E1),
  'azul tiffany': const Color(0xFF81D8D0),
  'tiffany blue': const Color(0xFF81D8D0),
  'azul safira': const Color(0xFF0F52BA),
  'sapphire': const Color(0xFF0F52BA),
  'safira': const Color(0xFF0F52BA),
  'azul cobalto': const Color(0xFF0047AB),
  'cobalt blue': const Color(0xFF0047AB),
  'cobalto': const Color(0xFF0047AB),
  'azul bic': const Color(0xFF003399),
  'indigo': const Color(0xFF4B0082),
  'anil': const Color(0xFF4B0082),
  // Oceano / mar
  'oceano': const Color(0xFF1B6B93),
  'ocean': const Color(0xFF1B6B93),
  'ocean blue': const Color(0xFF1B6B93),
  'ocean green': const Color(0xFF2A9D8F),
  'azul oceano': const Color(0xFF1B6B93),
  'azul ocean': const Color(0xFF1B6B93),
  'verde oceano': const Color(0xFF2A9D8F),
  'verde mar': const Color(0xFF2E8B57),
  'sea green': const Color(0xFF2E8B57),
  'verde agua': const Color(0xFF66CDAA),
  'agua marinha': const Color(0xFF7FFFD4),
  'aquamarine': const Color(0xFF7FFFD4),
  'aqua': const Color(0xFF00FFFF),
  'azul mar': const Color(0xFF006994),
  'blue sea': const Color(0xFF006994),
  'marine': const Color(0xFF004953),
  'marinho': const Color(0xFF000080),
  // Verdes compostos
  'verde musgo': const Color(0xFF8A9A5B),
  'moss green': const Color(0xFF8A9A5B),
  'verde militar': const Color(0xFF4B5320),
  'olive drab': const Color(0xFF6B8E23),
  'verde neon': const Color(0xFF39FF14),
  'neon green': const Color(0xFF39FF14),
  'verde pistache': const Color(0xFF93C572),
  'pistachio': const Color(0xFF93C572),
  'verde floresta': const Color(0xFF228B22),
  'forest green': const Color(0xFF228B22),
  'verde escuro': const Color(0xFF006400),
  'dark green': const Color(0xFF006400),
  'verde claro': const Color(0xFF90EE90),
  'light green': const Color(0xFF90EE90),
  'verde menta': const Color(0xFF98FF98),
  'verde abacate': const Color(0xFF568203),
  'avocado': const Color(0xFF568203),
  'verde eucalipto': const Color(0xFF44A08D),
  'eucalyptus': const Color(0xFF44A08D),
  // Turmalina — variações (incl. ordem invertida)
  'turmalina azul': const Color(0xFF0E7490),
  'azul turmalina': const Color(0xFF0E7490),
  'blue tourmaline': const Color(0xFF0E7490),
  'turmalina rosa': const Color(0xFFE879A9),
  'rosa turmalina': const Color(0xFFE879A9),
  'pink tourmaline': const Color(0xFFE879A9),
  'turmalina paraiba': const Color(0xFF00D4AA),
  'paraiba': const Color(0xFF00D4AA),
  'turmalina verde oceano': const Color(0xFF0D9488),
  'verde oceano turmalina': const Color(0xFF0D9488),
  'turmalina verde agua': const Color(0xFF14B8A6),
  'verde turmalina oceano': const Color(0xFF0D9488),
  // Rosas / vermelhos compostos
  'rosa bebe': const Color(0xFFF4C2C2),
  'baby pink': const Color(0xFFF4C2C2),
  'rosa antigo': const Color(0xFFB76E79),
  'dusty rose': const Color(0xFFB76E79),
  'rosa chiclete': const Color(0xFFFF69B4),
  'hot pink': const Color(0xFFFF69B4),
  'rosa queimado': const Color(0xFFC08081),
  'vermelho escuro': const Color(0xFF8B0000),
  'dark red': const Color(0xFF8B0000),
  // Amarelos / laranjas
  'amarelo canario': const Color(0xFFFFEF00),
  'canario': const Color(0xFFFFEF00),
  'amarelo ouro': const Color(0xFFFFD700),
  'dourado velho': const Color(0xFFC5A059),
  'ouro velho': const Color(0xFFC5A059),
  // Marrons / neutros
  'marrom chocolate': const Color(0xFF7B3F00),
  'chocolate': const Color(0xFF7B3F00),
  'marrom cafe': const Color(0xFF6F4E37),
  'coffee': const Color(0xFF6F4E37),
  'cafe': const Color(0xFF6F4E37),
  'cinza escuro': const Color(0xFFA9A9A9),
  'dark gray': const Color(0xFFA9A9A9),
  'cinza claro': const Color(0xFFD3D3D3),
  'light gray': const Color(0xFFD3D3D3),
  'cinza mescla': const Color(0xFF9E9E9E),
  'off black': const Color(0xFF1A1A1A),
  // Metálicos / neon genéricos
  'neon pink': const Color(0xFFFF6EC7),
  'neon azul': const Color(0xFF1E90FF),
  'neon laranja': const Color(0xFFFF4500),
  'metalico': const Color(0xFFA8A9AD),
  'metalico prata': const Color(0xFFC0C0C0),
  'metalico dourado': const Color(0xFFD4AF37),
  'rose gold': const Color(0xFFB76E79),
  'ouro rosado': const Color(0xFFB76E79),
  'grafite': const Color(0xFF41424A),
  'graphite': const Color(0xFF41424A),
  'chumbo': const Color(0xFF43464B),
  'perola': const Color(0xFFFDEEF4),
  'pearl': const Color(0xFFFDEEF4),
};

/// Se o texto contém uma chave cadastrada (ex.: "turmalina verde oceano" contém a frase completa).
Color? _longestCatalogKeyContainedIn(String n) {
  if (n.length < 4) return null;
  final keys = _kCatalogColors.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (k.length < 6) continue;
    if (n.contains(k)) return _kCatalogColors[k];
  }
  return null;
}

/// Cor da bolinha a partir do texto cadastrado (português ou inglês, com acento ou não).
Color catalogColorFromName(String raw) {
  if (raw.trim().isEmpty) return Colors.grey;

  var n = normalizeCatalogColorKey(raw);
  n = _typoFixColorPhrase(n);

  final hex = _tryParseHexColor(n);
  if (hex != null) return hex;

  final direct = _kCatalogColors[n];
  if (direct != null) return direct;

  // Frases compostas: tenta todas as junções de tokens (ex.: "verde turmalina").
  final parts = n.split(' ').where((e) => e.isNotEmpty).toList();
  if (parts.length > 1) {
    for (var len = parts.length; len >= 2; len--) {
      for (var start = 0; start + len <= parts.length; start++) {
        final phrase = parts.sublist(start, start + len).join(' ');
        final c = _kCatalogColors[phrase];
        if (c != null) return c;
      }
    }
  }

  // Palavra a palavra (última costuma ser mais específica: "turmalina").
  for (var i = parts.length - 1; i >= 0; i--) {
    final c = _kCatalogColors[parts[i]];
    if (c != null) return c;
  }

  final fuzzy = _longestCatalogKeyContainedIn(n);
  if (fuzzy != null) return fuzzy;

  return Colors.grey;
}
