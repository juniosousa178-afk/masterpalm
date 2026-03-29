// lib/widgets/update_app_dialog.dart
// Diálogo exibido quando há nova versão do app disponível

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_update_service.dart';
import '../services/notificacao_centro_service.dart';

/// Diálogo que informa sobre atualização disponível e permite baixar/instalar
class UpdateAppDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const UpdateAppDialog({super.key, required this.info});

  static Future<void> showIfNeeded(BuildContext context) async {
    final update = await AppUpdateService.checkForUpdate();
    if (update == null || !context.mounted) return;

    // Adicionar ao centro de notificações (badge na barra) com URL para abrir ao tocar
    NotificacaoCentroService().add(
      titulo: 'Atualização disponível',
      corpo: 'Nova versão ${update.latestVersion} do MasterPalm. Toque para ir ao site e baixar.',
      tipo: TipoNotificacaoCentro.atualizacaoApk,
      acaoArgs: {'url': update.downloadUrl},
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateAppDialog(info: update),
    );
  }

  Future<void> _onAtualizar(BuildContext context) async {
    final uri = Uri.tryParse(info.downloadUrl);
    if (uri == null) return;
    final ok = await AppUpdateService.openDownload(uri);
    if (context.mounted) {
      Navigator.of(context).pop();
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O download foi iniciado. Instale o APK quando o download terminar.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o link: ${info.downloadUrl}'),
            action: SnackBarAction(
              label: 'Copiar',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: info.downloadUrl));
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Atualização disponível',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Uma nova versão do MasterPalm está disponível.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Sua versão: ${info.currentVersion}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            Text(
              'Nova versão: ${info.latestVersion}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            if (info.changelog.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Novidades e correções:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  info.changelog,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Clique em "Atualizar" para baixar e instalar a nova versão.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Depois'),
        ),
        FilledButton.icon(
          onPressed: () => _onAtualizar(context),
          icon: const Icon(Icons.download, size: 20),
          label: const Text('Atualizar'),
        ),
      ],
    );
  }
}
