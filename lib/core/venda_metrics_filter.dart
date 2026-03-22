import '../models/venda.dart';

/// Incluir venda em somas de faturamento, ticket, gráficos e rankings.
/// Legado: sem status/cancelada → conta (comportamento anterior).
bool incluirVendaEmMetricas(Venda v) {
  if (v.cancelada == true) return false;
  if (v.estornada == true) return false;
  final s = (v.statusVenda ?? '').trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s == 'cancelada' || s == 'cancelado') return false;
  if (s == 'estornada' || s == 'estornado') return false;
  return true;
}

/// Mesma regra para documento Firestore (campos opcionais).
bool incluirVendaFirestoreMap(Map<String, dynamic>? data) {
  if (data == null) return true;
  if (data['cancelada'] == true) return false;
  if (data['estornada'] == true) return false;
  final s = (data['statusVenda'] ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s == 'cancelada' || s == 'cancelado') return false;
  if (s == 'estornada' || s == 'estornado') return false;
  return true;
}
