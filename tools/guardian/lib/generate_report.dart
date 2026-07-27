import 'dart:convert';

import 'models/guardian_result.dart';

class ReportGenerator {
  static String toMarkdown(GuardianResult result) {
    final buf = StringBuffer();
    buf.writeln('# Guardian Report\n');
    buf.writeln('## Resumo\n');
    buf.writeln(result.summary);
    buf.writeln('\n**Decisão:** `${result.decision.name.toUpperCase()}`');
    buf.writeln('**Modo simulação:** ${result.simulationOnly}\n');

    buf.writeln('## Arquivos alterados\n');
    buf.writeln('### Adicionados');
    for (final f in result.filesAdded) buf.writeln('- `$f`');
    buf.writeln('\n### Modificados');
    for (final f in result.filesModified) buf.writeln('- `$f`');
    buf.writeln('\n### Removidos');
    for (final f in result.filesRemoved) buf.writeln('- `$f`');

    buf.writeln('\n## Métodos alterados\n');
    for (final m in result.methodsChanged.take(50)) buf.writeln('- `$m`');

    buf.writeln('\n## Classes alteradas\n');
    for (final c in result.classesChanged.take(30)) buf.writeln('- `$c`');

    buf.writeln('\n## Áreas impactadas\n');
    for (final d in result.impact.domains) buf.writeln('- $d');

    buf.writeln('\n## Dependências afetadas\n');
    buf.writeln('### Serviços');
    for (final s in result.impact.services) buf.writeln('- `$s`');
    buf.writeln('\n### Telas');
    for (final s in result.impact.screens.take(20)) buf.writeln('- `$s`');

    buf.writeln('\n## Collections Firestore\n');
    for (final c in result.impact.firestoreCollections) buf.writeln('- `$c`');

    buf.writeln('\n## Boxes Hive\n');
    for (final b in result.impact.hiveBoxes) buf.writeln('- `$b`');

    buf.writeln('\n## Risco por item\n');
    buf.writeln('| Ficheiro | Nível | Motivo |');
    buf.writeln('|----------|-------|--------|');
    for (final item in result.risk.items) {
      buf.writeln('| `${item.file}` | ${item.level.name} | ${item.reason} |');
    }

    buf.writeln('\n## Violações de regras\n');
    for (final v in result.violations) {
      buf.writeln('### ${v.code} — ${v.severity.name}');
      buf.writeln('- **Mensagem:** ${v.message}');
      if (v.file != null) buf.writeln('- **Ficheiro:** `${v.file}`');
      if (v.method != null) buf.writeln('- **Método:** `${v.method}`');
      if (v.evidence != null) buf.writeln('- **Evidência:** ${v.evidence}');
      if (v.requiredAction != null) {
        buf.writeln('- **Ação:** ${v.requiredAction}');
      }
      buf.writeln('');
    }

    buf.writeln('## Testes obrigatórios\n');
    for (final t in result.requiredTests) buf.writeln('- `$t`');

    buf.writeln('\n## Testes encontrados\n');
    for (final t in result.foundTests.take(30)) buf.writeln('- `$t`');

    buf.writeln('\n## Testes ausentes\n');
    if (result.missingTests.isEmpty) {
      buf.writeln('- Nenhum ausente identificado');
    } else {
      for (final t in result.missingTests) buf.writeln('- `$t`');
    }

    buf.writeln('\n## Documentação obrigatória\n');
    for (final d in result.requiredDocumentation) buf.writeln('- `$d`');

    buf.writeln('\n## Recomendações\n');
    for (final r in result.recommendations) buf.writeln('- $r');

    buf.writeln('\n## Decisão\n');
    buf.writeln('**${result.decision.name.toUpperCase()}**');
    return buf.toString();
  }

  static String toJson(GuardianResult result) {
    return const JsonEncoder.withIndent('  ').convert(result.toJson());
  }
}
