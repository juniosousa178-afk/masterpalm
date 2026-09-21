// Desembrulha erros do interop web (Future convertida / JSObject) para mensagem e retry.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/venda_estoque_remoto_prep_service.dart'
    show PendingStockSyncRequiredException;
import '../services/vendas_service.dart' show VendaPersistenciaInconsistenciaCritica;

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
  if (code == 'failed-precondition' || code == 'aborted') {
    final msg = e.message?.trim() ?? '';
    final lower = msg.toLowerCase();
    if (lower.contains('revision') ||
        lower.contains('conflict') ||
        lower.contains('stock revision')) {
      return 'Os dados de estoque deste produto foram atualizados. '
          'Atualize a tela e tente novamente.';
    }
    if (lower.contains('insufficient') || lower.contains('quantity')) {
      return 'Estoque insuficiente para concluir a operação.';
    }
    if (lower.contains('product validation') ||
        lower.contains('product_validation_failed')) {
      return 'Não foi possível validar o estoque de um ou mais produtos. '
          'Atualize a tela e tente novamente.';
    }
    return 'Os dados de estoque precisam ser atualizados. '
        'Atualize a tela e tente novamente.';
  }
  if (code == 'already-exists') {
    return 'Esta operação já foi registrada. Atualize a tela antes de repetir.';
  }
  if (code == 'invalid-argument') {
    return 'Dados inválidos para concluir a operação. Verifique os itens e tente novamente.';
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
  var cleaned = text.trim();
  // StateError.toString() = "Bad state: …" — nunca mostrar prefixo técnico.
  const prefixes = <String>[
    'Bad state: ',
    'Exception: ',
    'Error: ',
  ];
  for (final p in prefixes) {
    if (cleaned.startsWith(p)) {
      cleaned = cleaned.substring(p.length).trim();
    }
  }
  if (_contemDetalheTecnico(cleaned)) {
    return 'Falha na operação. Verifique conexão e tente novamente.';
  }
  return cleaned;
}

/// Mensagem amigável para falha ao finalizar venda (sem erro técnico bruto).
String formatSalvarVendaErrorForUser(Object e) {
  final root = unwrapDartInteropError(e);

  if (root is VendaPersistenciaInconsistenciaCritica) {
    return _mensagemInconsistenciaCriticaVenda();
  }

  if (root is PendingStockSyncRequiredException) {
    return root.message;
  }

  final detalhe = formatDartErrorForUser(e);
  final lower = detalhe.toLowerCase();

  if (lower.contains('não foi possível sincronizar o estoque') ||
      lower.contains('alteração de estoque ainda não sincronizada') ||
      lower.contains('alteracao de estoque ainda nao sincronizada')) {
    return detalhe;
  }

  if (_textoErroInutilParaUsuario(detalhe) ||
      detalhe.startsWith('Falha na operação')) {
    return 'Não foi possível concluir a venda. Tente novamente.';
  }

  if (lower.contains('falha ao persistir venda local') &&
      lower.contains('restaurar estoque')) {
    return _mensagemInconsistenciaCriticaVenda();
  }

  if (lower.contains('estoque insuficiente') ||
      (lower.contains('insuficiente') && lower.contains('estoque')) ||
      lower.contains('disponível:') && lower.contains('solicitado:')) {
    return detalhe.startsWith('Estoque')
        ? detalhe
        : 'Estoque insuficiente. $detalhe';
  }
  if (lower.contains('produto não encontrado') ||
      lower.contains('nao encontrado no estoque') ||
      lower.contains('não encontrado no estoque') ||
      lower.contains('not-found')) {
    return detalhe.contains('estoque') || detalhe.contains('nuvem')
        ? detalhe
        : 'Produto não encontrado no estoque. $detalhe';
  }
  if (lower.contains('variação') ||
      lower.contains('variacao') ||
      lower.contains('tamanho') && lower.contains('obrigat')) {
    return detalhe;
  }
  if (lower.contains('permission') ||
      lower.contains('permission-denied') ||
      lower.contains('permiss')) {
    return 'Sem permissão para concluir a venda. Verifique login e acesso à loja.';
  }
  if (lower.contains('failed-precondition') ||
      lower.contains('aborted') ||
      lower.contains('stock revision') ||
      lower.contains('revision conflict') ||
      lower.contains('os dados de estoque')) {
    return 'Os dados de estoque deste produto foram atualizados. '
        'Atualize a tela e tente novamente.';
  }
  if (lower.contains('already-exists') || lower.contains('já foi registrada')) {
    return 'Esta venda já foi registrada. Atualize a tela antes de repetir.';
  }
  if (lower.contains('invalid-argument') || lower.contains('dados inválidos')) {
    return 'Dados inválidos para concluir a venda. Verifique os itens e tente novamente.';
  }
  if (lower.contains('network') ||
      lower.contains('unavailable') ||
      lower.contains('deadline-exceeded') ||
      lower.contains('offline')) {
    return 'Falha de conexão ao salvar a venda. Verifique a internet e tente novamente.';
  }
  // "conex" sozinho aparece em mensagens genéricas ("Verifique conexão") —
  // não tratar como falha de rede real.
  if (lower.contains('sincroniz') || lower.contains('nuvem')) {
    return detalhe;
  }
  return detalhe;
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
