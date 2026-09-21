class ConsignmentProductIssue {
  const ConsignmentProductIssue({
    required this.productId,
    required this.productName,
    required this.reasonCode,
    required this.userMessage,
    this.lineIndex = 0,
    this.selectionLabel = '',
    this.requestedQty,
    this.availableQty,
  });

  final String productId;
  final String productName;
  final String reasonCode;
  final String userMessage;
  final int lineIndex;
  final String selectionLabel;
  final int? requestedQty;
  final int? availableQty;

  factory ConsignmentProductIssue.fromMap(Map raw) {
    return ConsignmentProductIssue(
      productId: '${raw['productId'] ?? ''}',
      productName: '${raw['productName'] ?? raw['productId'] ?? ''}',
      reasonCode: '${raw['reasonCode'] ?? 'OTHER_PRODUCT_BLOCK'}',
      userMessage: '${raw['userMessage'] ?? ''}',
      lineIndex: raw['lineIndex'] is int ? raw['lineIndex'] as int : 0,
      selectionLabel: '${raw['selectionLabel'] ?? ''}',
      requestedQty: raw['requestedQty'] is num ? (raw['requestedQty'] as num).toInt() : null,
      availableQty: raw['availableQty'] is num ? (raw['availableQty'] as num).toInt() : null,
    );
  }
}

class ConsignmentException implements Exception {
  const ConsignmentException(this.code, this.message, {this.issues = const []});

  final String code;
  final String message;
  final List<ConsignmentProductIssue> issues;

  @override
  String toString() => message;

  static const networkMessage =
      'É necessário estar conectado para confirmar esta operação.';

  static ConsignmentException network() =>
      const ConsignmentException('NETWORK', networkMessage);

  static ConsignmentException fromCallable(String? code, String? message, dynamic details) {
    String mapped = (code ?? '').trim();
    final issues = <ConsignmentProductIssue>[];
    if (details is Map) {
      final c = details['consignmentCode'] ?? details['code'];
      if (c != null && '$c'.trim().isNotEmpty) mapped = '$c'.trim();
      final rawIssues = details['issues'];
      if (rawIssues is List) {
        for (final item in rawIssues) {
          if (item is Map) issues.add(ConsignmentProductIssue.fromMap(item));
        }
      }
    }
    if (mapped.isEmpty) mapped = (message ?? 'SERVER').trim();
    if (mapped == 'unavailable' ||
        mapped == 'deadline-exceeded' ||
        mapped == 'NETWORK') {
      return ConsignmentException.network();
    }
    if (mapped == 'PRODUCT_VALIDATION_FAILED' && issues.isNotEmpty) {
      final buffer = StringBuffer('Não foi possível concluir a operação.\n\n');
      buffer.writeln('${issues.length} produto${issues.length == 1 ? '' : 's'} precisam de atenção:');
      for (final issue in issues) {
        final label = issue.selectionLabel.trim().isEmpty
            ? issue.productName
            : '${issue.productName} (${issue.selectionLabel})';
        buffer.writeln('• $label — ${issue.userMessage}');
      }
      return ConsignmentException(mapped, buffer.toString().trim(), issues: issues);
    }
    return ConsignmentException(mapped, userMessage(mapped, message), issues: issues);
  }

  static String userMessage(String code, [String? fallback]) {
    switch (code) {
      case 'INSUFFICIENT_STOCK':
        return 'Estoque insuficiente para este produto. Atualize a quantidade e tente novamente.';
      case 'ZERO_STOCK':
        return 'Este produto está sem estoque disponível.';
      case 'PRODUCT_NOT_FOUND':
        return 'Produto não encontrado.';
      case 'VARIATION_NOT_FOUND':
        return 'Variação não encontrada.';
      case 'VARIATION_REQUIRED':
        return 'Selecione a variação deste produto.';
      case 'GRADE_SELECTION_REQUIRED':
        return 'Selecione todas as opções deste produto.';
      case 'GRADE_CELL_NOT_FOUND':
        return 'Essa combinação não está mais disponível.';
      case 'GRADE_CELL_AMBIGUOUS':
        return 'A grade deste produto precisa ser atualizada antes de continuar.';
      case 'PRODUCT_STATE_UNSAFE':
      case 'INVALID_STOCK_STATE':
      case 'MISSING_STOCK_METADATA':
      case 'MISSING_DEPENDENCY':
        return 'O estoque deste produto precisa ser atualizado antes de continuar.';
      case 'COMBO_NOT_SUPPORTED':
        return 'Produtos do tipo combo ainda não são suportados nesta operação.';
      case 'CONSIGNMENT_GRADE_NOT_SUPPORTED':
        return 'A grade deste produto precisa ser atualizada antes de continuar.';
      case 'PRODUCT_VALIDATION_FAILED':
        return 'Não foi possível concluir. Verifique os produtos selecionados.';
      case 'CONSIGNMENT_ALREADY_ISSUED':
        return 'Esta consignação já foi emitida.';
      case 'CONSIGNMENT_ALREADY_SETTLED':
        return 'Esta consignação já foi acertada e não pode receber novas peças.';
      case 'CONSIGNMENT_CANCELLED':
        return 'Esta consignação está cancelada.';
      case 'CONSIGNMENT_REVISION_CONFLICT':
      case 'aborted':
        return 'Esta consignação foi atualizada. Atualize a tela e tente novamente.';
      case 'STOCK_CONFLICT':
        return 'O estoque deste produto foi alterado. Atualizamos os dados; confira e tente novamente.';
      case 'INVALID_SETTLEMENT_TOTAL':
        return 'Vendido + devolvido deve ser igual ao enviado em todas as linhas.';
      case 'IDEMPOTENCY_CONFLICT':
        return 'Operação duplicada com dados diferentes. Recarregue e tente de novo.';
      case 'unauthenticated':
      case 'permission-denied':
      case 'AUTH':
        return 'Você não tem permissão para esta operação nesta loja.';
      case 'RESELLER_PERMISSION':
        return 'Você não tem permissão para cadastrar revendedores nesta loja.';
      case 'MODULE_DISABLED':
        return 'O módulo de consignados não está habilitado nesta loja.';
      case 'NETWORK':
        return networkMessage;
      case 'unavailable':
      case 'deadline-exceeded':
        return networkMessage;
      default:
        return fallback?.trim().isNotEmpty == true
            ? 'Não foi possível concluir: ${fallback!.trim()}'
            : 'Falha no servidor ao processar o consignado.';
    }
  }

  static String resellerUserMessage(Object e) {
    if (e is ConsignmentException) {
      if (e.code == 'NETWORK' ||
          e.code == 'unavailable' ||
          e.code == 'deadline-exceeded') {
        return 'Não foi possível conectar. Verifique sua internet.';
      }
      if (e.code == 'INVALID_ARGUMENT') {
        return 'Informe o nome do revendedor.';
      }
      if (e.code == 'RESELLER_PERMISSION' ||
          e.code == 'AUTH' ||
          e.code == 'permission-denied' ||
          e.code == 'unauthenticated') {
        return 'Você não tem permissão para cadastrar revendedores nesta loja.';
      }
      if (e.message.contains('Stock protocol')) {
        return 'Você não tem permissão para cadastrar revendedores nesta loja.';
      }
      return e.message;
    }
    return userMessage('SERVER', e.toString());
  }
}
