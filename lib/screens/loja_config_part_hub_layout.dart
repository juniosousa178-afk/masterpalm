// Hub da Loja Config: shell, busca, filtros e cards de módulo (part da mesma library).
// Etapa 4 blast-radius: UI + callbacks via [host], sem alterar regra de negócio.

part of 'loja_config_screen.dart';

Color _hubSignalBorderColor(_HubModuleSignal s, ColorScheme cs, Color successColor) {
  switch (s) {
    case _HubModuleSignal.error:
      return cs.error.withOpacity(0.32);
    case _HubModuleSignal.pending:
      return cs.primary.withOpacity(0.28);
    case _HubModuleSignal.ok:
      return successColor.withOpacity(0.26);
    case _HubModuleSignal.neutral:
      return Colors.transparent;
  }
}

Color? _hubSignalDotColor(_HubModuleSignal s, ColorScheme cs, Color successColor) {
  switch (s) {
    case _HubModuleSignal.error:
      return cs.error;
    case _HubModuleSignal.pending:
      return cs.primary;
    case _HubModuleSignal.ok:
      return successColor;
    case _HubModuleSignal.neutral:
      return null;
  }
}

String? _hubSignalStatusCaption(_HubModuleSignal s) {
  switch (s) {
    case _HubModuleSignal.error:
      return 'Revisar configuração';
    case _HubModuleSignal.pending:
      return 'Alterações pendentes';
    case _HubModuleSignal.ok:
      return 'Sem pendências';
    case _HubModuleSignal.neutral:
      return null;
  }
}

/// Card “Módulos de configuração” (cabeçalho + busca + filtro + corpo).
class _LojaConfigHubShell extends StatelessWidget {
  const _LojaConfigHubShell({
    required this.isWide,
    required this.cs,
    required this.tt,
    required this.searchField,
    required this.filterStrip,
    required this.moduleSections,
  });

  final bool isWide;
  final ColorScheme cs;
  final TextTheme tt;
  final Widget searchField;
  final Widget filterStrip;
  final List<Widget> moduleSections;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _LojaConfigScreenState._primaryColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _LojaConfigScreenState._primaryColor.withOpacity(0.14)),
                  ),
                  child: const Icon(Icons.dashboard_customize_outlined,
                      color: _LojaConfigScreenState._primaryColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Módulos de configuração',
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isWide
                            ? 'Abra cada área em tela própria para editar com foco. Salvar, sincronizar, publicar e pré-visualizar continuam no topo.'
                            : 'Toque em um card para abrir o módulo. Use voltar para retornar ao painel.',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant.withOpacity(0.92),
                          height: 1.45,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 28, thickness: 1, color: cs.outlineVariant.withOpacity(0.35)),
            searchField,
            const SizedBox(height: 14),
            filterStrip,
            const SizedBox(height: 14),
            ...moduleSections,
          ],
        ),
      ),
    );
  }
}

class _HubFretesShortcutCard extends StatelessWidget {
  const _HubFretesShortcutCard({
    required this.host,
    required this.cs,
    required this.signal,
    this.tooltip,
  });

  final _LojaConfigScreenState host;
  final ColorScheme cs;
  final _HubModuleSignal signal;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final caption = _hubSignalStatusCaption(signal);
    final dotColor = _hubSignalDotColor(signal, cs, _LojaConfigScreenState._successColor);
    final borderColor = switch (signal) {
      _HubModuleSignal.neutral => _LojaConfigScreenState._warningColor.withOpacity(0.35),
      _ => _hubSignalBorderColor(signal, cs, _LojaConfigScreenState._successColor),
    };

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _LojaConfigScreenState._warningColor.withOpacity(0.12),
            ),
            child: const Icon(Icons.local_shipping_outlined,
                color: _LojaConfigScreenState._warningColor, size: 22),
          ),
          if (dotColor != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        'Fretes & Cupons',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: cs.onSurface,
          letterSpacing: -0.1,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (caption != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  caption,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: switch (signal) {
                      _HubModuleSignal.error => cs.error.withOpacity(0.95),
                      _HubModuleSignal.pending => cs.primary.withOpacity(0.95),
                      _HubModuleSignal.ok =>
                        _LojaConfigScreenState._successColor.withOpacity(0.92),
                      _HubModuleSignal.neutral => cs.onSurfaceVariant,
                    },
                  ),
                ),
              ),
            Text(
              'Fretes e cupons em tela dedicada',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: cs.onSurfaceVariant.withOpacity(0.92),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 22, color: cs.onSurfaceVariant.withOpacity(0.7)),
      onTap: () => unawaited(host._openFretesCuponsScreenIfAllowed()),
    );

    final t = tooltip ?? 'Abrir fretes e cupons em tela dedicada';
    return Tooltip(
      message: t,
      waitDuration: const Duration(milliseconds: 400),
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: tile,
      ),
    );
  }
}

class _HubSearchFieldWidget extends StatelessWidget {
  const _HubSearchFieldWidget({
    required this.host,
    required this.cs,
    required this.tt,
  });

  final _LojaConfigScreenState host;
  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final hasText = host._hubSearchCtrl.text.trim().isNotEmpty;
    return TextField(
      controller: host._hubSearchCtrl,
      onChanged: (_) => host._onHubSearchChanged(),
      textInputAction: TextInputAction.search,
      style: tt.bodyMedium?.copyWith(
        color: cs.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: cs.surface,
        hintText: 'Buscar módulo ou configuração',
        hintStyle: tt.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant.withOpacity(0.65),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 22,
          color: cs.onSurfaceVariant.withOpacity(0.75),
        ),
        suffixIcon: hasText
            ? IconButton(
                tooltip: 'Limpar busca',
                icon: Icon(Icons.close_rounded, size: 20, color: cs.onSurfaceVariant),
                onPressed: host._clearHubSearch,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: _LojaConfigScreenState._primaryColor.withOpacity(0.65), width: 1.5),
        ),
      ),
    );
  }
}

class _HubFilterStripWidget extends StatelessWidget {
  const _HubFilterStripWidget({
    required this.host,
    required this.cs,
    required this.tt,
    required this.countAll,
    required this.countError,
    required this.countPending,
    required this.countOk,
    required this.countNeutral,
    required this.showFirstErrorShortcut,
  });

  final _LojaConfigScreenState host;
  final ColorScheme cs;
  final TextTheme tt;
  final int countAll;
  final int countError;
  final int countPending;
  final int countOk;
  final int countNeutral;
  final bool showFirstErrorShortcut;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _HubModuleFilter value) {
      final sel = host._hubModuleFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: ChoiceChip(
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
          selected: sel,
          onSelected: (_) => host._setHubModuleFilterIfChanged(value),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          selectedColor: _LojaConfigScreenState._primaryColor.withOpacity(0.16),
          backgroundColor: cs.surface.withOpacity(0.65),
          labelStyle: TextStyle(
            color: sel ? _LojaConfigScreenState._primaryColor : cs.onSurface.withOpacity(0.82),
          ),
          side: BorderSide(
            color: sel
                ? _LojaConfigScreenState._primaryColor.withOpacity(0.42)
                : cs.outlineVariant.withOpacity(0.55),
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          showCheckmark: false,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Filtrar',
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withOpacity(0.88),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (showFirstErrorShortcut)
              Tooltip(
                message:
                    'Abre o primeiro módulo com erro na ordem do hub (independente do filtro e da busca atual).',
                waitDuration: const Duration(milliseconds: 450),
                child: TextButton.icon(
                  onPressed: host._openFirstHubErrorTarget,
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error.withOpacity(0.92),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(Icons.arrow_circle_right_outlined, size: 18, color: cs.error.withOpacity(0.92)),
                  label: Text(
                    'Primeiro erro',
                    style: tt.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip('Todos ($countAll)', _HubModuleFilter.all),
              chip('Erros ($countError)', _HubModuleFilter.error),
              chip('Pendentes ($countPending)', _HubModuleFilter.pending),
              chip('OK ($countOk)', _HubModuleFilter.ok),
              chip('Neutros ($countNeutral)', _HubModuleFilter.neutral),
            ],
          ),
        ),
      ],
    );
  }
}

class _HubModuleCardWidget extends StatelessWidget {
  const _HubModuleCardWidget({
    required this.host,
    required this.item,
    required this.cs,
    required this.dirty,
    required this.hubSalvar,
    required this.hubPubAvisos,
  });

  final _LojaConfigScreenState host;
  final Map<String, dynamic> item;
  final ColorScheme cs;
  final bool dirty;
  final List<({String campo, String msg})> hubSalvar;
  final List<String> hubPubAvisos;

  @override
  Widget build(BuildContext context) {
    final icon = item['icon'] as IconData;
    final label = item['label'] as String;
    final subtitle = item['subtitle'] as String;
    final pane = item['pane'] as _Pane;

    final hub = host._hubCardStateForPane(pane, dirty, hubSalvar, hubPubAvisos);
    final signal = hub.signal;
    final caption = _hubSignalStatusCaption(signal);
    final dotColor = _hubSignalDotColor(signal, cs, _LojaConfigScreenState._successColor);
    final borderColor = _hubSignalBorderColor(signal, cs, _LojaConfigScreenState._successColor);

    final body = Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => host._openConfigModule(pane),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _LojaConfigScreenState._primaryColor.withOpacity(0.1),
                      border: Border.all(color: _LojaConfigScreenState._primaryColor.withOpacity(0.2)),
                    ),
                    child: Icon(icon, color: _LojaConfigScreenState._primaryColor, size: 24),
                  ),
                  if (dotColor != null)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surfaceContainerLow, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: -0.1,
                        color: cs.onSurface,
                        height: 1.2,
                      ),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: switch (signal) {
                            _HubModuleSignal.error => cs.error.withOpacity(0.92),
                            _HubModuleSignal.pending => cs.primary.withOpacity(0.92),
                            _HubModuleSignal.ok =>
                              _LojaConfigScreenState._successColor.withOpacity(0.9),
                            _HubModuleSignal.neutral => cs.onSurfaceVariant.withOpacity(0.88),
                          },
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: cs.onSurfaceVariant.withOpacity(0.88),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: cs.onSurfaceVariant.withOpacity(0.65)),
            ],
          ),
        ),
      ),
    );

    final tip = hub.tooltip;
    if (tip == null || tip.isEmpty) return body;

    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 400),
      child: body,
    );
  }
}
