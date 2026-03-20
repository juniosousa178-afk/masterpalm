
import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:logger/logger.dart';

final logger = Logger();

class EmailService {
  /// Envia email.
  /// [remetenteNome] – nome exibido como remetente (ex: "MasterPalm" para admin, nome da loja para cliente)
  /// [logoUrl] – URL da logo da loja para incluir no topo do email (HTML)
  static Future<bool> enviarEmail({
    required String destinatario,
    required String assunto,
    required String mensagem,
    String remetenteNome = 'MasterPalm',
    String• logoUrl,
  }) async {
    const smtpEmail = 'masterpalm26@gmail.com';
    const smtpSenha = 'vyicsfqbsghrbuuz'; // Senha de app (sem espaços)

    if (smtpEmail.contains('SEU_EMAIL') || smtpSenha == 'SENHA_DE_APP') {
      debugPrint('⚠️ [EMAIL] SMTP não configurado. Configure smtpEmail e smtpSenha em email_service.dart');
      return false;
    }

    debugPrint('📧 [EMAIL] Enviando para: $destinatario | assunto: $assunto');
    final smtpServer = gmail(smtpEmail, smtpSenha);

    final message = Message()
      ..from = Address(smtpEmail, remetenteNome)
      ..recipients.add(destinatario)
      ..subject = assunto;
    if (logoUrl != null && logoUrl.trim().isNotEmpty) {
      final escaped = mensagem
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('\n', '<br>');
      message.html = '''
<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;font-size:14px;color:#333;line-height:1.5;">
<div style="text-align:center;margin-bottom:20px;">
<img src="$logoUrl" alt="Logo" style="max-width:120px;max-height:80px;height:auto;" />
</div>
<div>$escaped</div>
</body></html>''';
    }
    message.text = mensagem;

    try {
      await send(message, smtpServer);
      return true;
    } catch (e) {
      logger.e('Erro ao enviar e-mail (type=${e.runtimeType})');
      debugPrint('⚠️ [EMAIL] Erro ao enviar (type=${e.runtimeType})');
      return false;
    }
  }
}
