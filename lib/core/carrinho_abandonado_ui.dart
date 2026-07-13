// Status canônicos M3.8 (UI) + filtros locais de carrinhos abandonados.
// Não altera engines de checkout/venda.

import 'package:diacritic/diacritic.dart';

const String kCarrinhoUiAbandonado = 'abandonado';
const String kCarrinhoUiRecuperado = 'recuperado';
const String kCarrinhoUiVirouPedido = 'virou_pedido';
const String kCarrinhoUiVirouVenda = 'virou_venda';

const String kCarrinhoFiltroPeriodoTodos = 'todos';
const String kCarrinhoFiltroPeriodoHoje = 'hoje';
const String kCarrinhoFiltroPeriodo7d = '7d';
const String kCarrinhoFiltroPeriodo30d = '30d';

const String kCarrinhoFiltroValorTodos = 'todos';
const String kCarrinhoFiltroValorAte100 = 'ate100';
const String kCarrinhoFiltroValor100a300 = '100a300';
const String kCarrinhoFiltroValorAcima300 = 'acima300';

String normalizarStatusCarrinhoAbandonado(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'ativo') return kCarrinhoUiAbandonado;
  if (s == 'recuperado' || s == 'recovered') return kCarrinhoUiRecuperado;
  if (s.contains('pedido') || s == 'virou_pedido') return kCarrinhoUiVirouPedido;
  if (s.contains('venda') || s == 'virou_venda') return kCarrinhoUiVirouVenda;
  if (s == 'abandonado' || s == 'abandoned') return kCarrinhoUiAbandonado;
  return s;
}

String labelStatusCarrinhoAbandonado(String raw) {
  switch (normalizarStatusCarrinhoAbandonado(raw)) {
    case kCarrinhoUiRecuperado:
      return 'Recuperado';
    case kCarrinhoUiVirouPedido:
      return 'Virou Pedido';
    case kCarrinhoUiVirouVenda:
      return 'Virou Venda';
    default:
      return 'Abandonado';
  }
}

double totalCarrinhoProdutos(List<Map<String, dynamic>> produtos) {
  double t = 0;
  for (final p in produtos) {
    final q = (p['quantidade'] as num?)?.toDouble() ?? 1;
    final preco = (p['preco'] as num?)?.toDouble() ??
        (p['precoUnitario'] as num?)?.toDouble() ??
        (p['price'] as num?)?.toDouble() ??
        0;
    final line = (p['total'] as num?)?.toDouble();
    t += line ?? (preco * q);
  }
  return t;
}

String formatarTempoAbandonado(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}min';
  return '${d.inMinutes}min';
}

/// Normaliza texto de busca: lower, sem acento, espaços colapsados.
String normalizarTextoBuscaCarrinho(String input) {
  return removeDiacritics(input)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String apenasDigitosCarrinho(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// [haystack] contém [query] (já normalizada) por texto ou por dígitos do telefone.
bool textoContemBuscaCarrinho(String haystack, String queryNormalizada) {
  if (queryNormalizada.isEmpty) return true;
  final h = normalizarTextoBuscaCarrinho(haystack);
  if (h.contains(queryNormalizada)) return true;
  final qd = apenasDigitosCarrinho(queryNormalizada);
  if (qd.length >= 3) {
    final hd = apenasDigitosCarrinho(haystack);
    if (hd.contains(qd)) return true;
  }
  return false;
}

bool carrinhoCorrespondeBusca({
  required String query,
  required String nome,
  String telefone = '',
  String whatsapp = '',
  String email = '',
  String cpf = '',
  String idExtra = '',
}) {
  final q = normalizarTextoBuscaCarrinho(query);
  if (q.isEmpty) return true;
  return textoContemBuscaCarrinho(nome, q) ||
      textoContemBuscaCarrinho(telefone, q) ||
      textoContemBuscaCarrinho(whatsapp, q) ||
      textoContemBuscaCarrinho(email, q) ||
      textoContemBuscaCarrinho(cpf, q) ||
      textoContemBuscaCarrinho(idExtra, q);
}

bool carrinhoCorrespondeStatus(String statusRaw, String filtroStatus) {
  if (filtroStatus == 'todos' || filtroStatus.isEmpty) return true;
  return normalizarStatusCarrinhoAbandonado(statusRaw) == filtroStatus;
}

bool carrinhoCorrespondePeriodo(
  DateTime? ref, {
  required String filtroPeriodo,
  DateTime? agora,
}) {
  if (filtroPeriodo == kCarrinhoFiltroPeriodoTodos || filtroPeriodo.isEmpty) {
    return true;
  }
  if (ref == null) return false;
  final now = agora ?? DateTime.now();
  switch (filtroPeriodo) {
    case kCarrinhoFiltroPeriodoHoje:
      return ref.year == now.year &&
          ref.month == now.month &&
          ref.day == now.day;
    case kCarrinhoFiltroPeriodo7d:
      return !ref.isBefore(now.subtract(const Duration(days: 7)));
    case kCarrinhoFiltroPeriodo30d:
      return !ref.isBefore(now.subtract(const Duration(days: 30)));
    default:
      return true;
  }
}

bool carrinhoCorrespondeValor(double valor, String filtroValor) {
  switch (filtroValor) {
    case kCarrinhoFiltroValorAte100:
      return valor <= 100;
    case kCarrinhoFiltroValor100a300:
      return valor > 100 && valor <= 300;
    case kCarrinhoFiltroValorAcima300:
      return valor > 300;
    default:
      return true;
  }
}

/// Critérios combinados (AND) aplicados localmente sobre a lista em memória.
bool carrinhoPassaFiltrosCombinados({
  required String query,
  required String filtroStatus,
  required String filtroPeriodo,
  required String filtroValor,
  required String statusRaw,
  required DateTime? dataRef,
  required double valor,
  required String nome,
  String telefone = '',
  String whatsapp = '',
  String email = '',
  String cpf = '',
  String idExtra = '',
  DateTime? agora,
}) {
  if (!carrinhoCorrespondeBusca(
    query: query,
    nome: nome,
    telefone: telefone,
    whatsapp: whatsapp,
    email: email,
    cpf: cpf,
    idExtra: idExtra,
  )) {
    return false;
  }
  if (!carrinhoCorrespondeStatus(statusRaw, filtroStatus)) return false;
  if (!carrinhoCorrespondePeriodo(
    dataRef,
    filtroPeriodo: filtroPeriodo,
    agora: agora,
  )) {
    return false;
  }
  if (!carrinhoCorrespondeValor(valor, filtroValor)) return false;
  return true;
}
