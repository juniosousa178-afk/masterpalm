import '../models/venda.dart';
import 'venda_exclusao_tombstone.dart';

/// Incluir venda em somas de faturamento, ticket, gráficos e rankings.
/// Legado: sem status/cancelada → conta (comportamento anterior).
///
/// [tombstonesExclusao]: IDs canónicos de vendas em soft-delete / excluídas.
/// Quando omitido, não aplica tombstone (callers síncronos legados).
bool incluirVendaEmMetricas(
  Venda v, {
  Set<String> tombstonesExclusao = const {},
}) {
  if (v.cancelada == true) return false;
  if (v.estornada == true) return false;
  if (VendaExclusaoTombstone.vendaEstaTombstoned(v, tombstonesExclusao)) {
    return false;
  }
  final s = (v.statusVenda ?? '').trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s == 'cancelada' || s == 'cancelado') return false;
  if (s == 'estornada' || s == 'estornado') return false;
  if (s == 'excluida' || s == 'excluída' || s == 'excluido') return false;
  return true;
}

/// Mesma regra para documento Firestore (campos opcionais).
bool incluirVendaFirestoreMap(
  Map<String, dynamic>? data, {
  Set<String> tombstonesExclusao = const {},
}) {
  if (data == null) return true;
  if (data['cancelada'] == true) return false;
  if (data['estornada'] == true) return false;
  final id = (data['idFirebase'] ?? data['id'] ?? data['vendaId'] ?? '')
      .toString()
      .trim();
  if (id.isNotEmpty && tombstonesExclusao.contains(id)) return false;
  final s = (data['statusVenda'] ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s == 'cancelada' || s == 'cancelado') return false;
  if (s == 'estornada' || s == 'estornado') return false;
  if (s == 'excluida' || s == 'excluída' || s == 'excluido') return false;
  return true;
}
