// lib/services/notificacao_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

class NotificacaoService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Inicialização do sistema de notificações
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(
      android: android,
    );

    await _plugin.initialize(settings);
  }

  /// Notificação simples
  static Future<void> enviarNotificacao({
    required String titulo,
    required String corpo,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'backup_channel',
      'Backup Automático',
      channelDescription: 'Notificações de backup do sistema MasterPalm',
      importance: Importance.max,
      priority: Priority.high,
    );

    const detalhes = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      titulo,
      corpo,
      detalhes,
    );
  }

  /// Notificação agendada — opcional se você quiser no futuro
  static Future<void> agendarNotificacaoDiaria() async {
    const androidDetails = AndroidNotificationDetails(
      'agenda_channel',
      'Agendamentos',
      channelDescription: 'Notificações agendadas do sistema MasterPalm',
      importance: Importance.max,
      priority: Priority.high,
    );

    const detalhes = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      12345,
      'Rotina de backup',
      'Backup diário será executado agora.',
      tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5)),
      detalhes,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ============================================================
  // ENVIO DE NÚMEROS DA SORTE VIA WHATSAPP E EMAIL
  // ============================================================

  /// Envia os números da sorte via WhatsApp
  ///
  /// Abre o WhatsApp Web/App com mensagem pré-formatada
  static Future<bool> enviarWhatsApp({
    required String telefone,
    required String clienteNome,
    required List<String> numeros,
    required List<Map<String, dynamic>> campanhas,
    String lojaNome = 'MasterPalm',
  }) async {
    if (telefone.isEmpty || numeros.isEmpty) return false;

    // Remove caracteres especiais do telefone
    final tel = telefone.replaceAll(RegExp(r'[^\d]'), '');

    // Monta a mensagem
    final buffer = StringBuffer();
    buffer.writeln('Olá $clienteNome! 🎉');
    buffer.writeln('');
    buffer.writeln('Parabéns pela sua compra na $lojaNome!');
    buffer.writeln('');

    if (numeros.length == 1) {
      buffer.writeln('🎟️ Você ganhou 1 número da sorte:');
      buffer.writeln('*${numeros.first}*');
    } else {
      buffer.writeln('🎟️ Você ganhou ${numeros.length} números da sorte:');
      for (final numero in numeros) {
        buffer.writeln('*$numero*');
      }
    }

    buffer.writeln('');
    buffer.writeln('📋 Detalhes da(s) campanha(s):');
    buffer.writeln('');

    for (final campanha in campanhas) {
      buffer.writeln('🏆 *${campanha['nome']}*');
      if (campanha['descricao']?.toString().isNotEmpty == true) {
        buffer.writeln(campanha['descricao']);
      }
      buffer.writeln('Prêmio: ${campanha['premioDescricao']}');

      // Data do sorteio
      final dataSorteio = campanha['dataSorteio'];
      if (dataSorteio != null) {
        final data = dataSorteio is DateTime
          ? dataSorteio
          : (dataSorteio as dynamic).toDate();
        buffer.writeln('Data do sorteio: ${_formatarData(data)}');
      }

      buffer.writeln('');
    }

    buffer.writeln('Boa sorte! 🍀');

    // URL encode da mensagem
    final mensagem = Uri.encodeComponent(buffer.toString());
    final url = 'https://wa.me/$tel?text=$mensagem';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('❌ Erro ao enviar WhatsApp (type=${e.runtimeType})');
      return false;
    }
  }

  /// Envia email com os números da sorte
  ///
  /// Abre o app de email padrão com mensagem pré-formatada
  static Future<bool> enviarEmail({
    required String email,
    required String clienteNome,
    required List<String> numeros,
    required List<Map<String, dynamic>> campanhas,
    String lojaNome = 'MasterPalm',
  }) async {
    if (email.isEmpty || numeros.isEmpty) return false;

    // Assunto do email
    final assunto = Uri.encodeComponent('Seus números da sorte - $lojaNome');

    // Corpo do email
    final buffer = StringBuffer();
    buffer.writeln('Olá $clienteNome!');
    buffer.writeln('');
    buffer.writeln('Parabéns pela sua compra na $lojaNome!');
    buffer.writeln('');

    if (numeros.length == 1) {
      buffer.writeln('Você ganhou 1 número da sorte:');
      buffer.writeln(numeros.first);
    } else {
      buffer.writeln('Você ganhou ${numeros.length} números da sorte:');
      for (final numero in numeros) {
        buffer.writeln('• $numero');
      }
    }

    buffer.writeln('');
    buffer.writeln('Detalhes da(s) campanha(s):');
    buffer.writeln('');

    for (final campanha in campanhas) {
      buffer.writeln('${campanha['nome']}');
      if (campanha['descricao']?.toString().isNotEmpty == true) {
        buffer.writeln(campanha['descricao']);
      }
      buffer.writeln('Prêmio: ${campanha['premioDescricao']}');

      // Data do sorteio
      final dataSorteio = campanha['dataSorteio'];
      if (dataSorteio != null) {
        final data = dataSorteio is DateTime
          ? dataSorteio
          : (dataSorteio as dynamic).toDate();
        buffer.writeln('Data do sorteio: ${_formatarData(data)}');
      }

      buffer.writeln('');
    }

    buffer.writeln('Boa sorte!');
    buffer.writeln('');
    buffer.writeln('---');
    buffer.writeln('Equipe $lojaNome');

    final corpo = Uri.encodeComponent(buffer.toString());
    final url = 'mailto:$email?subject=$assunto&body=$corpo';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return false;
    } catch (e) {
      debugPrint('❌ Erro ao enviar email (type=${e.runtimeType})');
      return false;
    }
  }

  /// Formata data para exibição
  static String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year;
    return '$dia/$mes/$ano';
  }

  /// Envia notificação completa (WhatsApp + Email)
  ///
  /// Retorna mapa com status de cada envio
  static Future<Map<String, bool>> enviarNotificacoes({
    required String clienteNome,
    required String? telefone,
    required String? email,
    required List<String> numeros,
    required List<Map<String, dynamic>> campanhas,
    String lojaNome = 'MasterPalm',
  }) async {
    final resultado = <String, bool>{
      'whatsapp': false,
      'email': false,
    };

    // Envia WhatsApp se tiver telefone
    if (telefone != null && telefone.isNotEmpty) {
      resultado['whatsapp'] = await enviarWhatsApp(
        telefone: telefone,
        clienteNome: clienteNome,
        numeros: numeros,
        campanhas: campanhas,
        lojaNome: lojaNome,
      );
    }

    // Envia Email se tiver email
    if (email != null && email.isNotEmpty) {
      resultado['email'] = await enviarEmail(
        email: email,
        clienteNome: clienteNome,
        numeros: numeros,
        campanhas: campanhas,
        lojaNome: lojaNome,
      );
    }

    return resultado;
  }
}