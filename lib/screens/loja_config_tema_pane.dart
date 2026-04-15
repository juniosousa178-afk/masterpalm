part of 'loja_config_screen.dart';

class _PaneTemaWidget extends StatefulWidget {
  const _PaneTemaWidget({super.key, required this.host});
  final _LojaConfigScreenState host;

  @override
  State<_PaneTemaWidget> createState() => _PaneTemaWidgetState();
}

class _PaneTemaWidgetState extends State<_PaneTemaWidget> {
  String? _accordionOpenId = 'tema_fundo';

  /// Grupo colapsável no painel Temas e Cores — [child] só entra na árvore quando aberto.
  Widget _buildTemaAccordionSection({
    required String id,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final open = _accordionOpenId == id;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (open) {
                  _accordionOpenId = null;
                } else {
                  _accordionOpenId = id;
                }
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: cs.onSurface,
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withOpacity(0.92),
                              height: 1.4,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: RepaintBoundary(child: child),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paletteSuggestions = widget.host._catalogColorPaletteSuggestions();
    final miniPreviewColors = widget.host._catalogMiniPreviewColors();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            _Section(
              title: 'Prévia visual',
              subtitle:
                  'Miniatura estática com as cores do rascunho (não carrega produtos nem o catálogo real). Atualiza ao mudar cores, presets ou editor.',
              child: LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 440;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 420),
                      child: CatalogStoreMiniPreview(
                        colors: miniPreviewColors,
                        storeName: widget.host._miniPreviewStoreName(),
                        density: narrow
                            ? CatalogStoreMiniPreviewDensity.compact
                            : CatalogStoreMiniPreviewDensity.comfortable,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Presets de Layout (Master)',
              child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: 'Master Padrão',
                description: 'Fundo escuro, azul neon, visual tech',
                selected: widget.host._layoutPreset == _LayoutPreset.masterPadrao,
                onTap: () => widget.host._applyPreset(_LayoutPreset.masterPadrao),
              ),
              _PresetChip(
                label: 'Master Luxo',
                description: 'Dourado, fundo escuro, cara de joalheria',
                selected: widget.host._layoutPreset == _LayoutPreset.masterLuxo,
                onTap: () => widget.host._applyPreset(_LayoutPreset.masterLuxo),
              ),
              _PresetChip(
                label: 'Dark Clean',
                description: 'Minimalista, verde neon, bem limpo',
                selected: widget.host._layoutPreset == _LayoutPreset.darkClean,
                onTap: () => widget.host._applyPreset(_LayoutPreset.darkClean),
              ),
            ],
          ),
        ),
          const SizedBox(height: 12),
          _Section(
            title: 'Paletas prontas',
            subtitle:
                'Cores harmonizadas como ponto de partida. Só aplicam após você confirmar; edite manualmente depois se quiser.',
            child: CatalogVisualPalettePresetsPanel(
              presets: CatalogVisualPalettePresets.all,
              onApplyRequested: widget.host._confirmApplyVisualPalette,
            ),
          ),
          const SizedBox(height: 12),

          // ===== FUNDO E CARDS =====
          _buildTemaAccordionSection(
            id: 'tema_fundo',
            title: 'Fundo e Cards',
            subtitle: 'Cores de fundo da página e dos cards de produto',
            child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              widget.host._catalogColorFieldTema(
                suggestions: paletteSuggestions,
                label: 'Fundo da página',
                description: 'Plano de fundo geral do catálogo público.',
                color: widget.host._cFundo,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFundo = c),
              ),

              widget.host._catalogColorFieldTema(
                suggestions: paletteSuggestions,
                label: 'Fundo dos cards',
                color: widget.host._cCard,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCard = c),
              ),

            ],
          ),
        ),
        const SizedBox(height: 8),

        // ===== PRODUTOS (Nome e Preço) =====
        _buildTemaAccordionSection(
          id: 'tema_produtos',
          title: 'Produtos – Nome e Preço',
          subtitle: 'Cores do nome do produto e do valor (ex: R\$ 109,90)',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Nome do produto',
                color: widget.host._cCardTextPrimary,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCardTextPrimary = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Preço (valor)',
                color: widget.host._cPriceHighlight,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cPriceHighlight = c),
              ),

            ],
          ),
        ),
        const SizedBox(height: 8),

        // ===== BOTÕES =====
        _buildTemaAccordionSection(
          id: 'tema_botoes',
          title: 'Botões',
          subtitle: 'Cores dos botões Comprar, Ver e filtros de categoria',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Botão Comprar – fundo',
                description: 'Cor principal de ação (comprar, aplicar cupom, etc.).',
                color: widget.host._cPrimaria,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cPrimaria = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Botão Comprar – texto',
                color: widget.host._cBotaoTexto,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cBotaoTexto = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Botão Ver – fundo',
                color: widget.host._cButtonSecondaryBg,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cButtonSecondaryBg = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Botão Ver – texto e borda',
                color: widget.host._cButtonSecondaryText,
                onChanged: (c) => widget.host._applyTemaColor(() {
                    widget.host._cButtonSecondaryText = c;
                    widget.host._cButtonSecondaryBorder = c;
                  }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ===== TEXTOS GERAIS =====
        _buildTemaAccordionSection(
          id: 'tema_textos',
          title: 'Textos Gerais',
          subtitle: 'Textos da página, secundários, ícones e divisórias',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Texto principal',
                color: widget.host._cTexto,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cTexto = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Texto secundário',
                color: widget.host._cTextSecondary,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cTextSecondary = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Texto card secundário',
                color: widget.host._cCardTextSecondary,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCardTextSecondary = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Ícones',
                color: widget.host._cIcon,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cIcon = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Divisórias',
                color: widget.host._cDivider,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDivider = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Sombras',
                color: widget.host._cShadow,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cShadow = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Cor de perigo',
                color: widget.host._cDanger,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDanger = c),
              ),

            ],
          ),
        ),
        const SizedBox(height: 8),

        // ===== BADGES =====
        _buildTemaAccordionSection(
          id: 'tema_badges',
          title: 'Badges e Chips',
          subtitle: 'Selos, etiquetas e chips informativos',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Badge – fundo',
                color: widget.host._cBadgeBackground,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cBadgeBackground = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Badge – texto',
                color: widget.host._cBadgeText,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cBadgeText = c),
              ),

            ],
          ),
        ),
        const SizedBox(height: 8),

        // ===== CABEÇALHO DO CATÁLOGO =====
        _buildTemaAccordionSection(
          id: 'tema_cabecalho',
          title: 'Cabeçalho do Catálogo',
          subtitle: 'Menu, logo, busca e ícones do topo',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Fundo Cabeçalho',
                    color: widget.host._cCabecalho,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCabecalho = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Texto Cabeçalho',
                    color: widget.host._cHeaderText,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cHeaderText = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Ícones Cabeçalho',
                    color: widget.host._cHeaderIcon,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cHeaderIcon = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Busca Fundo',
                    color: widget.host._cHeaderSearchBg,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cHeaderSearchBg = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Busca Texto',
                    color: widget.host._cHeaderSearchText,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cHeaderSearchText = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Busca Hint',
                    color: widget.host._cHeaderSearchHint,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cHeaderSearchHint = c),
                  ),

                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Pré-visualização do cartão',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: widget.host._cFundo,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.host._cCard,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: widget.host._cPrimaria.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Exemplo de joia',
                                    style: TextStyle(
                                      color: widget.host._cTexto,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Descrição breve do produto...',
                                    style: TextStyle(
                                      color: widget.host._cTexto.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'R\$ 129,90',
                                          style: TextStyle(
                                            color: widget.host._cPriceHighlight,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: widget.host._cPrimaria,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                'Ver detalhes',
                                                style: TextStyle(
                                                  color: widget.host._cBotaoTexto,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ===== CORES DO CARRINHO (CHECKOUT) =====
        _buildTemaAccordionSection(
          id: 'tema_carrinho',
          title: 'Cores do Carrinho (checkout)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Fundo do card',
                    color: widget.host._cCarrinhoCard,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCarrinhoCard = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Campos (dropdown / input)',
                    color: widget.host._cCarrinhoCampo,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCarrinhoCampo = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Texto dos campos',
                    color: widget.host._cCarrinhoTexto,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCarrinhoTexto = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Rótulos (Entrega, Pagamento...)',
                    color: widget.host._cCarrinhoLabel,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCarrinhoLabel = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Total a pagar',
                    color: widget.host._cCarrinhoTotal,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cCarrinhoTotal = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Campo Hint',
                    color: widget.host._cFieldHint,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFieldHint = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Campo Borda',
                    color: widget.host._cFieldBorder,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFieldBorder = c),
                  ),

                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Pré-visualização do resumo do pedido',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // PREVIEW DO CARRINHO
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: widget.host._cFundo,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.host._cPrimaria.withOpacity(0.18),
                          ),
                          child: Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                            color: widget.host._cPrimaria,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Resumo do pedido',
                            style: TextStyle(
                              color: widget.host._cCarrinhoLabel,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: widget.host._cCarrinhoTotal,
                              ),
                              child: const Text(
                                'Total R\$ 99,66',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Card interno
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.host._cCarrinhoCard,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Subtotal',
                                  style: TextStyle(
                                    color: widget.host._cCarrinhoTexto
                                        .withOpacity(0.8),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                'R\$ 99,66',
                                style: TextStyle(
                                  color: widget.host._cCarrinhoTexto,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Total a pagar',
                                  style: TextStyle(
                                    color: widget.host._cCarrinhoLabel,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'R\$ 99,66',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: widget.host._cCarrinhoTotal,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Preview das linhas de Entrega / Pagamento / Cupom
                    Text(
                      'Entrega',
                      style: TextStyle(
                        color: widget.host._cCarrinhoLabel,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.host._cCarrinhoCampo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Retirada ? R\$ 0,00',
                        style: TextStyle(
                          color: widget.host._cCarrinhoTexto,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Forma de pagamento',
                      style: TextStyle(
                        color: widget.host._cCarrinhoLabel,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.host._cCarrinhoCampo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'PIX',
                        style: TextStyle(
                          color: widget.host._cCarrinhoTexto,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cupom de desconto',
                      style: TextStyle(
                        color: widget.host._cCarrinhoLabel,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: widget.host._cCarrinhoCampo,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Digite o cupom',
                              style: TextStyle(
                                color: widget.host._cCarrinhoTexto.withOpacity(0.7),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Container(
                              height: 42,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: widget.host._cPrimaria,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Aplicar',
                                style: TextStyle(
                                  color: widget.host._cBotaoTexto,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ===== CORES DO RODAPÉ DO CATÁLOGO =====
        _buildTemaAccordionSection(
          id: 'tema_rodape',
          title: 'Cores do Rodapé',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personalize as cores da área de rodapé do catálogo',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Fundo Rodapé',
                    color: widget.host._cFooterBackground,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFooterBackground = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Texto Rodapé',
                    color: widget.host._cFooterText,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFooterText = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Texto Secundário',
                    color: widget.host._cFooterTextSecondary,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFooterTextSecondary = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Ícones Rodapé',
                    color: widget.host._cFooterIcon,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFooterIcon = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Links Rodapé',
                    color: widget.host._cFooterLink,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFooterLink = c),
                  ),

                  widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                    label: 'Divisórias Rodapé',
                    color: widget.host._cFooterDivider,
                    onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cFooterDivider = c),
                  ),

                ],
              ),
              const SizedBox(height: 16),

              // Preview do rodapé
              Text(
                'Pré-visualização do rodapé',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.host._cFooterBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sobre a Loja',
                      style: TextStyle(
                        color: widget.host._cFooterText,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Texto de exemplo do rodapé...',
                      style: TextStyle(
                        color: widget.host._cFooterTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Divider(color: widget.host._cFooterDivider, height: 1),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.email_outlined, color: widget.host._cFooterIcon, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'contato@exemplo.com',
                            style: TextStyle(color: widget.host._cFooterLink, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ===== CORES DA TELA DICAS E INFORMAÇÕES =====
        _buildTemaAccordionSection(
          id: 'tema_dicas',
          title: 'Cores da tela Dicas e Informações',
          subtitle: 'Fundo, rodapé, botões e etiqueta por tópico (Garantias, Cuidados, etc.)',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Fundo',
                color: widget.host._cDicasBackground,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDicasBackground = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Rodapé – fundo',
                color: widget.host._cDicasFooterBg,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDicasFooterBg = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Rodapé – texto',
                color: widget.host._cDicasFooterText,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDicasFooterText = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Botões',
                color: widget.host._cDicasButtonBg,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDicasButtonBg = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Texto dos botões',
                color: widget.host._cDicasButtonText,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDicasButtonText = c),
              ),

              widget.host._catalogColorFieldTema(suggestions: paletteSuggestions,
                label: 'Por tópico (Garantias, Cuidados...)',
                color: widget.host._cDicasTopicPrimary,
                onChanged: (c) => widget.host._applyTemaColor(() => widget.host._cDicasTopicPrimary = c),
              ),

            ],
          ),
        ),
      ],
    );
  }
}
