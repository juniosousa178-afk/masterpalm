// Painel Rodapé: bandeiras, links sociais, empresa e card informativo (part da mesma library).

part of 'loja_config_screen.dart';

class _PaneRodapeWidget extends StatelessWidget {
  const _PaneRodapeWidget({required this.host});

  final _LojaConfigScreenState host;

  static const List<String> _allPayments = [
    'mastercard',
    'visa',
    'hipercard',
    'amex',
    'diners',
    'elo',
    'pix',
    'boleto',
    'transfer',
    'barcode',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Section(
          title: 'Formas de pagamento (bandeiras)',
          child: Column(
            children: _allPayments.map((p) {
              final selected = host._payments.contains(p);
              return CheckboxListTile(
                title: Text(p.toUpperCase()),
                value: selected,
                onChanged: (v) => host._rodapeOnPaymentChanged(p, v),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        _Section(
          title: 'Links do Rodapé',
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 700;
            final firstRow = narrow
                ? Column(
                    children: [
                      TextField(
                        controller: host._instagramCtrl,
                        onChanged: (_) => host._scheduleAutoSave(),
                        decoration: const InputDecoration(
                          labelText: 'Instagram (URL)',
                          prefixIcon: Icon(Icons.camera_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: host._facebookCtrl,
                        onChanged: (_) => host._scheduleAutoSave(),
                        decoration: const InputDecoration(
                          labelText: 'Facebook (URL)',
                          prefixIcon: Icon(Icons.facebook_outlined),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: host._instagramCtrl,
                          onChanged: (_) => host._scheduleAutoSave(),
                          decoration: const InputDecoration(
                            labelText: 'Instagram (URL)',
                            prefixIcon: Icon(Icons.camera_alt_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: host._facebookCtrl,
                          onChanged: (_) => host._scheduleAutoSave(),
                          decoration: const InputDecoration(
                            labelText: 'Facebook (URL)',
                            prefixIcon: Icon(Icons.facebook_outlined),
                          ),
                        ),
                      ),
                    ],
                  );

            final newSocialRow = narrow
                ? Column(
                    children: [
                      TextField(
                        controller: host._tiktokCtrl,
                        onChanged: (_) => host._scheduleAutoSave(),
                        decoration: const InputDecoration(
                          labelText: 'TikTok (URL)',
                          prefixIcon: Icon(Icons.music_note),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: host._telegramCtrl,
                        onChanged: (_) => host._scheduleAutoSave(),
                        decoration: const InputDecoration(
                          labelText: 'Telegram (URL)',
                          prefixIcon: Icon(Icons.send),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: host._tiktokCtrl,
                          onChanged: (_) => host._scheduleAutoSave(),
                          decoration: const InputDecoration(
                            labelText: 'TikTok (URL)',
                            prefixIcon: Icon(Icons.music_note),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: host._telegramCtrl,
                          onChanged: (_) => host._scheduleAutoSave(),
                          decoration: const InputDecoration(
                            labelText: 'Telegram (URL)',
                            prefixIcon: Icon(Icons.send),
                          ),
                        ),
                      ),
                    ],
                  );

            final thirdSocialRow = narrow
                ? Column(
                    children: [
                      TextField(
                        controller: host._kwaiCtrl,
                        onChanged: (_) => host._scheduleAutoSave(),
                        decoration: const InputDecoration(
                          labelText: 'Kwai (URL)',
                          prefixIcon: Icon(Icons.video_library),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: host._linkedinCtrl,
                        onChanged: (_) => host._scheduleAutoSave(),
                        decoration: const InputDecoration(
                          labelText: 'LinkedIn (URL)',
                          prefixIcon: Icon(Icons.business),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: host._kwaiCtrl,
                          onChanged: (_) => host._scheduleAutoSave(),
                          decoration: const InputDecoration(
                            labelText: 'Kwai (URL)',
                            prefixIcon: Icon(Icons.video_library),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: host._linkedinCtrl,
                          onChanged: (_) => host._scheduleAutoSave(),
                          decoration: const InputDecoration(
                            labelText: 'LinkedIn (URL)',
                            prefixIcon: Icon(Icons.business),
                          ),
                        ),
                      ),
                    ],
                  );

            final secondRow = TextField(
              controller: host._trocasCtrl,
              onChanged: (_) => host._scheduleAutoSave(),
              decoration: const InputDecoration(
                labelText: 'Trocas & devoluções (URL)',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                helperText:
                    'A página "Sobre a loja" é configurada em Menu e páginas, acima.',
              ),
            );

            final emailRow = TextField(
              controller: host._emailRodapeCtrl,
              onChanged: (_) => host._scheduleAutoSave(),
              decoration: const InputDecoration(
                labelText: 'Email de contato',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            );

            final whatsappRow = TextField(
              controller: host._whatsappRodapeCtrl,
              focusNode: host._focusWhatsappRodape,
              onChanged: (_) {
                host._limparErroCampo('whatsapp_rodape');
                host._scheduleAutoSave();
              },
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\s\-+()]')),
              ],
              decoration: InputDecoration(
                labelText: 'WhatsApp de contato',
                prefixIcon: const Icon(Icons.phone_outlined),
                helperText: 'Ex: 5533999999999',
                helperStyle: const TextStyle(fontSize: 11),
                errorText: host._camposComErro.contains('whatsapp_rodape')
                    ? 'Use 10 a 15 dígitos'
                    : null,
                errorBorder: OutlineInputBorder(
                  borderSide:
                      const BorderSide(color: _LojaConfigScreenState._errorColor, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );

            return Column(
              children: [
                firstRow,
                const SizedBox(height: 10),
                newSocialRow,
                const SizedBox(height: 10),
                thirdSocialRow,
                const SizedBox(height: 10),
                emailRow,
                const SizedBox(height: 10),
                whatsappRow,
                const SizedBox(height: 10),
                secondRow,
                const SizedBox(height: 10),
                TextField(
                  controller: host._loginCtrl,
                  onChanged: (_) => host._scheduleAutoSave(),
                  decoration: const InputDecoration(
                    labelText: 'Link de login (opcional)',
                    prefixIcon: Icon(Icons.lock_open_outlined),
                  ),
                ),
              ],
            );
          }),
        ),

        const SizedBox(height: 16),

        _Section(
          title: 'Empresa no Rodapé',
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 700;
            if (narrow) {
              return Column(
                children: [
                  TextField(
                    controller: host._razaoCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Razão social',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: host._cnpjCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'CNPJ',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: host._razaoCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Razão social',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: host._cnpjCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'CNPJ',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),

        const SizedBox(height: 16),

        const Card(
          elevation: 0,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funciona?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                _PaneMutedIntroText(
                  '? Salvar rascunho grava localmente e em lojas/{store_id}/draft_config/config.\n'
                  '? Publicar copia o rascunho para lojas/{store_id}/config/config e também espelha no doc raiz.\n'
                  '? O Catálogo Web lê os dados publicados (config/config).',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
