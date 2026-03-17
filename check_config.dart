// check_config.dart - Verifica configuração publicada no Firestore
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  print('🔍 Verificando configuração do catálogo...\n');

  try {
    await Firebase.initializeApp();
    print('✅ Firebase inicializado\n');

    const lojaId = 'masterpalm_gmail_com'; // Altere se necessário

    print('Loja: $lojaId\n');
    print('=' * 60);

    // Verificar draft_config
    print('\n📝 DRAFT (Rascunho) - lojas/$lojaId/draft_config/config:');
    final draftDoc = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(lojaId)
        .collection('draft_config')
        .doc('config')
        .get();

    if (draftDoc.exists) {
      final data = draftDoc.data();
      final theme = data?['theme'];
      print('  ✅ Existe');
      print('  theme.primaria: ${theme?['primaria']}');
      if (theme?['primaria'] != null) {
        final color = theme['primaria'] as int;
        print('  Cor hex: #${color.toRadixString(16).padLeft(8, '0').toUpperCase()}');
      }
    } else {
      print('  ❌ NÃO existe');
    }

    // Verificar config (LIVE/Publicado)
    print('\n🌐 LIVE (Publicado) - lojas/$lojaId/config/config:');
    final liveDoc = await FirebaseFirestore.instance
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('config')
        .get();

    if (liveDoc.exists) {
      final data = liveDoc.data();
      final theme = data?['theme'];
      print('  ✅ Existe');
      print('  theme.primaria: ${theme?['primaria']}');
      if (theme?['primaria'] != null) {
        final color = theme['primaria'] as int;
        print('  Cor hex: #${color.toRadixString(16).padLeft(8, '0').toUpperCase()}');
      }
    } else {
      print('  ❌ NÃO existe');
    }

    print('\n${'=' * 60}');
    print('\n💡 DIAGNÓSTICO:');

    if (!liveDoc.exists || liveDoc.data()?['theme'] == null) {
      print('  ❌ Configuração NÃO foi publicada!');
      print('  📱 Abra o app, vá em "Configurações da Loja"');
      print('  📤 Clique na aba "Publicar"');
      print('  🟣 Clique no botão roxo "PUBLICAR CATÁLOGO (TORNAR VISÍVEL)"');
    } else if (draftDoc.data()?['theme']?['primaria'] != liveDoc.data()?['theme']?['primaria']) {
      print('  ⚠️  Configuração publicada está DESATUALIZADA!');
      print('  📱 Publique novamente para aplicar as alterações mais recentes');
    } else {
      print('  ✅ Configuração está PUBLICADA e ATUALIZADA!');
      print('  🌐 Web catalog deve mostrar as cores corretas');
    }

  } catch (e, stack) {
    print('\n❌ ERRO (type=${e.runtimeType})');
    print('\n$stack');
  }
}
