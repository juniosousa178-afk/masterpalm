class ConsignmentException implements Exception {
  const ConsignmentException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;

  static const networkMessage =
      'É necessário estar conectado para confirmar esta operação.';

  static ConsignmentException network() =>
      const ConsignmentException('NETWORK', networkMessage);

  static ConsignmentException fromCallable(String? code, String? message, dynamic details) {
    String mapped = (code ?? '').trim();
    if (details is Map) {
      final c = details['consignmentCode'] ?? details['code'];
      if (c != null && '$c'.trim().isNotEmpty) mapped = '$c'.trim();
    }
    if (mapped.isEmpty) mapped = (message ?? 'SERVER').trim();
    if (mapped == 'unavailable' ||
        mapped == 'deadline-exceeded' ||
        mapped == 'NETWORK') {
      return ConsignmentException.network();
    }
    return ConsignmentException(mapped, userMessage(mapped, message));
  }

  static String userMessage(String code, [String? fallback]) {
    switch (code) {
      case 'INSUFFICIENT_STOCK':
        return 'Estoque insuficiente para enviar em consignação.';
      case 'PRODUCT_NOT_FOUND':
        return 'Produto não encontrado.';
      case 'VARIATION_NOT_FOUND':
        return 'Variação não encontrada.';
      case 'PRODUCT_STATE_UNSAFE':
        return 'Produto em estado inseguro. A consignação foi recusada.';
      case 'CONSIGNMENT_GRADE_NOT_SUPPORTED':
        return 'Produtos de grade não são suportados no consignado.';
      case 'CONSIGNMENT_ALREADY_ISSUED':
        return 'Esta consignação já foi emitida.';
      case 'CONSIGNMENT_ALREADY_SETTLED':
        return 'Esta consignação já foi acertada.';
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
