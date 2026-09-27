import 'package:flutter/material.dart';

import '../../design_system/mp_tokens.dart';
import '../../screens/financeiro/financeiro_lancamentos_screen.dart';
import '../../screens/financeiro/gastos_fixos_screen.dart';
import 'financial_launch_catalog.dart';

const String financialNewLaunchLabel = '+ Novo lançamento';
const String financialLaunchChooserTitle = 'O que você deseja registrar?';

/// Abre a tela que já existe. Não grava dados.
void openFinancialHubDestination(
  BuildContext context,
  FinancialHubDestination destination, {
  required String? storeId,
}) {
  assert(!destination.persists);
  assert(FinancialLaunchCatalog.ledgerWrites == 0);
  final id = (storeId ?? '').trim();
  switch (destination.navigation) {
    case FinancialHubNavigation.namedRoute:
      final route = destination.route;
      if (route == null || route.isEmpty) return;
      Navigator.of(context).pushNamed<void>(route);
    case FinancialHubNavigation.existingLancamento:
      if (id.isEmpty) {
        _missingStore(context);
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FinanceiroLancamentosScreen(
            lojaId: id,
            tipoNovo: destination.tipoLancamento,
            categoriaNova: destination.categoria,
            abrirFormularioNovo: destination.openNewForm,
            mostrarFiltros: destination.showFilters,
          ),
        ),
      );
    case FinancialHubNavigation.existingFixedExpenses:
      if (id.isEmpty) {
        _missingStore(context);
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GastosFixosScreen(lojaId: id),
        ),
      );
  }
}

void _missingStore(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Não foi possível identificar a loja.')),
  );
}

Future<void> showFinancialLaunchChooser(
  BuildContext context, {
  required String? storeId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MpColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(MpRadius.lg)),
    ),
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.86;
      return SafeArea(
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  MpSpacing.lg,
                  MpSpacing.lg,
                  MpSpacing.lg,
                  MpSpacing.sm,
                ),
                child: Text(
                  financialLaunchChooserTitle,
                  style: MpType.title,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: MpSpacing.lg),
                child: Text(
                  'Escolha o registro que já existe. Nada é gravado nesta lista.',
                  style: MpType.caption,
                ),
              ),
              const SizedBox(height: MpSpacing.sm),
              Expanded(
                child: ListView(
                  children: [
                    for (final destination in FinancialLaunchCatalog.options) ...[
                      ListTile(
                        key: Key('financial-launch-${destination.id}'),
                        title: Text(destination.label, style: MpType.body),
                        subtitle:
                            Text(destination.helper, style: MpType.caption),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          openFinancialHubDestination(
                            context,
                            destination,
                            storeId: storeId,
                          );
                        },
                      ),
                      const Divider(height: 1, color: MpColors.border),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Camada de navegação sobre a visão só leitura. Some quando [enabled] é falso.
class FinancialV2OperationalHub extends StatelessWidget {
  const FinancialV2OperationalHub({
    super.key,
    required this.enabled,
    required this.storeId,
    required this.overview,
  });

  final bool enabled;
  final String? storeId;
  final Widget overview;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return overview;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MpSpacing.lg,
            MpSpacing.lg,
            MpSpacing.lg,
            MpSpacing.sm,
          ),
          child: wide ? _desktopBar(context) : _mobileBar(context),
        ),
        Expanded(child: overview),
      ],
    );
  }

  Widget _desktopBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _newLaunchButton(context),
        const SizedBox(height: MpSpacing.md),
        Wrap(
          spacing: MpSpacing.sm,
          runSpacing: MpSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Chip(
              label: Text('Visão geral'),
              visualDensity: VisualDensity.compact,
            ),
            for (final shortcut in FinancialLaunchCatalog.shortcuts)
              _shortcut(context, shortcut),
          ],
        ),
      ],
    );
  }

  Widget _mobileBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _newLaunchButton(context),
        const SizedBox(height: MpSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Chip(
                label: Text('Visão geral'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: MpSpacing.sm),
              for (final shortcut in FinancialLaunchCatalog.shortcuts) ...[
                _shortcut(context, shortcut),
                const SizedBox(width: MpSpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _newLaunchButton(BuildContext context) {
    return FilledButton(
      key: const Key('financial-v2-new-launch'),
      style: FilledButton.styleFrom(
        backgroundColor: MpColors.financeiro,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: MpSpacing.lg,
          vertical: MpSpacing.md,
        ),
      ),
      onPressed: () => showFinancialLaunchChooser(context, storeId: storeId),
      child: const Text(financialNewLaunchLabel),
    );
  }

  Widget _shortcut(BuildContext context, FinancialHubDestination shortcut) {
    return ActionChip(
      key: Key('financial-hub-${shortcut.id}'),
      label: Text(shortcut.label),
      visualDensity: VisualDensity.compact,
      onPressed: () => openFinancialHubDestination(
        context,
        shortcut,
        storeId: storeId,
      ),
    );
  }
}
