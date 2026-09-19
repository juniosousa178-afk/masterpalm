// Desembrulha erros do interop web (Future convertida / JSObject) para mensagem e retry.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/stock_catalog_affected_products.dart';
import '../services/vendas_service.dart' show VendaPersistenciaInconsistenciaCritica;
import 'nova_venda_payment_guard.dart';

/// Erro real após percorrer [error] / [cause] / encadeamento de "converted Future".
Object unwrapDartInteropError(Object e, {int maxDepth = 6}) {
  Object current = e;
  for (var depth = 0; depth < maxDepth; depth++) {
    final text = current.toString();
    if (!_pareceErroInteropGenerico(text)) {
      return current;
    }
    final inner = _lerErroEncadeado(current);
    if (inner == null || identical(inner, current)) break;
    current = inner;
  }
  return current;
}

/// Texto útil para UI (sem code/plugin/path/stack).
String formatDartErrorForUser(Object e) {
  final root = unwrapDartInteropError(e);
  if (StockCatalogAffectedProducts.isBackendAffectedLimit(root) ||
      StockCatalogAffectedProducts.isBackendAffectedLimit(e)) {
    return StockCatalogAffectedProducts.userMessageForError(root);
  }
  if (root is FirebaseException) {
    return _firebaseExceptionUserMessage(root);
  }
  final text = root.toString().trim();
  if (_textoErroInutilParaUsuario(text)) {
    return 'Falha na operação. Verifique conexão e tente novamente.';
  }
  return _sanitizarTextoErroUsuario(text);
}

String _firebaseExceptionUserMessage(FirebaseException e) {
  final code = e.code.trim().toLowerCase();
  if (code == 'permission-denied') {
    return 'Sem permissão para concluir a operação. Verifique login e acesso.';
  }
  if (code == 'unavailable' || code == 'deadline-exceeded') {
    return 'Falha de conexão. Verifique a internet e tente novamente.';
  }
  if (code == 'not-found') {
    return 'Registro não encontrado. Verifique se os dados foram sincronizados.';
  }
  final msg = e.message?.trim();
  if (msg != null &&
      msg.isNotEmpty &&
      !_textoErroInutilParaUsuario(msg) &&
      !_contemDetalheTecnico(msg)) {
    return _sanitizarTextoErroUsuario(msg);
  }
  return 'Falha na operação. Verifique conexão e tente novamente.';
}

bool _contemDetalheTecnico(String text) {
  final lower = text.toLowerCase();
  return lower.contains('lojas/') ||
      lower.contains('code=') ||
      lower.contains('plugin=') ||
      lower.contains('stack') ||
      lower.contains('converted future');
}

String _sanitizarTextoErroUsuario(String text) {
  if (_contemDetalheTecnico(text)) {
    return 'Falha na operação. Verifique conexão e tente novamente.';
  }
  return text;
}

/// Mensagem amigável para falha ao finalizar venda (sem erro técnico bruto).
String formatSalvarVendaErrorForUser(Object e) {
  final root = unwrapDartInteropError(e);

  if (root is VendaPersistenciaInconsistenciaCritica) {
    return _mensagemInconsistenciaCriticaVenda();
  }

  if (StockCatalogAffectedProducts.isBackendAffectedLimit(root) ||
      StockCatalogAffectedProducts.isBackendAffectedLimit(e)) {
    return StockCatalogAffectedProducts.userMessageForError(root);
  }

  final known = _mapSalvarVendaKnownFailure(root, e);
  if (known != null) return known;

  final detalhe = formatDartErrorForUser(e);
  final lower = detalhe.toLowerCase();

  if (_textoErroInutilParaUsuario(detalhe) ||
      detalhe.startsWith('Falha na operação')) {
    return 'Não foi possível concluir a venda. Tente novamente.';
  }

  if (lower.contains('falha ao persistir venda local') &&
      lower.contains('restaurar estoque')) {
    return _mensagemInconsistenciaCriticaVenda();
  }

  if (lower.contains('sincroniz') || lower.contains('nuvem')) {
    return detalhe;
  }
  return detalhe;
}

({String code, String message, String blob}) _salvarVendaErrorParts(Object root) {
  var code = '';
  var message = '';
  if (root is FirebaseException) {
    code = root.code.trim();
    message = (root.message ?? '').trim();
  } else {
    try {
      final dyn = root as dynamic;
      code = (dyn.code?.toString() ?? '').trim();
      message = (dyn.message?.toString() ?? '').trim();
    } catch (_) {}
  }
  var normalized = code.toLowerCase();
  const prefixes = ['functions/', 'cloud_functions/', 'firebase_functions/'];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) {
      normalized = normalized.substring(prefix.length);
      break;
    }
  }
  final blob = '$normalized $message ${root.toString()}'.toLowerCase();
  return (code: normalized, message: message, blob: blob);
}

bool _salvarVendaIsRealTransportFailure(String code, String blob) {
  if (code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'network-request-failed') {
    return true;
  }
  return blob.contains('socketexception') ||
      blob.contains('clientexception') ||
      blob.contains('xmlhttprequest') ||
      blob.contains('failed to fetch') ||
      blob.contains('network-request-failed') ||
      blob.contains('network_error') ||
      (blob.contains('offline') &&
          !blob.contains('permission') &&
          !blob.contains('failed-precondition'));
}

String? _mapSalvarVendaKnownFailure(Object root, Object original) {
  final parts = _salvarVendaErrorParts(root);
  final originalBlob = original.toString().toLowerCase();
  final blob = '${parts.blob} $originalBlob';
  final code = parts.code;
  final message = parts.message.toLowerCase();

  if (blob.contains('falha ao persistir venda local') &&
      blob.contains('restaurar estoque')) {
    return _mensagemInconsistenciaCriticaVenda();
  }

  if (blob.contains('variation_sale_product_not_authorized') ||
      blob.contains('product variation not authorized')) {
    return 'Este produto não está autorizado para venda com variação.';
  }
  if (blob.contains('grade_sale_not_authorized') ||
      blob.contains('unsafe variation') ||
      blob.contains('unexpected extra dimension')) {
    return 'Venda com grade extra não está autorizada para este produto.';
  }
  if (blob.contains('variation not found') ||
      blob.contains('extra variation not found') ||
      blob.contains('variação não encontrada') ||
      blob.contains('variacao nao encontrada')) {
    return 'Variação não encontrada para este produto.';
  }
  if (blob.contains('invalid canonical stock quantity') ||
      blob.contains('estoque insuficiente') ||
      (blob.contains('insuficiente') && blob.contains('estoque')) ||
      (blob.contains('disponível:') && blob.contains('solicitado:')) ||
      blob.contains('sem estoque disponível')) {
    if (parts.message.trim().startsWith('Estoque')) return parts.message.trim();
    return 'Sem estoque disponível para esta variação.';
  }
  if (blob.contains('dependency migration required') ||
      blob.contains('product tombstone requires reconciliation') ||
      blob.contains('canonical product and editorial draft required')) {
    return 'Este produto precisa de conferência de estoque antes da venda.';
  }
  if (code == 'aborted' ||
      blob.contains('stock revision conflict') ||
      blob.contains('operation identity conflict') ||
      blob.contains('reconciliation_stale_remote_conflict')) {
    return 'O estoque foi atualizado por outra operação. Recarregue o produto e tente novamente.';
  }
  if (blob.contains('pagamento incompleto') ||
      blob.contains('payment incomplete') ||
      blob.contains('não bate com o total')) {
    return kNovaVendaPagamentoIncompletoMensagem;
  }
  if (code == 'internal' || code == 'unknown' || code == 'data-loss') {
    return 'Erro no servidor ao salvar a venda. Tente novamente. Se persistir, contate o suporte.';
  }
  if (code == 'failed-precondition' || code == 'invalid-argument') {
    return 'Não foi possível salvar a venda. O servidor recusou a operação.';
  }
  if (code == 'permission-denied' ||
      blob.contains('permission-denied') ||
      message.contains('permission-denied')) {
    return 'Sem permissão para concluir a venda. Verifique login e acesso à loja.';
  }
  if (_salvarVendaIsRealTransportFailure(code, blob)) {
    return 'Falha de conexão ao salvar a venda. Verifique a internet e tente novamente.';
  }
  return null;
}

String _mensagemInconsistenciaCriticaVenda() =>
    'A venda não foi concluída corretamente e não foi possível restaurar o '
    'estoque na nuvem. Não repita a operação. Verifique o estoque antes de '
    'tentar novamente ou contate o suporte.';

/// Metadados seguros para log de diagnóstico (sem PII).
Map<String, String> dartErrorDiagMeta(Object e) {
  final root = unwrapDartInteropError(e);
  String? code;
  String? plugin;
  String? message;
  try {
    final dyn = root as dynamic;
    code = dyn.code?.toString();
    plugin = dyn.plugin?.toString();
    message = dyn.message?.toString();
  } catch (_) {}
  if (root is FirebaseException) {
    code ??= root.code;
    plugin ??= root.plugin;
    message ??= root.message;
  }
  return {
    'runtimeType': root.runtimeType.toString(),
    'outerRuntimeType': e.runtimeType.toString(),
    if (code != null && code.isNotEmpty) 'code': code,
    if (plugin != null && plugin.isNotEmpty) 'plugin': plugin,
    if (message != null && message.isNotEmpty) 'message': message,
    'unwrapped': formatDartErrorForUser(e),
  };
}

bool _pareceErroInteropGenerico(String text) {
  final lower = text.toLowerCase();
  return lower.contains('dart exception thrown from converted future') ||
      lower.contains('use the properties') && lower.contains("'error'");
}

bool _textoErroInutilParaUsuario(String text) {
  if (text.isEmpty) return true;
  if (_pareceErroInteropGenerico(text)) return true;
  if (text.startsWith("Instance of '") && text.endsWith("'")) return true;
  return false;
}

Object? _lerErroEncadeado(Object e) {
  try {
    final dyn = e as dynamic;
    final err = dyn.error;
    if (err != null) return err as Object;
  } catch (_) {}
  try {
    final dyn = e as dynamic;
    final cause = dyn.cause;
    if (cause != null) return cause as Object;
  } catch (_) {}
  try {
    final dyn = e as dynamic;
    final details = dyn.details;
    if (details != null) return details as Object;
  } catch (_) {}
  try {
    final dyn = e as dynamic;
    final inner = dyn.inner;
    if (inner != null) return inner as Object;
  } catch (_) {}
  return null;
}
