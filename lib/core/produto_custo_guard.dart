// Regras conservadoras para não alterar Produto.custoReal em sync/import automáticos.

import 'logger.dart';
import '../models/produto.dart';

/// Metadados de custo numa linha de importação (planilha/CSV).
class ImportCustoInput {
  /// `false` = coluna `custo` ausente no cabeçalho/mapeamento.
  final bool colunaPresente;

  /// `null` = ausente, célula vazia ou valor inválido (não numérico).
  /// Inclui `0.0` quando o usuário digitou zero explicitamente.
  final double? valorExplicito;

  const ImportCustoInput({
    required this.colunaPresente,
    this.valorExplicito,
  });

  static const ImportCustoInput colunaAusente =
      ImportCustoInput(colunaPresente: false);

  /// Interpreta a coluna `custo` (ou [custoKey]) numa linha importada.
  static ImportCustoInput fromRowMap(
    Map<String, dynamic> row, {
    String custoKey = 'custo',
  }) {
    if (!row.containsKey(custoKey)) {
      return colunaAusente;
    }
    final raw = row[custoKey];
    if (raw == null) {
      return const ImportCustoInput(colunaPresente: true);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) {
      return const ImportCustoInput(colunaPresente: true);
    }
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || !v.isFinite) {
      return const ImportCustoInput(colunaPresente: true);
    }
    return ImportCustoInput(colunaPresente: true, valorExplicito: v);
  }

  bool get temValorExplicito => valorExplicito != null;
}

class ProdutoCustoGuard {
  ProdutoCustoGuard._();

  static const double _eps = 1e-9;

  /// Cadastro manual ou legado com custo positivo sem flag explícita.
  static bool isCustoLocalProtegido(Produto local) {
    if (local.custoEditadoNoCadastro) return true;
    if (local.custoReal > _eps) return true;
    return false;
  }

  /// Lê `custoReal` remoto; ausente/inválido → `null` (desconhecido, não zero).
  static double? parseRemoteCusto(Map<String, dynamic> data) {
    if (!data.containsKey('custoReal')) return null;
    final v = data['custoReal'];
    if (v == null) return null;
    if (v is num) {
      if (!v.isFinite) return null;
      return v.toDouble();
    }
    return null;
  }

  /// Remoto indica custo zerado de forma intencional (cadastro com flag).
  static bool remoteIndicaCustoZeradoExplicitamente(Map<String, dynamic> data) {
    if (data['custoEditadoNoCadastro'] != true) return false;
    if (!data.containsKey('custoReal')) return false;
    final c = parseRemoteCusto(data);
    return c != null && c.abs() <= _eps;
  }

  /// Custo a aplicar no pull/full-sync, ou `null` para manter o local.
  static double? resolveCustoAfterRemotePull({
    required Produto local,
    required Map<String, dynamic> remoteData,
  }) {
    final localCusto = local.custoReal;
    final remoteCusto = parseRemoteCusto(remoteData);

    if (remoteCusto != null &&
        remoteIndicaCustoZeradoExplicitamente(remoteData)) {
      return 0.0;
    }

    if (remoteCusto == null) {
      return null;
    }

    if (isCustoLocalProtegido(local)) {
      if (remoteCusto <= _eps && localCusto > _eps) {
        return null;
      }
      if (localCusto <= _eps &&
          remoteCusto > _eps &&
          !local.custoEditadoNoCadastro) {
        return remoteCusto;
      }
      return null;
    }

    if (remoteCusto <= _eps && localCusto > _eps) {
      if (remoteIndicaCustoZeradoExplicitamente(remoteData)) {
        return 0.0;
      }
      return null;
    }

    return remoteCusto;
  }

  /// Atualiza [local.custoReal] e flag após pull ou full-sync (produto existente).
  static void applyRemoteCustoOnExistingProduct({
    required Produto local,
    required Map<String, dynamic> remoteData,
    String logContext = 'sync',
  }) {
    final antes = local.custoReal;
    final resolved = resolveCustoAfterRemotePull(
      local: local,
      remoteData: remoteData,
    );

    if (resolved != null && (resolved - antes).abs() > _eps) {
      local.custoReal = resolved;
    } else if (resolved == null) {
      final remoto = parseRemoteCusto(remoteData);
      if (remoto != null && remoto <= _eps && antes > _eps) {
        logW(
          '[CUSTO_GUARD] $logContext: preservou custoReal local '
          '${antes.toStringAsFixed(2)} (remoto ${remoto.toStringAsFixed(2)})',
          tag: 'CUSTO_GUARD',
        );
      }
    }

    final ce = remoteData['custoEditadoNoCadastro'];
    if (ce is bool && !isCustoLocalProtegido(local)) {
      local.custoEditadoNoCadastro = ce;
    } else if (isCustoLocalProtegido(local)) {
      local.custoEditadoNoCadastro = true;
    }
  }

  /// Merge de importação: retorna custo a gravar ou `null` para não alterar.
  static double? resolveCustoImportMerge({
    required Produto existente,
    required ImportCustoInput importCusto,
    required double fallbackNovoProduto,
  }) {
    if (existente.custoEditadoNoCadastro) {
      return null;
    }

    if (!importCusto.colunaPresente || !importCusto.temValorExplicito) {
      if (existente.custoReal > _eps) {
        return null;
      }
      return fallbackNovoProduto;
    }

    return importCusto.valorExplicito;
  }

  /// Aplica resultado do merge de importação em [existente].
  static void applyImportCustoMerge({
    required Produto existente,
    required ImportCustoInput importCusto,
    required double fallbackNovoProduto,
  }) {
    if (existente.custoEditadoNoCadastro) {
      logW(
        '[CUSTO_GUARD] import merge: mantendo custoReal ${existente.custoReal} (cadastro manual)',
        tag: 'CUSTO_GUARD',
      );
      return;
    }

    final resolved = resolveCustoImportMerge(
      existente: existente,
      importCusto: importCusto,
      fallbackNovoProduto: fallbackNovoProduto,
    );

    if (resolved == null) {
      if (existente.custoReal > _eps &&
          (!importCusto.colunaPresente || !importCusto.temValorExplicito)) {
        logW(
          '[CUSTO_GUARD] import merge: preservou custoReal ${existente.custoReal} (custo ausente/vazio)',
          tag: 'CUSTO_GUARD',
        );
      }
      return;
    }

    if ((resolved - existente.custoReal).abs() > _eps) {
      existente.custoReal = resolved;
    }
  }

  /// Custo inicial ao criar produto a partir de doc sem custo (ex.: catálogo público).
  static double custoInicialFromRemoteDoc(Map<String, dynamic> data) {
    return parseRemoteCusto(data) ?? 0.0;
  }
}
