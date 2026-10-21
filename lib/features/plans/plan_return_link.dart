// URLs de retorno do Mercado Pago para checkout de planos.
//
// - `/assinatura/{plano}/retorno` — preferência avulsa (planCreatePreference[Call]).
// - `/planos/retorno` — assinatura recorrente (createPlanSubscription).
// - `/assinatura/troca/{changeId}/retorno` — troca de plano (createPlanChangeSubscription).
//
// A query anexada pelo Mercado Pago (status, payment_id, preapproval_id…) é preservada na
// barra de endereço, mas nunca lida como prova de pagamento: o webhook é a autoridade.

import 'package:master_palm/config/app_urls.dart';

enum PlanReturnKind { oneTime, recurring, planChange }

class PlanReturnRef {
  const PlanReturnRef({required this.kind, this.planId, this.changeId});

  final PlanReturnKind kind;

  /// Segmento `{plano}` validado (apenas [PlanReturnKind.oneTime]); `null` se malformado.
  final String? planId;

  /// Segmento `{changeId}` validado (apenas [PlanReturnKind.planChange]); `null` se malformado.
  final String? changeId;

  bool get isValid {
    switch (kind) {
      case PlanReturnKind.oneTime:
        return planId != null;
      case PlanReturnKind.recurring:
        return true;
      case PlanReturnKind.planChange:
        return changeId != null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlanReturnRef &&
      other.kind == kind &&
      other.planId == planId &&
      other.changeId == changeId;

  @override
  int get hashCode => Object.hash(kind, planId, changeId);

  @override
  String toString() => 'PlanReturnRef($kind, plan=$planId, change=$changeId)';
}

class PlanReturnLink {
  PlanReturnLink._();

  static final RegExp _planIdPattern = RegExp(r'^[a-z0-9_-]{1,64}$');
  static final RegExp _changeIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static bool isValidPlanId(String? id) =>
      id != null && _planIdPattern.hasMatch(id);

  static bool isValidChangeId(String? id) =>
      id != null && _changeIdPattern.hasMatch(id);

  static List<String> _segments(Uri uri) =>
      uri.pathSegments.where((e) => e.isNotEmpty).toList();

  /// `true` para os três formatos de retorno, mesmo com IDs malformados
  /// (a página mostra um aviso amigável em vez de cair no catálogo/home).
  static bool isPlanReturnPath(Uri uri) => _kindOf(_segments(uri)) != null;

  static PlanReturnKind? _kindOf(List<String> s) {
    if (s.length == 2 && s[0] == 'planos' && s[1] == 'retorno') {
      return PlanReturnKind.recurring;
    }
    if (s.length == 4 &&
        s[0] == 'assinatura' &&
        s[1] == 'troca' &&
        s[3] == 'retorno') {
      return PlanReturnKind.planChange;
    }
    if (s.length == 3 && s[0] == 'assinatura' && s[2] == 'retorno') {
      return s[1] == 'troca' ? PlanReturnKind.planChange : PlanReturnKind.oneTime;
    }
    return null;
  }

  static PlanReturnRef? parse(Uri uri) {
    final s = _segments(uri);
    final kind = _kindOf(s);
    switch (kind) {
      case null:
        return null;
      case PlanReturnKind.recurring:
        return const PlanReturnRef(kind: PlanReturnKind.recurring);
      case PlanReturnKind.oneTime:
        final plan = s[1].trim();
        return PlanReturnRef(
          kind: PlanReturnKind.oneTime,
          planId: isValidPlanId(plan) ? plan : null,
        );
      case PlanReturnKind.planChange:
        final change = s.length == 4 ? s[2].trim() : null;
        return PlanReturnRef(
          kind: PlanReturnKind.planChange,
          changeId: isValidChangeId(change) ? change : null,
        );
    }
  }

  /// `returnUrl` enviado ao backend no checkout avulso. Lança [ArgumentError] para IDs fora do formato.
  static Uri buildOneTimeReturnUrl({
    required String planId,
    String baseUrl = AppUrls.appWebBase,
  }) {
    final plan = planId.trim();
    if (!isValidPlanId(plan)) {
      throw ArgumentError.value(planId, 'planId', 'formato inválido');
    }
    final base = Uri.parse(baseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: ['assinatura', plan, 'retorno'],
    );
  }

  /// Nome da rota reportado ao browser; com `/` a barra de endereço perderia o retorno.
  static String routeName(Uri uri) =>
      uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
}
