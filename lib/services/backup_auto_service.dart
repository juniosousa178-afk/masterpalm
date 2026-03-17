// lib/services/backup_auto_service.dart
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../services/loja_id_service.dart';
import '../services/notificacao_service.dart';

class BackupAutoService {
  static const String _boxName = 'backup_auto_control';
  static const int _retencaoDias = 7;

  /// Chamar no main.dart após iniciar Hive
  static Future<void> iniciarAgendamento() async {
    final box = await Hive.openBox(_boxName);

    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);

    final ultimo = box.get('ultimo_backup') as DateTime?;
    if (ultimo != null) {
      final ultimoDia = DateTime(ultimo.year, ultimo.month, ultimo.day);
      if (ultimoDia == hoje) {
        // já executou hoje
        return;
      }
    }

    // Hora programada: 03:00
    final horarioBackup = DateTime(agora.year, agora.month, agora.day, 3, 0);

    if (agora.isBefore(horarioBackup)) {
      // ainda não deu 03:00 → agenda para HOJE às 03:00
      final delay = horarioBackup.difference(agora);
      Future.delayed(delay, () => _executarBackup(box));
    } else {
      // 03:00 já passou → agenda para amanhã às 03:00
      final amanha = horarioBackup.add(const Duration(days: 1));
      final delay = amanha.difference(agora);
      Future.delayed(delay, () => _executarBackup(box));
    }
  }

  /// Executa o backup da loja definida
  /// ✅ Multi-loja: LojaIdService.get() primeiro (StoreResolver), sessao só fallback offline
  static Future<void> _executarBackup(Box box) async {
    try {
      var storeId = (await LojaIdService.get())?.toString().trim();
      if (storeId == null || storeId.isEmpty) {
        final sessao = Hive.box('sessao');
        storeId = (sessao.get('store_id') ?? sessao.get('storeId'))?.toString().trim();
      }
      if (storeId == null || storeId.isEmpty) {
        debugPrint('Backup automático: nenhuma loja ativa, pulando.');
        return;
      }

      final dir = await getApplicationDocumentsDirectory();

      // Criar pasta temporária da loja
      final tempDir = Directory('${dir.path}/temp_backup_$storeId');
      if (!await tempDir.exists()) {
        await tempDir.create();
      }

      // Copiar apenas arquivos da loja
      final files = dir.listSync();
      for (final f in files) {
        final name = f.uri.pathSegments.last;

        if (name.contains(storeId) || name == 'sessao.hive') {
          final dest = File('${tempDir.path}/$name');
          await dest.writeAsBytes(await File(f.path).readAsBytes());
        }
      }

      // Criar arquivo ZIP com data
      final zipPath =
          '${dir.path}/backup_${storeId}_${DateTime.now().toIso8601String().split("T").first}.zip';

      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addDirectory(tempDir);
      encoder.close();

      // Atualiza última execução
      box.put('ultimo_backup', DateTime.now());

      await NotificacaoService.enviarNotificacao(
      titulo: 'Backup concluído',
      corpo: 'Backup da loja $storeId foi realizado com sucesso!',
);
      // Apaga backups antigos
      await _limparBackupsAntigos(dir.path, storeId);
    } catch (e) {
      // se der erro, tenta de novo amanhã
      debugPrint('Erro no backup automático (type=${e.runtimeType})');
    }
  }

  /// Mantém somente os últimos X dias de backup
  static Future<void> _limparBackupsAntigos(String baseDir, String storeId) async {
    final dir = Directory(baseDir);
    final arquivos = dir.listSync().where((f) =>
        f.path.contains('backup_$storeId') && f.path.endsWith('.zip'));

    final limite = DateTime.now().subtract(const Duration(days: _retencaoDias));

    for (final f in arquivos) {
      final stats = await FileStat.stat(f.path);
      if (stats.changed.isBefore(limite)) {
        try {
          await File(f.path).delete();
        } catch (_) {}
      }
    }
  }
}