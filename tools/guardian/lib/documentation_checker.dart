import 'models/impact_result.dart';
import 'guardian_config.dart';

class DocumentationChecker {
  DocumentationChecker({required this.config});

  final GuardianConfig config;

  List<String> requiredDocs(ImpactResult impact, List<String> changedPaths) {
    final docs = <String>{};

    final onlyDocs = changedPaths.isNotEmpty &&
        changedPaths.every((p) => p.startsWith('docs/'));

    if (onlyDocs) return [];

    for (final domain in impact.domains) {
      final triggers = config.documentationMatrix[domain] ?? [];
      docs.addAll(triggers);
    }

    if (impact.domains.contains('Estoque') ||
        impact.domains.contains('PDV') ||
        impact.domains.contains('Venda')) {
      docs.add('docs/knowledge/flows/venda.md');
      docs.add('docs/intelligence/EVENT_MAP.md');
      docs.add('docs/intelligence/CHANGE_IMPACT.md');
    }

    if (impact.domains.contains('Sync') || impact.domains.contains('Offline')) {
      docs.add('docs/knowledge/flows/sync.md');
      docs.add('docs/intelligence/TRANSACTION_MAP.md');
    }

    if (impact.domains.contains('Financeiro') ||
        impact.domains.contains('Fiado')) {
      docs.add('docs/knowledge/flows/financeiro.md');
      docs.add('docs/knowledge/flows/consignado-fiado.md');
    }

    if (impact.domains.contains('Tenant')) {
      docs.add('docs/intelligence/security/SECURITY_MAP.md');
      docs.add('docs/engineering/RCA/RCA-001-Thawana-LastWriteWins.md');
    }

    final hasArchChange = changedPaths.any(
      (p) =>
          p.contains('lib/services/') &&
          (p.contains('vendas_service') ||
              p.contains('estoque_transaction') ||
              p.contains('store_resolver')),
    );
    if (hasArchChange) {
      docs.add('docs/knowledge/INDEX.md');
      docs.add('docs/intelligence/INDEX.md');
    }

    return docs.toList()..sort();
  }
}
