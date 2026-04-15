// ARQUIVO: lib/screens/configuracoes/canais_meta_widgets.dart
// Widgets das tabs (WhatsApp, Instagram, Messenger)

part of 'canais_meta_screen.dart';

// Extension methods for the _CanaisMetaScreenState class
extension _CanaisMetaWidgets on _CanaisMetaScreenState {
  // ========== TAB WHATSAPP ==========
  Widget _buildWhatsAppTabImpl() {
    return RefreshIndicator(
      onRefresh: _loadConfigs,
      color: _CanaisMetaScreenState._primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            _buildChannelHeader(
              icon: Icons.chat,
              color: _CanaisMetaScreenState._whatsappColor,
              title: 'WhatsApp Cloud API',
              subtitle: 'Responda automaticamente no WhatsApp Business',
              enabled: _whatsappEnabled,
              onToggle: _setWhatsAppEnabled,
            ),

            const SizedBox(height: 20),

            // Status
            if (_whatsappStatus != null) _buildStatusCard(_whatsappStatus!),
            if (_whatsappStatus != null) const SizedBox(height: 16),

            // Phone Number ID
            _buildModernTextField(
              controller: _whatsappPhoneNumberIdController,
              label: 'Phone Number ID',
              hint: '123456789012345',
              icon: Icons.phone,
              helperText: 'Encontre em: WhatsApp > API Setup',
              enabled: _whatsappEnabled,
              required: true,
            ),

            const SizedBox(height: 16),

            // Business Account ID
            _buildModernTextField(
              controller: _whatsappBusinessAccountIdController,
              label: 'Business Account ID',
              hint: '123456789012345',
              icon: Icons.business,
              helperText: 'WhatsApp Business Account ID',
              enabled: _whatsappEnabled,
              required: true,
            ),

            const SizedBox(height: 16),

            // Access Token
            _buildModernTextField(
              controller: _whatsappAccessTokenController,
              label: 'Access Token',
              hint: 'EAAxxxxxxxxxxxxxxxxxxxxx',
              icon: Icons.key,
              helperText: 'Token gerado no Meta Developers',
              enabled: _whatsappEnabled,
              required: true,
              obscureText: !_whatsappTokenVisible,
              suffixIcon: IconButton(
                icon: Icon(
                  _whatsappTokenVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: _CanaisMetaScreenState._primaryColor,
                ),
                onPressed: () =>
                    _setWhatsAppTokenVisible(!_whatsappTokenVisible),
                tooltip:
                    _whatsappTokenVisible ? 'Ocultar token' : 'Mostrar token',
              ),
            ),

            const SizedBox(height: 16),

            // Template Name
            _buildModernTextField(
              controller: _whatsappTemplateNameController,
              label: 'Template Name (opcional)',
              hint: 'hello_world',
              icon: Icons.message,
              helperText: 'Para mensagens fora da janela 24h',
              enabled: _whatsappEnabled,
            ),

            const SizedBox(height: 24),

            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.help_outline),
                    label: const Text('Guia'),
                    onPressed: _showWhatsAppGuide,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _CanaisMetaScreenState._whatsappColor,
                      side: const BorderSide(
                          color: _CanaisMetaScreenState._whatsappColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Testar'),
                    onPressed:
                        _whatsappEnabled ? _testWhatsAppConnection : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Salvar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _savingWhatsApp
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                    _savingWhatsApp ? 'Salvando...' : 'Salvar Configurações'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: _CanaisMetaScreenState._whatsappColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _whatsappEnabled && !_savingWhatsApp
                    ? _saveWhatsAppConfig
                    : null,
              ),
            ),

            const SizedBox(height: 24),

            // Webhook Info
            _buildWebhookInfo(
              'WhatsApp',
              'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp',
              _CanaisMetaScreenState._whatsappColor,
            ),
          ],
        ),
      ),
    );
  }

  // ========== TAB INSTAGRAM ==========
  Widget _buildInstagramTabImpl() {
    return RefreshIndicator(
      onRefresh: _loadConfigs,
      color: _CanaisMetaScreenState._primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            _buildChannelHeader(
              icon: Icons.camera_alt,
              color: _CanaisMetaScreenState._instagramColor,
              title: 'Instagram Direct Messaging',
              subtitle: 'Responda automaticamente no Instagram Business',
              enabled: _instagramEnabled,
              onToggle: _setInstagramEnabled,
            ),

            const SizedBox(height: 20),

            // Status
            if (_instagramStatus != null) _buildStatusCard(_instagramStatus!),
            if (_instagramStatus != null) const SizedBox(height: 16),

            // Instagram Business Account ID
            _buildModernTextField(
              controller: _instagramBusinessAccountIdController,
              label: 'Instagram Business Account ID',
              hint: '17841405822304914',
              icon: Icons.account_circle,
              helperText: 'Encontre em: Instagram > API Setup',
              enabled: _instagramEnabled,
              required: true,
            ),

            const SizedBox(height: 16),

            // Page ID
            _buildModernTextField(
              controller: _instagramPageIdController,
              label: 'Page ID',
              hint: '108316244769394',
              icon: Icons.pages,
              helperText: 'ID da página vinculada ao Instagram',
              enabled: _instagramEnabled,
              required: true,
            ),

            const SizedBox(height: 16),

            // Page Access Token
            _buildModernTextField(
              controller: _instagramPageAccessTokenController,
              label: 'Page Access Token',
              hint: 'EAAxxxxxxxxxxxxxxxxxxxxx',
              icon: Icons.key,
              helperText: 'Token da página no Meta Developers',
              enabled: _instagramEnabled,
              required: true,
              obscureText: !_instagramTokenVisible,
              suffixIcon: IconButton(
                icon: Icon(
                  _instagramTokenVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: _CanaisMetaScreenState._primaryColor,
                ),
                onPressed: () =>
                    _setInstagramTokenVisible(!_instagramTokenVisible),
                tooltip:
                    _instagramTokenVisible ? 'Ocultar token' : 'Mostrar token',
              ),
            ),

            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'Como configurar o Instagram',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Guia'),
                      onPressed: _showInstagramGuide,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _CanaisMetaScreenState._instagramColor,
                        side: const BorderSide(
                            color: _CanaisMetaScreenState._instagramColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Testar'),
                    onPressed:
                        _instagramEnabled ? _testInstagramConnection : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _CanaisMetaScreenState._instagramColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Salvar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _savingInstagram
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                    _savingInstagram ? 'Salvando...' : 'Salvar Configurações'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: _CanaisMetaScreenState._instagramColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _instagramEnabled && !_savingInstagram
                    ? _saveInstagramConfig
                    : null,
              ),
            ),

            const SizedBox(height: 24),

            // Webhook Info
            _buildWebhookInfo(
              'Instagram',
              'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram',
              _CanaisMetaScreenState._instagramColor,
            ),
          ],
        ),
      ),
    );
  }

  // ========== TAB MESSENGER ==========
  Widget _buildMessengerTabImpl() {
    return RefreshIndicator(
      onRefresh: _loadConfigs,
      color: _CanaisMetaScreenState._primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            _buildChannelHeader(
              icon: Icons.messenger,
              color: _CanaisMetaScreenState._messengerColor,
              title: 'Facebook Messenger',
              subtitle: 'Responda automaticamente no Messenger',
              enabled: _messengerEnabled,
              onToggle: _setMessengerEnabled,
            ),

            const SizedBox(height: 20),

            // Status
            if (_messengerStatus != null) _buildStatusCard(_messengerStatus!),
            if (_messengerStatus != null) const SizedBox(height: 16),

            // Page ID
            _buildModernTextField(
              controller: _messengerPageIdController,
              label: 'Page ID',
              hint: '108316244769394',
              icon: Icons.pages,
              helperText: 'ID da página do Facebook',
              enabled: _messengerEnabled,
              required: true,
            ),

            const SizedBox(height: 16),

            // Page Access Token
            _buildModernTextField(
              controller: _messengerPageAccessTokenController,
              label: 'Page Access Token',
              hint: 'EAAxxxxxxxxxxxxxxxxxxxxx',
              icon: Icons.key,
              helperText: 'Token da página no Meta Developers',
              enabled: _messengerEnabled,
              required: true,
              obscureText: !_messengerTokenVisible,
              suffixIcon: IconButton(
                icon: Icon(
                  _messengerTokenVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: _CanaisMetaScreenState._primaryColor,
                ),
                onPressed: () =>
                    _setMessengerTokenVisible(!_messengerTokenVisible),
                tooltip:
                    _messengerTokenVisible ? 'Ocultar token' : 'Mostrar token',
              ),
            ),

            const SizedBox(height: 24),

            // Botões
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'Como configurar o Messenger',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.help_outline),
                      label: const Text('Guia'),
                      onPressed: _showMessengerGuide,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _CanaisMetaScreenState._messengerColor,
                        side: const BorderSide(
                            color: _CanaisMetaScreenState._messengerColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Testar'),
                    onPressed:
                        _messengerEnabled ? _testMessengerConnection : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Salvar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _savingMessenger
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                    _savingMessenger ? 'Salvando...' : 'Salvar Configurações'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: _CanaisMetaScreenState._messengerColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _messengerEnabled && !_savingMessenger
                    ? _saveMessengerConfig
                    : null,
              ),
            ),

            const SizedBox(height: 24),

            // Webhook Info
            _buildWebhookInfo(
              'Messenger',
              'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger',
              _CanaisMetaScreenState._messengerColor,
            ),
          ],
        ),
      ),
    );
  }

  // ========== WIDGETS COMUNS ==========
  Widget _buildChannelHeader({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool enabled,
    required Function(bool) onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Ativar ou desativar canal',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Switch(
                value: enabled,
                onChanged: onToggle,
                activeTrackColor: Colors.white.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String status) {
    final isSuccess = status.contains('?');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSuccess
            ? _CanaisMetaScreenState._successColor.withOpacity(0.1)
            : _CanaisMetaScreenState._errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? _CanaisMetaScreenState._successColor.withOpacity(0.3)
              : _CanaisMetaScreenState._errorColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSuccess
                  ? _CanaisMetaScreenState._successColor.withOpacity(0.2)
                  : _CanaisMetaScreenState._errorColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess
                  ? _CanaisMetaScreenState._successColor
                  : _CanaisMetaScreenState._errorColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status.replaceAll('? ', '').replaceAll('? ', ''),
              style: TextStyle(
                color: isSuccess
                    ? _CanaisMetaScreenState._successColor
                    : _CanaisMetaScreenState._errorColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String helperText,
    required bool enabled,
    bool required = false,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor =
        isDark ? cs.primary : _CanaisMetaScreenState._primaryColor;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        style: TextStyle(color: cs.onSurface),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(color: cs.onSurfaceVariant),
          hintText: hint,
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          helperText: helperText,
          helperStyle: TextStyle(color: cs.onSurfaceVariant),
          helperMaxLines: 2,
          prefixIcon: Icon(icon, color: primaryColor),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor:
              enabled ? cs.surfaceContainerHigh : cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: primaryColor,
              width: 2,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildWebhookInfo(String name, String url, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.webhook, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'Configuração do Webhook',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Webhook URL
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Webhook URL',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        url,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, size: 18, color: color),
                      onPressed: () => _copyToClipboard(url, 'Webhook URL'),
                      tooltip: 'Copiar',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Verify Token
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.vpn_key, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      'Verify Token',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        'masterpalm_verify_2026',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy, size: 18, color: color),
                      onPressed: () => _copyToClipboard(
                          'masterpalm_verify_2026', 'Verify Token'),
                      tooltip: 'Copiar',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Dica
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cole estas informações no Meta Developers ao configurar o webhook.',
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

