// lib/widgets/notificacao_centro_sheet.dart
// Bottom sheet com lista de notificações
// ✅ Multi-loja: usa StoreResolverFacade/LojaIdService (mesma lógica da loja modelo)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/loja_id_service.dart';
import '../services/notificacao_centro_service.dart';

class NotificacaoCentroSheet extends StatelessWidget {
  const NotificacaoCentroSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const NotificacaoCentroSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = NotificacaoCentroService();
    return FutureBuilder<String?>(
      future: LojaIdService.get(),
      builder: (context, snapshot) {
        final currentStoreId = snapshot.data?.trim().isNotEmpty == true
            ? snapshot.data!.trim()
            : null;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Notifica??es',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ListenableBuilder(
                          listenable: svc,
                          builder: (_, __) {
                            final unread = svc.unreadCountParaLoja(currentStoreId);
                            if (unread == 0) return const SizedBox.shrink();
                            return TextButton(
                              onPressed: () => svc.markAllAsReadParaLoja(currentStoreId),
                              child: const Text('Marcar todas como lidas'),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: svc,
                      builder: (_, __) {
                        final items = svc.itemsParaLoja(currentStoreId);
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhuma notifica??o',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final n = items[i];
                            return _NotificationTile(
                              notificacao: n,
                              onTap: () async {
                                await svc.markAsRead(n.id);
                                if (!context.mounted) return;
                                final nav = Navigator.of(context);
                                nav.pop();
                                final url = n.acaoArgs?['url']?.toString();
                                if (n.tipo == TipoNotificacaoCentro.atualizacaoApk &&
                                    url != null &&
                                    url.startsWith('http')) {
                                  final uri = Uri.tryParse(url);
                                  if (uri != null) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                  return;
                                }
                                if (n.acaoRota != null && n.acaoRota!.isNotEmpty) {
                                  nav.pushNamed(n.acaoRota!, arguments: n.acaoArgs);
                                }
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificacaoCentro notificacao;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notificacao,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = notificacao;
    final isNovoPedido = n.tipo == TipoNotificacaoCentro.novoPedido;
    final isAtualizacao = n.tipo == TipoNotificacaoCentro.atualizacaoApk;

    IconData icon = Icons.notifications;
    Color iconColor = Colors.blue;
    if (isNovoPedido) {
      icon = Icons.shopping_cart;
      iconColor = Colors.green;
    } else if (isAtualizacao) {
      icon = Icons.system_update;
      iconColor = Colors.orange;
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha:0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        n.titulo,
        style: TextStyle(
          fontWeight: n.lida ? FontWeight.normal : FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            n.corpo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha:0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(n.criadaEm),
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inHours < 1) return 'H? ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'H? ${diff.inHours}h';
    if (diff.inDays < 7) return 'H? ${diff.inDays} dias';
    return DateFormat('dd/MM').format(d);
  }
}

