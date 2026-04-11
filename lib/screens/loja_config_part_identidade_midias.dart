// Painéis Identidade & Contato e Mídias (part da mesma library que loja_config_screen.dart).
// Etapa 3 blast-radius: UI delegada ao State via [host], sem alterar regra.

part of 'loja_config_screen.dart';

class _PaneIdentidadeWidget extends StatelessWidget {
  const _PaneIdentidadeWidget({required this.host});

  final _LojaConfigScreenState host;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      title: 'Identidade & Contato',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slug (URL): ${host._activeStoreId()}',
            style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: host._nomeCtrl,
            focusNode: host._focusNomeLoja,
            style: host._fieldTextStyle(context),
            decoration: host._inputDecoration(
              context,
              labelText: 'Nome da loja',
              prefixIcon: const Icon(Icons.storefront_outlined),
            ),
            onChanged: (_) {
              host._setStateIfSlugEmptyFromNome();
              host._scheduleAutoSave();
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: host._slugCtrl,
            style: host._fieldTextStyle(context),
            decoration: host._inputDecoration(
              context,
              labelText: 'Slug (URL amigável)',
              helperText:
                  'Ex.: nathy_pratas_e_folheados\nURL: ${host._configBox.get('public_base_url') ?? 'https://app.mastepalm.com.br'}/loja/${host._slugCtrl.text.isNotEmpty ? host._slugCtrl.text : 'seu-slug'}',
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.link),
            ),
            onChanged: (value) {
              final sanitized = value
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
                  .replaceAll(RegExp(r'_+'), '_')
                  .replaceAll(RegExp(r'^_+|_+$'), '');
              if (sanitized != value) {
                host._slugCtrl.value = TextEditingValue(
                  text: sanitized,
                  selection: TextSelection.collapsed(offset: sanitized.length),
                );
              }
              host._setStateIdentidadeHelperRebuild();
              host._scheduleAutoSave();
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: host._linkCurtoCtrl,
            style: host._fieldTextStyle(context),
            decoration: host._inputDecoration(
              context,
              labelText: 'Link curto (opcional)',
              helperText:
                  'Ex.: nathy → app.mastepalm.com.br/c/nathy redireciona para seu catálogo',
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.short_text),
            ),
            onChanged: (value) {
              final sanitized =
                  value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
              if (sanitized != value) {
                host._linkCurtoCtrl.value = TextEditingValue(
                  text: sanitized,
                  selection: TextSelection.collapsed(offset: sanitized.length),
                );
              }
              host._setStateIdentidadeHelperRebuild();
              host._scheduleAutoSave();
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: host._subdominioMascaraCtrl,
                  style: host._fieldTextStyle(context),
                  decoration: host._inputDecoration(
                    context,
                    labelText: 'Subdomínio personalizado (opcional)',
                    helperText: 'Ex.: nathypratasefolheados',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.link),
                  ),
                  onChanged: (value) {
                    final sanitized =
                        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
                    if (sanitized != value) {
                      host._subdominioMascaraCtrl.value = TextEditingValue(
                        text: sanitized,
                        selection:
                            TextSelection.collapsed(offset: sanitized.length),
                      );
                    }
                    host._setStateIdentidadeHelperRebuild();
                    host._scheduleAutoSave();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: host._subdominioDominioBaseCtrl,
                  style: host._fieldTextStyle(context),
                  decoration: host._inputDecoration(
                    context,
                    labelText: 'Domínio base',
                    helperText: 'Ex.: mastepalm.com.br',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.domain),
                  ),
                  onChanged: (_) {
                    host._setStateIdentidadeHelperRebuild();
                    host._scheduleAutoSave();
                  },
                ),
              ),
            ],
          ),
          if (host._subdominioMascaraCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final m = host._subdominioMascaraCtrl.text
                    .trim()
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9-]'), '');
                final d = host._subdominioDominioBaseCtrl.text
                    .trim()
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9.-]'), '');
                final dominio = d.isNotEmpty ? d : 'mastepalm.com.br';
                return Text(
                  'URL com máscara: https://$m.$dominio',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 420,
                child: TextField(
                  controller: host._waCtrl,
                  focusNode: host._focusWaVendedor,
                  style: host._fieldTextStyle(context),
                  onChanged: (_) {
                    host._limparErroCampo('whatsapp');
                    host._scheduleAutoSave();
                  },
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\s\-+()]')),
                  ],
                  decoration: host._inputDecoration(
                    context,
                    labelText: 'WhatsApp do vendedor (E.164)',
                    helperText: 'Ex.: 5533999998888 (10 a 15 dígitos)',
                    errorText: host._camposComErro.contains('whatsapp')
                        ? 'Use 10 a 15 dígitos'
                        : null,
                    prefixIcon: const Icon(Icons.phone_iphone),
                  ),
                ),
              ),
              if (host._showsPedidoBaseUrlField)
                SizedBox(
                  width: 520,
                  child: TextField(
                    controller: host._pedidoBaseCtrl,
                    focusNode: host._focusPedidoBaseUrl,
                    style: host._fieldTextStyle(context),
                    onChanged: (_) {
                      host._limparErroCampo('pedido_base');
                      host._scheduleAutoSave();
                    },
                    decoration: host._inputDecoration(
                      context,
                      labelText: 'Link base do pedido',
                      helperText: 'Ex.: https://app.mastepalm.com.br/pedido',
                      errorText: host._camposComErro.contains('pedido_base')
                          ? 'URL inválida'
                          : null,
                      prefixIcon:
                          const Icon(Icons.shopping_cart_checkout_outlined),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            host._isFreeLimitedCatalog
                ? 'No plano gratuito o catálogo envia o cliente para o WhatsApp. Link de pedido online e checkout ficam nos planos pagos.'
                : host._isBasicCatalog
                    ? 'No Básico o pedido no catálogo continua pelo WhatsApp. Link de checkout online libera no Intermediário.'
                    : 'Essas informações alimentam o link de pedido no catálogo público e o botão de WhatsApp.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PaneMidiasWidget extends StatelessWidget {
  const _PaneMidiasWidget({required this.host});

  final _LojaConfigScreenState host;

  InputDecoration _dec(BuildContext context, String label) =>
      host._inputDecoration(context, labelText: label);

  Widget _dimRow({
    required TextEditingController h,
    required TextEditingController w,
  }) {
    return LayoutBuilder(builder: (context, c) {
      final isNarrow = c.maxWidth < 420;
      final row = Row(
        children: [
          Expanded(
            child: TextField(
              controller: h,
              style: host._fieldTextStyle(context),
              onChanged: (_) => host._scheduleAutoSave(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec(context, 'Altura (px)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: w,
              style: host._fieldTextStyle(context),
              onChanged: (_) => host._scheduleAutoSave(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec(context, 'Largura (px)'),
            ),
          ),
        ],
      );
      if (!isNarrow) return row;
      return Column(
        children: [
          TextField(
            controller: h,
            style: host._fieldTextStyle(context),
            onChanged: (_) => host._scheduleAutoSave(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec(context, 'Altura (px)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: w,
            style: host._fieldTextStyle(context),
            onChanged: (_) => host._scheduleAutoSave(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec(context, 'Largura (px)'),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = host._mediaTab == _MediaTab.desktop;

    final logoUrl = isDesktop ? host._logoUrlDesktop : host._logoUrlMobile;
    final banners = isDesktop ? host._bannersDesktop : host._bannersMobile;

    return Column(
      children: [
        _Section(
          title: 'Plataforma',
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Desktop'),
                selected: isDesktop,
                onSelected: (_) => host._setMediaTab(_MediaTab.desktop),
              ),
              ChoiceChip(
                label: const Text('Android / Mobile'),
                selected: !isDesktop,
                onSelected: (_) => host._setMediaTab(_MediaTab.mobile),
              ),
              const SizedBox(width: 8),
              Text(
                isDesktop
                    ? 'Banner recomendado: 1280×256  |  Logo: 105×327 (A×L)'
                    : 'Banner recomendado: 562×300  |  Logo: 105×327 (A×L)',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: host._midiasLogoSectionKey,
          child: _Section(
            title: 'Logo',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: host._salvando
                      ? null
                      : () => host._trocarLogo(desktop: isDesktop),
                  icon: const Icon(Icons.photo),
                  label: const Text('Enviar logo'),
                ),
                OutlinedButton.icon(
                  onPressed: host._salvando ||
                          (logoUrl == null || logoUrl.isEmpty)
                      ? null
                      : () => host._removerLogo(desktop: isDesktop),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover'),
                ),
              ],
            ),
            child: LayoutBuilder(builder: (context, c) {
              final isNarrow = c.maxWidth < 640;
              final preview = Container(
                height: 64,
                alignment: Alignment.centerLeft,
                child: (logoUrl == null || logoUrl.isEmpty)
                    ? const Text('Nenhuma logo enviada ainda')
                    : Image(
                        image: mpImageProvider(logoUrl),
                        height: 64,
                        fit: BoxFit.contain,
                      ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    preview,
                    const SizedBox(height: 12),
                    _dimRow(
                      h: isDesktop ? host._dLogoH : host._mLogoH,
                      w: isDesktop ? host._dLogoW : host._mLogoW,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: preview),
                  const SizedBox(width: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _dimRow(
                        h: isDesktop ? host._dLogoH : host._mLogoH,
                        w: isDesktop ? host._dLogoW : host._mLogoW,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Banners',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 260,
                child: _dimRow(
                  h: isDesktop ? host._dBanH : host._mBanH,
                  w: isDesktop ? host._dBanW : host._mBanW,
                ),
              ),
              ElevatedButton.icon(
                onPressed: host._salvando
                    ? null
                    : () => host._adicionarBanners(desktop: isDesktop),
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          child: banners.isEmpty
              ? const Text(
                  'Nenhum banner adicionado ainda. Envie pelo menos 1 para deixar seu catálogo mais profissional.',
                  style: TextStyle(color: Colors.black54),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: banners.map((url) {
                      return SizedBox(
                        height: 100,
                        width: 180,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image(
                                image: mpImageProvider(url),
                                height: 100,
                                width: 180,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: InkWell(
                                onTap: host._salvando
                                    ? null
                                    : () => host._removerBanner(
                                          desktop: isDesktop,
                                          url: url,
                                        ),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }
}
