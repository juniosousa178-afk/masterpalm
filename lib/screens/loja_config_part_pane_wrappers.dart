// Wrappers de vista de módulo, acordeão do painel Layout e pares responsivos.
// Etapa 5 blast-radius: UI estrutural + callbacks via [host].

part of 'loja_config_screen.dart';

/// Vista fullscreen de um módulo (mesmo [State], sem nova rota).
class _ModuleConfigViewShell extends StatelessWidget {
  const _ModuleConfigViewShell({
    required this.host,
    required this.cs,
    required this.isDark,
  });

  final _LojaConfigScreenState host;
  final ColorScheme cs;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final items = host._lojaConfigNavItems();
    final meta =
        items.firstWhere((e) => e['pane'] == host._pane, orElse: () => items.first);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        host._goToHub();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: _LojaConfigScreenState._primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: host._goToHub,
            tooltip: 'Módulos',
          ),
          titleSpacing: 8,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                meta['label'] as String,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Text(
                meta['subtitle'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w400,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: host._buildLojaConfigAppBarActions(cs, isDark),
        ),
        body: Column(
          children: [
            if (host._offline)
              _LojaConfigOfflineConnectivityStripe(
                onVerificar: host._verificarConectividade,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: host._refreshModuleConfigFromPull,
                color: _LojaConfigScreenState._primaryColor,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          host._buildModulePaneErrorBanner(context, cs, host._pane),
                          host._wrapLojaConfigFieldTheme(
                            context,
                            host._buildPaneEditorFor(host._pane),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seção em acordeão no painel Layout (alinhada ao tema dos outros painéis).
class _LayoutAccordionSection extends StatelessWidget {
  const _LayoutAccordionSection({
    required this.host,
    required this.id,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final _LojaConfigScreenState host;
  final String id;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final open = host._layoutPaneAccordionOpenId == id;
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
            onTap: () => host._toggleLayoutAccordion(id),
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
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle!,
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
}

/// Dois blocos lado a lado com largura suficiente; senão empilha (evita overflow no mobile).
Widget _lojaConfigLayoutResponsivePair({
  required double breakpoint,
  required Widget first,
  required Widget second,
  double gap = 12,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < breakpoint;
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            SizedBox(height: gap),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      );
    },
  );
}
