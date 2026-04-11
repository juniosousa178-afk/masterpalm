import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../services/cloud_sync_service.dart'; // pushAll()
import '../utils/role_utils.dart';

/// Barra administrativa para publicar o rascunho no site diretamente do Catálogo Público.
/// Só aparece para programador/admin/root.
class AdminPublishBar extends StatefulWidget {
  final String slug; // lojas/{slug}
  final EdgeInsetsGeometry? padding;
  const AdminPublishBar({super.key, required this.slug, this.padding});

  @override
  State<AdminPublishBar> createState() => _AdminPublishBarState();
}

class _AdminPublishBarState extends State<AdminPublishBar> {
  bool _busy = false;

  bool get _canPublish {
    // 1) Sessão local (Hive) — seu app já grava isso
    try {
      final tipo = Hive.box('sessao').get('tipo_usuario')?.toString();
      if (tipo == 'programador' || tipo == 'admin') return true;
    } catch (_) {}

    // 2) Root (fallback — mesma lista que RoleUtils)
    final email = FirebaseAuth.instance.currentUser?.email;
    if (RoleUtils.isRootEmail(email)) return true;

    // 3) Web: ?admin=1 (útil p/ testes)
    if (kIsWeb) {
      final adminFlag = Uri.base.queryParameters['admin'];
      if (adminFlag == '1' || adminFlag == 'true') return true;
    }

    return false;
  }

  Future<void> _publicarTudo() async {
    if (!_canPublish || _busy) return;
    setState(() => _busy = true);
    final slug = widget.slug.trim();
    try {
      debugPrint('🚀 [ADMIN-BAR] Iniciando publicação para loja: $slug');
      // 1) lê rascunho
      final base = FirebaseFirestore.instance.collection('lojas').doc(slug);
      final draftRef = base.collection('draft_config').doc('config');
      final liveRef = base.collection('config').doc('config'); // ✅ CORRIGIDO: era draft_config

      final snap = await draftRef.get();
      final draftData = (snap.data() ?? <String, dynamic>{});

      // 2) escreve "ao vivo"
      debugPrint('📋 [ADMIN-BAR] Publicando config (merge: true)');
      await liveRef.set(draftData, SetOptions(merge: true));

      // 3) espelha no doc raiz (compat)
      await base.set({
        'slug': slug,
        'updatedAt': FieldValue.serverTimestamp(),
        'config': draftData,
        ...draftData,
      }, SetOptions(merge: true));

      // 4) sincroniza (perfil + produtos) com o site
      debugPrint('🔄 [ADMIN-BAR] Sincronizando produtos...');
      // REMOVIDO CloudSyncService.pushAll() - sobrescreve configurações!
      // await CloudSyncService.pushAll();

      debugPrint('✅ [ADMIN-BAR] Publicação concluída com sucesso!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Publicado com sucesso!')),
        );
      }
    } catch (e) {
      debugPrint('❌ [ADMIN-BAR] Erro ao publicar (type=${e.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Falha ao publicar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forcarSync() async {
    if (!_canPublish || _busy) return;
    setState(() => _busy = true);
    try {
      await CloudSyncService.pushAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🔄 Sincronizado com o site.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Falha ao sincronizar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canPublish) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      child: Material(
        elevation: 6,
        color: Colors.white,
        child: Padding(
          padding: widget.padding ?? const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _publicarTudo,
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(_busy ? 'Publicando...' : 'Publicar no site'),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _forcarSync,
                icon: const Icon(Icons.sync),
                label: const Text('Forçar sync'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
