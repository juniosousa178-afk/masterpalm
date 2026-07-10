// Política de cupom público vs pessoal no checkout do catálogo (visitante).

import '../models/cupom.dart';

/// Resultado da tentativa de resolver um cupom no checkout.
enum CatalogoCupomResolverStatus {
  encontradoPublico,
  bloqueadoPessoalSemLogin,
  naoEncontrado,
}

class CatalogoCupomResolverResult {
  const CatalogoCupomResolverResult({
    required this.status,
    this.cupomMap,
    this.mensagem,
  });

  final CatalogoCupomResolverStatus status;
  final Map<String, dynamic>? cupomMap;
  final String? mensagem;
}

/// Mensagem UX quando cupom pessoal exige login.
const catalogoCupomPessoalExigeLoginMsg =
    'Este cupom é pessoal. Entre na sua conta para utilizá-lo.';

/// Converte [Cupom] da loja para mapa usado no carrinho.
Map<String, dynamic> catalogoCupomMapFromFirestoreCupom(Cupom c) {
  final tipo = c.freteGratis
      ? 'frete_gratis'
      : (c.tipo == 'percentual' ? 'percent' : 'valor');
  return {
    'id': c.id,
    'codigo': c.codigo,
    'code': c.codigo,
    'tipo': tipo,
    'valor': c.valor,
    'aplicarEm': c.aplicarEm,
    'freteGratis': c.freteGratis,
    'valorMinimo': c.valorMinimo,
    'dataFim': c.dataFim,
    'ativo': c.ativo,
    'origem': 'cupom_publico_loja',
    if (c.produtoIds.isNotEmpty) 'produtoIds': c.produtoIds,
  };
}

/// Cupom da config embutida do catálogo (público).
bool catalogoCupomConfigEhPublico(Map<String, dynamic> cupom) {
  final pessoal = cupom['pessoal'] == true || cupom['clienteId'] != null;
  return !pessoal;
}

/// Resolve cupom público da collection Firestore para visitante.
CatalogoCupomResolverResult resolverCupomPublicoFirestore({
  required Cupom? cupom,
  required bool clienteLogado,
}) {
  if (cupom == null || !cupom.ativo) {
    return const CatalogoCupomResolverResult(
      status: CatalogoCupomResolverStatus.naoEncontrado,
    );
  }

  final ehPessoal =
      cupom.clienteId != null && cupom.clienteId!.trim().isNotEmpty;
  if (ehPessoal && !clienteLogado) {
    return const CatalogoCupomResolverResult(
      status: CatalogoCupomResolverStatus.bloqueadoPessoalSemLogin,
      mensagem: catalogoCupomPessoalExigeLoginMsg,
    );
  }

  return CatalogoCupomResolverResult(
    status: CatalogoCupomResolverStatus.encontradoPublico,
    cupomMap: catalogoCupomMapFromFirestoreCupom(cupom),
  );
}

/// Mensagem quando visitante não logado não achou cupom público.
String mensagemCupomNaoEncontradoVisitante({required bool clienteLogado}) {
  if (clienteLogado) {
    return 'Cupom inválido, inativo ou expirado.';
  }
  return catalogoCupomPessoalExigeLoginMsg;
}

/// Indica se o código parece cupom de roleta/indicação (pessoal).
bool catalogoCupomCodigoParecePessoal(String code) {
  final c = code.trim().toUpperCase();
  if (c.startsWith('PREMIO-')) return true;
  if (c == 'FRETE_GRATIS' || c == 'BRINDE') return true;
  return false;
}
