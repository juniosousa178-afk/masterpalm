// Bridge controlado: meta/comissão legadas → GestaoVendedorConfig.

import '../models/comissao_config.dart';
import '../models/gestao_comercial.dart';
import '../models/meta.dart';
import 'access_scope_service.dart';

/// Resolve meta mensal legada para o vendedor sem cruzar outros sellers.
/// Ordem: uid → email → displayName → sellerKeys (nunca "GERAL").
Meta? resolveMetaLegadaParaVendedor({
  required List<Meta> metas,
  required AccessScopeIdentity identity,
  required String mesRef,
}) {
  final uid = identity.uid.trim().toLowerCase();
  final email = identity.email.trim().toLowerCase();
  final nome = identity.displayName.trim().toLowerCase();
  final keys = identity.sellerKeys.map((e) => e.trim().toLowerCase()).toSet();

  Meta? by(bool Function(String vid) pred) {
    for (final m in metas) {
      if (m.mesRef != mesRef) continue;
      final vid = m.vendedorId.trim();
      if (vid.isEmpty || vid.toUpperCase() == 'GERAL') continue;
      if (pred(vid.toLowerCase())) return m;
    }
    return null;
  }

  if (uid.isNotEmpty) {
    final hit = by((v) => v == uid);
    if (hit != null) return hit;
  }
  if (email.isNotEmpty) {
    final hit = by((v) => v == email);
    if (hit != null) return hit;
  }
  if (nome.isNotEmpty) {
    final hit = by((v) => v == nome);
    if (hit != null) return hit;
  }
  if (keys.isNotEmpty) {
    final hit = by(keys.contains);
    if (hit != null) return hit;
  }
  return null;
}

/// Se gestao não tem meta mensal, aplica valor legado (sem sobrescrever > 0).
GestaoVendedorConfig aplicarMetaLegadaSeVazia({
  required GestaoVendedorConfig config,
  required Meta? legada,
}) {
  if (config.metaMensal > 0) return config;
  if (legada == null || legada.metaMensal <= 0) return config;
  return config.copyWith(metaMensal: legada.metaMensal);
}

/// Se gestao não tem %/fixo de comissão, aplica legado (vendedor → global).
GestaoVendedorConfig aplicarComissaoLegadaSeVazia({
  required GestaoVendedorConfig config,
  ComissaoVendedor? vendedorLegado,
  ComissaoConfig? globalLegado,
}) {
  final temPct = (config.comissaoPercentual ?? 0) > 0;
  final temFixo = (config.comissaoValorFixo ?? 0) > 0;
  final temFaixa = config.comissaoFaixas.isNotEmpty;
  if (temPct || temFixo || temFaixa) return config;

  if (vendedorLegado != null &&
      vendedorLegado.ativo &&
      (vendedorLegado.comissaoPercentual ?? 0) > 0) {
    return config.copyWith(
      comissaoTipo: ComissaoTipo.percentual,
      comissaoPercentual: vendedorLegado.comissaoPercentual,
    );
  }
  final globalPct = globalLegado?.comissaoGlobalPercent ?? 0;
  if (globalPct > 0) {
    return config.copyWith(
      comissaoTipo: ComissaoTipo.percentual,
      comissaoPercentual: globalPct,
    );
  }
  return config;
}
