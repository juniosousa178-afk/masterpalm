// Painel Layout & cards: acordeões minimalista, hero, categorias, grid (part da mesma library).

part of 'loja_config_screen.dart';

class _PaneLayoutWidget extends StatelessWidget {
  const _PaneLayoutWidget({required this.host});

  final _LojaConfigScreenState host;

  @override
  Widget build(BuildContext context) {
    final paletteSuggestions = host._catalogColorPaletteSuggestions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LayoutAccordionSection(
          host: host,
          id: 'layout_geral',
          title: 'Layout geral',
          subtitle:
              'Minimalista Premium é o visual recomendado. Clássico compatível preserva o grid/cards de lojas antigas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: host._layoutCatalogo,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'minimalista_nuvemshop',
                    child: Text('Minimalista Premium (recomendado)'),
                  ),
                  DropdownMenuItem(
                    value: 'padrao',
                    child: Text('Clássico compatível'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  host._layoutSetStateAndSave(() => host._layoutCatalogo = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Opção de layout',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: host._productCardSize,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'small',
                    child: Text('Pequena (layout mais compacto)'),
                  ),
                  DropdownMenuItem(
                    value: 'medium',
                    child: Text('Média (equilíbrio)'),
                  ),
                  DropdownMenuItem(
                    value: 'large',
                    child: Text('Grande (foto em destaque)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  host._layoutSetStateAndSave(() => host._productCardSize = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Tamanho do card/foto do produto',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        _LayoutAccordionSection(
          host: host,
          id: 'layout_promo',
          title: 'Barra promocional superior',
          subtitle:
              'Letreiro no layout minimalista — texto, link, cores e rolagem.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: host._promoBarEnabled,
                onChanged: (v) {
                  host._layoutSetStateAndSave(() => host._promoBarEnabled = v);
                },
                title: const Text('Ativar barra promocional'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._promoBarTextCtrl,
                decoration: const InputDecoration(
                  labelText: 'Texto da barra promocional',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: host._promoBarLinkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link opcional da barra',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 12),
              _lojaConfigLayoutResponsivePair(
                breakpoint: 560,
                first: host._catalogColorFieldTema(
                  suggestions: paletteSuggestions,
                  label: 'Cor fundo da barra',
                  description: 'Fundo do letreiro promocional.',
                  color: host._promoBarBg,
                  onChanged: (c) =>
                      host._layoutSetStateOnly(() => host._promoBarBg = c),
                ),
                second: host._catalogColorFieldTema(
                  suggestions: paletteSuggestions,
                  label: 'Cor do texto da barra',
                  description: 'Cor das letras do letreiro.',
                  color: host._promoBarText,
                  onChanged: (c) =>
                      host._layoutSetStateOnly(() => host._promoBarText = c),
                ),
              ),
              SwitchListTile(
                value: host._promoBarMarquee,
                onChanged: (v) {
                  host._layoutSetStateAndSave(() => host._promoBarMarquee = v);
                },
                title: const Text('Rolar texto longo no letreiro (minimalista)'),
                subtitle: const Text(
                  'Quando a frase não couber, ela passa automaticamente na horizontal.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: host._minimalSearchPlaceholderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Placeholder da busca (layout minimalista)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
            ],
          ),
        ),
        _LayoutAccordionSection(
          host: host,
          id: 'layout_hero',
          title: 'Banner / letreiro (minimalista)',
          subtitle:
              'Card abaixo das categorias — imagens, textos, botão e aparência.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: host._heroBannerEnabled,
                onChanged: (v) {
                  host._layoutSetStateAndSave(() => host._heroBannerEnabled = v);
                },
                title: const Text('Ativar banner promocional'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Text(
                'Tamanho ideal do banner: Desktop 1280×256  |  Mobile 562×300',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._heroBannerTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titulo do banner',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._heroBannerSubtitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Subtitulo do banner',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 8),
              _ImageFieldWithGallery(
                label: 'Imagem banner (desktop)',
                controller: host._heroBannerImageCtrl,
                onChanged: host._scheduleAutoSave,
                onPickImage: () => host._pickAndUploadLayoutImage('hero_desktop'),
              ),
              const SizedBox(height: 8),
              _ImageFieldWithGallery(
                label: 'Imagem banner (mobile)',
                controller: host._heroBannerMobileImageCtrl,
                onChanged: host._scheduleAutoSave,
                onPickImage: () => host._pickAndUploadLayoutImage('hero_mobile'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._heroBannerButtonTextCtrl,
                decoration: const InputDecoration(
                  labelText: 'Texto do botao do banner',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._heroBannerButtonLinkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Link do botao do banner',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text(
                  'Aparência do banner (layout minimalista)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Cores do card, tipografia do título/subtítulo e do botão — independentes do tema geral.',
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Card do banner',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  host._catalogColorFieldTema(
                    suggestions: paletteSuggestions,
                    label: 'Fundo do card',
                    color: host._heroCardBg,
                    onChanged: (c) => host._layoutSetStateOnly(() => host._heroCardBg = c),
                  ),
                  const SizedBox(height: 8),
                  _lojaConfigLayoutResponsivePair(
                    breakpoint: 480,
                    first: TextField(
                      controller: host._heroBannerHeightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Altura do banner (px)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => host._scheduleAutoSave(),
                    ),
                    second: TextField(
                      controller: host._heroBannerCardRadiusCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Raio dos cantos do card',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => host._scheduleAutoSave(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._heroBannerOverlayCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Escurecimento sobre a imagem (0–0,8)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => host._scheduleAutoSave(),
                  ),
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Título',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  host._catalogColorFieldTema(
                    suggestions: paletteSuggestions,
                    label: 'Cor do título',
                    color: host._heroTitleColor,
                    onChanged: (c) => host._layoutSetStateOnly(() => host._heroTitleColor = c),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._heroBannerTitleSizeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tamanho da fonte (título)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => host._scheduleAutoSave(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: host._heroTitleFontWeight,
                    decoration: const InputDecoration(
                      labelText: 'Peso da fonte (título)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 400, child: Text('400 (Regular)')),
                      DropdownMenuItem(value: 500, child: Text('500 (Medium)')),
                      DropdownMenuItem(value: 600, child: Text('600 (Semibold)')),
                      DropdownMenuItem(value: 700, child: Text('700 (Bold)')),
                      DropdownMenuItem(value: 800, child: Text('800 (Extra bold)')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      host._layoutSetStateAndSave(() => host._heroTitleFontWeight = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: host._heroTitleCase,
                    decoration: const InputDecoration(
                      labelText: 'Caixa do texto (título)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Normal')),
                      DropdownMenuItem(
                          value: 'lowercase', child: Text('minúsculas')),
                      DropdownMenuItem(
                          value: 'uppercase', child: Text('MAIÚSCULAS')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      host._layoutSetStateAndSave(() => host._heroTitleCase = v);
                    },
                  ),
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Subtítulo',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  host._catalogColorFieldTema(
                    suggestions: paletteSuggestions,
                    label: 'Cor do subtítulo',
                    color: host._heroSubtitleColor,
                    onChanged: (c) =>
                        host._layoutSetStateOnly(() => host._heroSubtitleColor = c),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._heroBannerSubtitleSizeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tamanho da fonte (subtítulo)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => host._scheduleAutoSave(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: host._heroSubtitleFontWeight,
                    decoration: const InputDecoration(
                      labelText: 'Peso da fonte (subtítulo)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 400, child: Text('400 (Regular)')),
                      DropdownMenuItem(value: 500, child: Text('500 (Medium)')),
                      DropdownMenuItem(value: 600, child: Text('600 (Semibold)')),
                      DropdownMenuItem(value: 700, child: Text('700 (Bold)')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      host._layoutSetStateAndSave(() => host._heroSubtitleFontWeight = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: host._heroSubtitleCase,
                    decoration: const InputDecoration(
                      labelText: 'Caixa do texto (subtítulo)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Normal')),
                      DropdownMenuItem(
                          value: 'lowercase', child: Text('minúsculas')),
                      DropdownMenuItem(
                          value: 'uppercase', child: Text('MAIÚSCULAS')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      host._layoutSetStateAndSave(() => host._heroSubtitleCase = v);
                    },
                  ),
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Botão / destaque',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _lojaConfigLayoutResponsivePair(
                    breakpoint: 560,
                    first: host._catalogColorFieldTema(
                      suggestions: paletteSuggestions,
                      label: 'Fundo do botão',
                      color: host._heroButtonBg,
                      onChanged: (c) => host._layoutSetStateOnly(() => host._heroButtonBg = c),
                    ),
                    second: host._catalogColorFieldTema(
                      suggestions: paletteSuggestions,
                      label: 'Texto do botão',
                      color: host._heroButtonTextColor,
                      onChanged: (c) =>
                          host._layoutSetStateOnly(() => host._heroButtonTextColor = c),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _lojaConfigLayoutResponsivePair(
                    breakpoint: 480,
                    first: TextField(
                      controller: host._heroBannerButtonSizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tamanho da fonte (botão)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => host._scheduleAutoSave(),
                    ),
                    second: TextField(
                      controller: host._heroBannerButtonRadiusCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Raio dos cantos do botão',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => host._scheduleAutoSave(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: host._heroButtonFontWeight,
                    decoration: const InputDecoration(
                      labelText: 'Peso da fonte (botão)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 400, child: Text('400 (Regular)')),
                      DropdownMenuItem(value: 500, child: Text('500 (Medium)')),
                      DropdownMenuItem(value: 600, child: Text('600 (Semibold)')),
                      DropdownMenuItem(value: 700, child: Text('700 (Bold)')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      host._layoutSetStateAndSave(() => host._heroButtonFontWeight = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: host._heroButtonCase,
                    decoration: const InputDecoration(
                      labelText: 'Caixa do texto (botão)',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Normal')),
                      DropdownMenuItem(
                          value: 'lowercase', child: Text('minúsculas')),
                      DropdownMenuItem(
                          value: 'uppercase', child: Text('MAIÚSCULAS')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      host._layoutSetStateAndSave(() => host._heroButtonCase = v);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ],
          ),
        ),
        _LayoutAccordionSection(
          host: host,
          id: 'layout_categorias',
          title: 'Imagens por categoria',
          subtitle:
              'Uma foto por categoria no minimalista; compatível com configs antigas.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: (host._catSelectedFromStore != null &&
                        host._knownCategoryNames.contains(host._catSelectedFromStore))
                    ? host._catSelectedFromStore
                    : null,
                items: host._knownCategoryNames
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: host._layoutOnCatSelectedFromStoreChanged,
                decoration: const InputDecoration(
                  labelText: 'Selecionar categoria existente (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._catImgCategoriaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome da categoria',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._catImgCategoriaIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID da categoria (opcional, para matching por id)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 8),
              _ImageFieldWithGallery(
                label: 'Imagem da categoria',
                controller: host._catImgUrlCtrl,
                onChanged: host._scheduleAutoSave,
                onPickImage: () => host._pickAndUploadLayoutImage('cat_dynamic'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: host._layoutSaveCategoryImagePressed,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Salvar categoria'),
                ),
              ),
              if (host._categoryImagesByName.isNotEmpty || host._categoryImagesById.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Categorias configuradas',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                ...host._categoryImagesByName.entries
                    .where((e) => !e.key.startsWith('name:'))
                    .map((e) => Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: e.value.trim().isEmpty
                                ? const Icon(Icons.image_not_supported_outlined)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image(
                                      image: mpImageProvider(e.value),
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
                                    ),
                                  ),
                            title: Text(e.key),
                            subtitle: Text(
                              e.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => host._layoutRemoveCategoryImageByNameKey(e.key),
                            ),
                          ),
                        )),
              ],
              if (host._categoryImagesById.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...host._categoryImagesById.entries.map(
                  (e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('ID: ${e.key}'),
                    subtitle: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => host._layoutRemoveCategoryImageById(e.key),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: host._loadKnownCategoryNamesFromStore,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Atualizar categorias da loja'),
                ),
              ),
            ],
          ),
        ),
        _LayoutAccordionSection(
          host: host,
          id: 'layout_mais_vendidos',
          title: 'Seção Mais vendidos',
          subtitle:
              'Carrossel no minimalista — métricas de venda, destaque e novidades.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                value: host._minimalBestSellersEnabled,
                onChanged: (v) {
                  host._layoutSetStateAndSave(() => host._minimalBestSellersEnabled = v);
                },
                title: const Text('Exibir carrossel de mais vendidos'),
                contentPadding: EdgeInsets.zero,
              ),
              TextField(
                controller: host._minimalBestSellersTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Título da seção',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: host._minimalBestSellersCountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantidade de produtos (3 a 24)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => host._scheduleAutoSave(),
              ),
            ],
          ),
        ),
        _LayoutAccordionSection(
          host: host,
          id: 'layout_grid',
          title: 'Grade de produtos (desktop × mobile)',
          subtitle:
              'Quantos cards de produto aparecem por linha em cada tipo de tela.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Desktop (navegador no PC)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: host._gridDesktopCols,
                items: const [2, 3, 4, 5, 6]
                    .map(
                      (v) => DropdownMenuItem<int>(
                        value: v,
                        child: Text('$v cards por linha'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  host._layoutSetStateAndSave(() => host._gridDesktopCols = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Cards por linha (desktop)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Mobile (Android / iOS)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: host._gridMobileCols,
                items: const [1, 2, 3]
                    .map(
                      (v) => DropdownMenuItem<int>(
                        value: v,
                        child: Text('$v cards por linha'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  host._layoutSetStateAndSave(() => host._gridMobileCols = v);
                },
                decoration: const InputDecoration(
                  labelText: 'Cards por linha (mobile)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        _LayoutAccordionSection(
          host: host,
          id: 'layout_cards_style',
          title: 'Estilo visual dos cards',
          subtitle: 'Sombra, cantos arredondados e pré-visualização rápida.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                title: const Text('Aplicar sombra nos cards'),
                subtitle: const Text(
                  'Deixe desativado para um visual mais clean/minimalista.',
                ),
                value: host._cardShowShadow,
                onChanged: (v) {
                  host._layoutSetStateAndSave(() => host._cardShowShadow = v);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Arredondamento das bordas',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Slider(
                min: 4,
                max: 32,
                divisions: 7,
                label: '${host._cardBorderRadius.round()} px',
                value: host._cardBorderRadius,
                onChanged: host._layoutSetCardBorderRadius,
                onChangeEnd: (_) => host._salvarRascunho(validar: false),
              ),
              const SizedBox(height: 4),
              Text(
                'Bordas atuais: ${host._cardBorderRadius.toStringAsFixed(0)} px',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 16),

              Text(
                'Pré-visualização rápida',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: host._cFundo,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Desktop ($host._gridDesktopCols por linha)',
                      style: TextStyle(
                        color: host._cTexto,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    host._buildLayoutPreviewRow(
                      cols: host._gridDesktopCols,
                      borderRadius: host._cardBorderRadius,
                      showShadow: host._cardShowShadow,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Mobile ($host._gridMobileCols por linha)',
                      style: TextStyle(
                        color: host._cTexto,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    host._buildLayoutPreviewRow(
                      cols: host._gridMobileCols,
                      borderRadius: host._cardBorderRadius,
                      showShadow: host._cardShowShadow,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

  }
}
