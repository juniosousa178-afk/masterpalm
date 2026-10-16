import 'package:flutter/material.dart';

import 'consignment_errors.dart';
import 'consignment_models.dart';
import 'consignment_service.dart';

const consignmentHideTotalReturnLabel = 'Excluir da lista';
const consignmentHideTotalReturnMessage =
    'Essa consignação foi encerrada com devolução total.\n'
    'Ela será removida das listas, mas o histórico continuará preservado.';
const consignmentHiddenMessage = 'Consignação removida da lista.';
const consignmentHideUnavailableMessage =
    'Esta opção ainda não está disponível. Tente novamente mais tarde.';

/// Confirms and hides a settled total-return consignment. Returns true when the server hid it.
Future<bool> confirmAndHideTotalReturn(
  BuildContext context, {
  required String lojaId,
  required ConsignmentDoc doc,
}) async {
  if (!doc.canHideFromList) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(consignmentHideTotalReturnLabel),
      content: const Text(consignmentHideTotalReturnMessage),
      actions: [
        TextButton(
          key: const Key('consignment_hide_cancel'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('consignment_hide_confirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(consignmentHideTotalReturnLabel),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ConsignmentService.hideTotalReturn(lojaId: lojaId, consignmentId: doc.id);
    messenger.showSnackBar(const SnackBar(content: Text(consignmentHiddenMessage)));
    return true;
  } catch (e) {
    final msg = e is ConsignmentException
        ? (e.code == 'INVALID_ARGUMENT' ? consignmentHideUnavailableMessage : e.message)
        : ConsignmentException.userMessage('SERVER', e.toString());
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }
}
