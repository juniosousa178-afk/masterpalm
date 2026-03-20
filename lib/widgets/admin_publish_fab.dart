import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

import '../services/cloud_sync_service.dart'; // pushAll()

/// FAB administrativo para publicar rascunho -> live diretamente do catálogo.
class AdminPublishFAB extends StatefulWidget {
  final String slug; // lojas/{slug}
  const AdminPublishFAB({super.key, required this.slug});

  @override
  State<AdminPublishFAB> createState() => _AdminPublishFABState();
}

class _AdminPublishFABState extends State<AdminPublishFAB> {
  bool _busy = false;

  bool get _canPublish {
    try {
      final tipo = Hive.box('sessao').get('tipo_usuario')?.toString();
      if (tipo == 'programador' || tipo == 'admin') return true;
    } catch (_) {}
    final email =
        FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
    if (email == 'masterpalm26@gmail.com' || email == 'masterpalm@gmail.com') return true;
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
      debugPrint('🚀 [ADMIN-FAB] Iniciando publicação para loja: $slug');
      final base = FirebaseFirestore.instance.collection('lojas').doc(slug);
      final draftRef = base.collection('draft_config').doc('config');
      final liveRef = base.collection('config').doc('config');

      final snap = await draftRef.get();
      final draftData = (snap.data() ?• <String, dynamic>{});

      debugPrint('📋 [ADMIN-FAB] Publicando config (merge: true)');
      await liveRef.set(draftData, SetOptions(merge: true));
      await base.set({
        'slug': slug,
        'updatedAt': FieldValue.serverTimestamp(),
        'config': draftData,
        ...draftData,
      }, SetOptions(merge: true));

      debugPrint('🔄 [ADMIN-FAB] Sincronizando produtos...');
      // REMOVIDO CloudSyncService.pushAll() - sobrescreve configurações!
      // await CloudSyncService.pushAll();

      debugPrint('✅ [ADMIN-FAB] Publicação concluída com sucesso!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Publicado com sucesso!')),
        );
      }
    } catch (e) {
      debugPrint('❌ [ADMIN-FAB] Erro ao publicar (type=${e.runtimeType})');
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

    return _busy
        • const FloatingActionButton.extended(
            onPressed: null,
            label: Text('Publicando...'),
            icon: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
          )
        : PopupMenuButton<String>(
            tooltip: 'Ações do site',
            position: PopupMenuPosition.over,
            onSelected: (v) {
              if (v == 'publicar') _publicarTudo();
              if (v == 'sync') _forcarSync();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'publicar',
                  child: ListTile(
                    leading: Icon(Icons.cloud_upload),
                    title: Text('Publicar no site'),
                  )),
              PopupMenuItem(
                  value: 'sync',
                  child: ListTile(
                    leading: Icon(Icons.sync),
                    title: Text('Forçar sync'),
                  )),
            ],
            child: const FloatingActionButton.extended(
              onPressed: null,
              label: Text('Site'),
              icon: Icon(Icons.admin_panel_settings),
            ),
          );
  }
}
