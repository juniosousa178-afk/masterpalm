// M3.8-SPRINT2-R5-HOTFIX-PERMISSIONS — portal ↔ telas (fonte única).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/app_module_definition.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/permissao_service.dart';

HomeModuleAccessContext _ctx({
  required String tipo,
  required Map<String, bool> permissoes,
}) {
  return HomeModuleAccessContext(
    tipoUsuario: tipo,
    permissoes: permissoes,
    planTier: PlanAccessTier.lifetime,
    applyPlanGate: false,
  );
}

Map<String, bool> _allFalse() => {
      for (final k in PermissaoService.todasAsChaves) k: false,
    };

Map<String, bool> _with(Map<String, bool> base, Map<String, bool> overrides) =>
    {...base, ...overrides};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R5 PERM — registry keys alinhadas às telas', () {
    test('PERM-REG-1 historico_compras usa historico_cliente', () {
      final m = HomeModuleRegistry.byId('historico_compras')!;
      expect(m.permissionKey, 'historico_cliente');
      expect(m.route, '/historico_cliente');
    });

    test('PERM-REG-2 clientes usa clientes', () {
      expect(HomeModuleRegistry.byId('clientes')!.permissionKey, 'clientes');
    });

    test('PERM-REG-3 catalogo_interno usa vendas (grade comercial)', () {
      expect(
        HomeModuleRegistry.byId('catalogo_interno')!.permissionKey,
        'vendas',
      );
    });

    test('PERM-REG-4 insights sem permissionKey (só plano)', () {
      final m = HomeModuleRegistry.byId('insights_crm')!;
      expect(m.permissionKey, isNull);
      expect(m.planFeature, PlanGateFeature.insights);
    });

    test('PERM-REG-5 toda permissionKey do registry está em todasAsChaves', () {
      final keys = HomeModuleRegistry.permissionKeysInRegistry();
      for (final k in keys) {
        expect(
          PermissaoService.todasAsChaves,
          contains(k),
          reason: 'chave registry órfã: $k',
        );
      }
    });
  });

  group('R5 PERM — isAllowed nunca mostra sem chave', () {
    test('PERM-VIS-1 vendedor só clientes: vê clientes, não histórico', () {
      final ctx = _ctx(
        tipo: 'vendedor',
        permissoes: _with(_allFalse(), {'clientes': true}),
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('clientes')!,
          ctx,
        ),
        isTrue,
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('historico_compras')!,
          ctx,
        ),
        isFalse,
      );
      final ids = HomeModuleRegistry.visibleForHome(ctx)
          .where((m) => m.category == HomeModuleCategory.clientes)
          .map((m) => m.id)
          .toSet();
      expect(ids, contains('clientes'));
      expect(ids, isNot(contains('historico_compras')));
    });

    test('PERM-VIS-2 vendedor com histórico: vê histórico', () {
      final ctx = _ctx(
        tipo: 'vendedor',
        permissoes: _with(_allFalse(), {
          'clientes': true,
          'historico_cliente': true,
        }),
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('historico_compras')!,
          ctx,
        ),
        isTrue,
      );
    });

    test('PERM-VIS-3 sem permissões: clientes/histórico ocultos', () {
      final ctx = _ctx(tipo: 'vendedor', permissoes: _allFalse());
      expect(
        HomeModuleRegistry.visibleForHome(ctx)
            .where((m) =>
                m.id == 'clientes' || m.id == 'historico_compras')
            .toList(),
        isEmpty,
      );
    });

    test('PERM-VIS-4 admin com mapa true: ambas visíveis', () {
      final ctx = _ctx(
        tipo: 'admin',
        permissoes: {
          for (final k in PermissaoService.todasAsChaves) k: true,
        },
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('historico_compras')!,
          ctx,
        ),
        isTrue,
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('clientes')!,
          ctx,
        ),
        isTrue,
      );
    });

    test('PERM-VIS-5 admin NÃO bypassa mapa parcial (fonte única)', () {
      // Regressão do bug: portal liberava admin sem checar chave.
      final ctx = _ctx(
        tipo: 'admin',
        permissoes: _with(_allFalse(), {'clientes': true}),
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('clientes')!,
          ctx,
        ),
        isTrue,
      );
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('historico_compras')!,
          ctx,
        ),
        isFalse,
      );
    });

    test('PERM-VIS-6 insights aparece sem permissionKey (plan-only)', () {
      final ctx = _ctx(tipo: 'vendedor', permissoes: _allFalse());
      expect(
        HomeModuleRegistry.isAllowed(
          HomeModuleRegistry.byId('insights_crm')!,
          ctx,
        ),
        isTrue,
      );
    });

    test('PERM-VIS-7 mapa completo + isAllowed espelha possuiPermissao admin',
        () {
      // Simula mapaAcessoResolvido para admin (todas true).
      final map = {for (final k in PermissaoService.todasAsChaves) k: true};
      final ctx = _ctx(tipo: 'admin', permissoes: map);
      for (final m in HomeModuleRegistry.all) {
        if (m.permissionKey == null) continue;
        expect(
          HomeModuleRegistry.isAllowed(m, ctx),
          isTrue,
          reason: 'admin deve ver ${m.id}',
        );
      }
    });
  });
}
