// Política de cupom público vs pessoal no checkout do catálogo (visitante).

import '../models/cupom.dart';

/// Resultado da tentativa de resolver um cupom no checkout.
enum CatalogoCupomResolverStatus {
  encontradoPublico,
  bloqueadoPessoalSemLogin,
  bloqueadoPessoalContaErrada,
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

/// Mensagem UX quando cupom pessoal pertence a outra conta.
const catalogoCupomPessoalContaErradaMsg =
    'Este cupom é pessoal e não está disponível para esta conta.';

String catalogoEmailNormalizado(String? email) =>
    email?.trim().toLowerCase() ?? '';

bool catalogoCupomEhPessoal(Cupom cupom) =>
    cupom.clienteId != null && cupom.clienteId!.trim().isNotEmpty;

/// Valida se o cliente logado é dono do cupom pessoal (uid/email normalizado).
bool catalogoClienteEhDonoCupom({
  required Cupom cupom,
  required String? clienteLogadoId,
  required String? clienteLogadoEmail,
}) {
  if (!catalogoCupomEhPessoal(cupom)) return true;

  final ownerId = cupom.clienteId?.trim() ?? '';
  final ownerEmail = catalogoEmailNormalizado(cupom.ownerEmail);
  final idLogado = clienteLogadoId?.trim() ?? '';
  final emailLogado = catalogoEmailNormalizado(clienteLogadoEmail);

  if (ownerId.isNotEmpty && idLogado.isNotEmpty && idLogado == ownerId) {
    return true;
  }
  if (ownerEmail.isNotEmpty &&
      emailLogado.isNotEmpty &&
      ownerEmail == emailLogado) {
    return true;
  }
  return false;
}

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
    'pessoal': catalogoCupomEhPessoal(c),
    if (c.clienteId != null && c.clienteId!.isNotEmpty)
      'clienteId': c.clienteId,
    if (c.ownerEmail != null && c.ownerEmail!.trim().isNotEmpty)
      'ownerEmail': catalogoEmailNormalizado(c.ownerEmail),
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
  String? clienteLogadoId,
  String? clienteLogadoEmail,
}) {
  if (cupom == null || !cupom.ativo) {
    return const CatalogoCupomResolverResult(
      status: CatalogoCupomResolverStatus.naoEncontrado,
    );
  }

  final ehPessoal = catalogoCupomEhPessoal(cupom);
  if (ehPessoal && !clienteLogado) {
    return const CatalogoCupomResolverResult(
      status: CatalogoCupomResolverStatus.bloqueadoPessoalSemLogin,
      mensagem: catalogoCupomPessoalExigeLoginMsg,
    );
  }

  if (ehPessoal &&
      !catalogoClienteEhDonoCupom(
        cupom: cupom,
        clienteLogadoId: clienteLogadoId,
        clienteLogadoEmail: clienteLogadoEmail,
      )) {
    return const CatalogoCupomResolverResult(
      status: CatalogoCupomResolverStatus.bloqueadoPessoalContaErrada,
      mensagem: catalogoCupomPessoalContaErradaMsg,
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
