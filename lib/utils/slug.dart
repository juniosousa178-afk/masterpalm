// lib/utils/slug.dart
String slugify(String input) {
  var s = input.trim().toLowerCase();

  // remove acentos simples
  const accents = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const without = 'aaaaaaceeeeiiiinooooouuuuyy';
  for (var i = 0; i < accents.length; i++) {
    s = s.replaceAll(accents[i], without[i]);
  }

  // troca espaços e separadores por hífen
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  // remove hífens duplicados e bordas
  s = s.replaceAll(RegExp(r'-{2,}'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');

  // fallback
  if (s.isEmpty) s = 'minha-loja';
  return s;
}
