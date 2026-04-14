// Helpers para domínio customizado do catálogo (normalização + estados de UI/backend).

/// Host CNAME público do catálogo Firebase Hosting (valor exibido ao lojista).
const String kCatalogPublicCnameTarget = 'masterpalm-58c46.web.app';

/// Rótulo recomendado do registro DNS (nome relativo à zona).
const String kCatalogDnsRecordName = 'catalogo';

/// Tipo de registro exibido na configuração guiada.
const String kCatalogDnsRecordType = 'CNAME';

const String kDominioStatusNaoConfigurado = 'nao_configurado';
const String kDominioStatusPendente = 'pendente';
const String kDominioStatusEmVerificacao = 'em_verificacao';
const String kDominioStatusSolicitado = 'solicitado';
const String kDominioStatusPendenteDns = 'pendente_dns';
const String kDominioStatusDnsOk = 'dns_ok';
const String kDominioStatusErro = 'erro';
const String kDominioStatusAtivo = 'ativo';

/// Remove protocolo, caminho, porta e normaliza minúsculas.
String normalizeCatalogDomainInput(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  final slash = s.indexOf('/');
  if (slash >= 0) s = s.substring(0, slash);
  final colon = s.indexOf(':');
  if (colon >= 0) s = s.substring(0, colon);
  while (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Se o host já for `catalogo.*`, mantém; senão prefixa `catalogo.`.
String recommendedCatalogFqdn(String normalizedHost) {
  if (normalizedHost.isEmpty) return '';
  if (normalizedHost.startsWith('catalogo.')) return normalizedHost;
  return 'catalogo.$normalizedHost';
}

String dominioStatusLabelPt(String key) {
  switch (key) {
    case kDominioStatusPendente:
      return 'Pendente';
    case kDominioStatusEmVerificacao:
      return 'Em verificação';
    case kDominioStatusSolicitado:
      return 'Solicitação enviada';
    case kDominioStatusPendenteDns:
      return 'DNS pendente';
    case kDominioStatusDnsOk:
      return 'DNS correto';
    case kDominioStatusErro:
      return 'Erro';
    case kDominioStatusAtivo:
      return 'Ativo';
    case kDominioStatusNaoConfigurado:
    default:
      return 'Não configurado';
  }
}

/// Carrega status persistido; corrige combinações inválidas.
String dominioStatusFromStorage(String? raw, {required bool hasDomain}) {
  final s = (raw ?? '').trim();
  if (!hasDomain) return kDominioStatusNaoConfigurado;
  if (s == kDominioStatusPendente) return kDominioStatusSolicitado;
  if (s == kDominioStatusEmVerificacao) return kDominioStatusPendenteDns;
  const ok = {
    kDominioStatusSolicitado,
    kDominioStatusPendenteDns,
    kDominioStatusDnsOk,
    kDominioStatusErro,
    kDominioStatusAtivo,
  };
  if (ok.contains(s)) return s;
  return kDominioStatusSolicitado;
}

/// Valor gravado em [dominioStatus] no mapa de configuração.
String dominioStatusForConfigMap(String normalizedDomain, String uiStatus) {
  if (normalizedDomain.isEmpty) return kDominioStatusNaoConfigurado;
  return dominioStatusFromStorage(uiStatus, hasDomain: true);
}
