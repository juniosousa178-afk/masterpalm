// lib/screens/loja_config_screen.dart
// Configuração unificada da loja: identidade -> mídia -> tema -> fretes -> rodapé -> publicar
// ✅ CORRIGIDO: Alinhado 100% com public_catalog_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:diacritic/diacritic.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/catalog_avaliacoes_ordem.dart';
import '../core/hive_box_names.dart';
import '../screens/public_catalog_screen.dart';
import 'fretes_cupons_screen.dart';
import '../utils/image_provider.dart';
import '../services/store_resolver_facade.dart';
import '../services/upload_manager.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import '../services/catalogo_sync_service.dart';
import '../services/catalog_cache_service.dart';
import '../services/catalogo_config_service.dart';
import '../services/limits_guard.dart';
import '../services/sync_firestore_script.dart';
import '../core/logger.dart';
import '../core/plan_matrix.dart';
import '../core/plan_access_resolver.dart';
import '../widgets/catalog_color_field_editor.dart';
import '../widgets/catalog_store_palette_card.dart';
import '../widgets/catalog_visual_palette_presets_panel.dart';
import '../widgets/catalog_store_mini_preview.dart';
import '../theme/catalog_visual_palette_presets.dart';
import '../catalog/catalog_layout_config.dart';
import '../catalog/domain/catalog_custom_domain.dart';
import '../screens/catalogo/catalog_domain_setup_screen.dart';
import '../widgets/catalog_domain_section.dart';
import '../services/catalog_domain_workflow_service.dart';

part 'loja_config_tema_pane.dart';
part 'loja_config_widgets.dart';
part 'loja_config_part_cards.dart';
part 'loja_config_part_identidade_midias.dart';
part 'loja_config_part_hub_layout.dart';
part 'loja_config_part_pane_wrappers.dart';
part 'loja_config_part_pane_internals.dart';
part 'loja_config_part_pane_menu.dart';
part 'loja_config_part_pane_rodape.dart';
part 'loja_config_part_pane_layout.dart';
part 'loja_config_part_pane_dicas.dart';

enum _LayoutPreset { masterPadrao, masterLuxo, darkClean }
enum _MediaTab { desktop, mobile }
enum _Pane {
  identidade,
  midias,
  tema,
  layout,
  // fretes, cupons -> movidos para FretesCuponsScreen
  menu,
  dicas,
  rodape,
  financeiro,
  publicar,
}

/// Indicadores do hub da Loja Config (erro > pendência > ok).
enum _HubModuleSignal { error, pending, ok, neutral }

/// Filtro do hub por estado visual dos cards.
enum _HubModuleFilter { all, error, pending, ok, neutral }

/// Campos de [_LojaConfigScreenState._coletarProblemasSalvar] → módulo do hub.
const Map<String, _Pane> _kCampoSalvarParaPane = {
  'whatsapp': _Pane.identidade,
  'pedido_base': _Pane.identidade,
  'sac_whatsapp': _Pane.menu,
  'whatsapp_rodape': _Pane.rodape,
};

class LojaConfigScreen extends StatefulWidget {
  const LojaConfigScreen({super.key});

  @override
  State<LojaConfigScreen> createState() => _LojaConfigScreenState();
}

class _LojaConfigScreenState extends State<LojaConfigScreen>
    with TickerProviderStateMixin {
  // Cores do tema moderno
  static const Color _primaryColor = Color(0xFF6366F1);
  static const Color _secondaryColor = Color(0xFF8B5CF6);
  static const Color _successColor = Color(0xFF22C55E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _surfaceColor = Color(0xFFF8FAFC);

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final UploadManager _uploader = UploadManager(maxConcurrent: 3);

  // ✅ Timer para debounce do salvamento automático
  Timer? _autoSaveTimer;

  String _extFromName(String name) {
    final i = name.lastIndexOf('.');
    if (i == -1) return 'jpg';
    final ext = name.substring(i + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  String _activeStoreId() {
    if (_resolvedLojaId == null || _resolvedLojaId!.isEmpty) {
      throw StateError('Nenhuma loja ativa definida no LojaConfigScreen');
    }
    return _resolvedLojaId!;
  }

  void _goToHub() {
    setState(() => _hubMode = true);
  }

  void _openConfigModule(_Pane pane) {
    if (_paneLockedForCatalogConfig(pane)) {
      _showCatalogUpgradeDialog(_catalogPaneLockedMessage(pane));
      return;
    }
    setState(() {
      _pane = pane;
      _hubMode = false;
    });
    _scheduleFirstErrorFieldFocus(pane);
  }

  PlanAccessTier? _planAccessTier;

  bool get _isFreeLimitedCatalog =>
      _planAccessTier == PlanAccessTier.freeLimited;

  bool get _isBasicCatalog => _planAccessTier == PlanAccessTier.basic;

  bool get _showsPedidoBaseUrlField =>
      _planAccessTier == PlanAccessTier.intermediate ||
      _planAccessTier == PlanAccessTier.pro ||
      _planAccessTier == PlanAccessTier.trialFull ||
      _planAccessTier == PlanAccessTier.lifetime;

  bool _paneLockedForCatalogConfig(_Pane pane) {
    final t = _planAccessTier;
    if (t == null) return false;
    switch (t) {
      case PlanAccessTier.lifetime:
      case PlanAccessTier.trialFull:
      case PlanAccessTier.pro:
      case PlanAccessTier.intermediate:
        return false;
      case PlanAccessTier.basic:
        return pane == _Pane.financeiro;
      case PlanAccessTier.freeLimited:
        switch (pane) {
          case _Pane.identidade:
          case _Pane.midias:
          case _Pane.publicar:
            return false;
          default:
            return true;
        }
    }
  }

  String _catalogPaneLockedMessage(_Pane pane) {
    if (_isBasicCatalog && pane == _Pane.financeiro) {
      return 'Taxas avançadas e checkout online ficam disponíveis no plano Intermediário ou Pro.';
    }
    return 'No plano gratuito limitado você configura identidade, mídias e publicação. '
        'Temas, layout, menu e rodapé exigem plano Básico ou superior; taxas e checkout online no Intermediário.';
  }

  Future<void> _loadPlanAccessTier() async {
    try {
      final t = await PlanAccessResolver.currentTier();
      if (!mounted) return;
      setState(() {
        _planAccessTier = t;
        if (_paneLockedForCatalogConfig(_pane) && !_hubMode) {
          _hubMode = true;
          _pane = _Pane.identidade;
        }
      });
    } catch (_) {}
  }

  void _showCatalogUpgradeDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recurso do plano'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushNamed('/planos');
            },
            child: const Text('Ver planos'),
          ),
        ],
      ),
    );
  }

  /// Foco/scroll no primeiro campo com erro (uma vez por abertura do módulo; post-frame).
  void _scheduleFirstErrorFieldFocus(_Pane pane) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hubMode || _pane != pane) return;
      if (_listHubErrorMessagesForPane(pane).isEmpty) return;
      _tryFocusFirstModuleErrorField(pane);
    });
  }

  /// Primeiro campo lógico com erro, na mesma ordem de [_coletarProblemasSalvar] + nome/logo.
  String? _firstHubErrorFieldKeyForPane(_Pane pane) {
    final salvar = _coletarProblemasSalvar();

    if (pane == _Pane.publicar) {
      return null;
    }

    for (final p in salvar) {
      if (_kCampoSalvarParaPane[p.campo] == pane) {
        return p.campo;
      }
    }
    if (salvar.isEmpty) {
      if (pane == _Pane.identidade && _nomeCtrl.text.trim().isEmpty) {
        return 'nome_loja';
      }
      if (pane == _Pane.midias &&
          _logoUrlDesktop == null &&
          _logoUrlMobile == null) {
        return 'logo_midia';
      }
    }
    return null;
  }

  FocusNode? _focusNodeForHubFieldKey(String key) {
    return switch (key) {
      'nome_loja' => _focusNomeLoja,
      'whatsapp' => _focusWaVendedor,
      'pedido_base' => _focusPedidoBaseUrl,
      'sac_whatsapp' => _focusSacWhatsapp,
      'whatsapp_rodape' => _focusWhatsappRodape,
      _ => null,
    };
  }

  void _tryFocusFirstModuleErrorField(_Pane pane) {
    final id = _firstHubErrorFieldKeyForPane(pane);
    if (id == null) return;

    if (id == 'logo_midia') {
      final ctx = _midiasLogoSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.12,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    final fn = _focusNodeForHubFieldKey(id);
    if (fn == null) return;
    fn.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = fn.context;
      if (c != null) {
        Scrollable.ensureVisible(
          c,
          alignment: 0.18,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // --- Hub: baseline do rascunho por módulo (comparação de fatias do [_buildConfigMap]) ---
  static final Map<_Pane, List<String>> _kHubPaneTopLevelKeys = {
    _Pane.identidade: [
      'slug',
      'linkCurto',
      'subdominioMascara',
      'subdominioDominioBase',
      'nome',
      'whatsapp',
      'pedidoBaseUrl',
      'dominioCatalogo',
      'dominioStatus',
      'dominioUpdatedAt',
      'dominioProvider',
      'lojaId',
    ],
    _Pane.midias: [
      'media',
      'logoDesktopUrl',
      'logoMobileUrl',
      'bannersDesktop',
      'bannersMobile',
      'dLogoH',
      'dLogoW',
      'mLogoH',
      'mLogoW',
      'dBanH',
      'dBanW',
      'mBanH',
      'mBanW',
      'categoryVisuals',
    ],
    _Pane.tema: [
      'layoutPreset',
      'theme',
      'checkoutTheme',
      'uiColors',
      'catalogHeaderColors',
      'catalogFooterColors',
      'catalogDicasColors',
      'promoBar',
      'minimalSearch',
      'heroBanner',
      'minimalBestSellers',
    ],
    _Pane.layout: [
      'gridDesktopCols',
      'gridMobileCols',
      'cardShowShadow',
      'cardBorderRadius',
      'layoutCatalogo',
      'productCardSize',
      'minimalProductGrid',
    ],
    _Pane.menu: ['menu', 'quemSomos', 'sac'],
    _Pane.dicas: ['dicas'],
    _Pane.rodape: ['rodape', 'links'],
    _Pane.financeiro: ['taxas'],
    _Pane.publicar: [],
  };

  static const List<String> _kHubFretesTopKeys = [
    'freteProvider',
    'melhorEnvioToken',
    'correiosUser',
    'correiosSenha',
    'frenetToken',
    'fretes',
    'cupons',
  ];

  static final DeepCollectionEquality _hubDeepEq = DeepCollectionEquality();

  void _captureHubBaseline() {
    if (_resolvedLojaId == null) return;
    try {
      final m = _buildConfigMap(storeId: _activeStoreId());
      _hubBaselineMap = json.decode(json.encode(m)) as Map<String, dynamic>;
      _hubBaselineFreteConfig =
          _mergeFreteConfigCache == null ? null : json.decode(json.encode(_mergeFreteConfigCache));
      _hubBaselineCuponsMerge =
          _mergeCuponsCache == null ? null : json.decode(json.encode(_mergeCuponsCache));
      _hubBaselinePublicarCampanha = _campanhaAtiva;
      _hubBaselinePublicarRoleta = _roletaAtiva;
    } catch (_) {}
  }

  Map<String, dynamic> _hubSliceForKeys(Map<String, dynamic> full, List<String> keys) {
    final out = <String, dynamic>{};
    for (final k in keys) {
      if (full.containsKey(k)) out[k] = full[k];
    }
    return out;
  }

  bool _hubSliceDirty(Map<String, dynamic> currentFull, Map<String, dynamic>? baseline, List<String> keys) {
    if (baseline == null) return false;
    final a = _hubSliceForKeys(currentFull, keys);
    final b = _hubSliceForKeys(baseline, keys);
    return !_hubDeepEq.equals(a, b);
  }

  bool _hubModuleHasPendingChanges(_Pane pane, Map<String, dynamic> currentFull) {
    if (_hubBaselineMap == null) return false;
    if (pane == _Pane.publicar) {
      return _campanhaAtiva != _hubBaselinePublicarCampanha || _roletaAtiva != _hubBaselinePublicarRoleta;
    }
    final keys = _kHubPaneTopLevelKeys[pane];
    if (keys == null || keys.isEmpty) return false;
    return _hubSliceDirty(currentFull, _hubBaselineMap, keys);
  }

  bool _hubFretesShortcutHasPendingChanges(Map<String, dynamic> currentFull) {
    if (_hubBaselineMap == null) return false;
    if (_hubSliceDirty(currentFull, _hubBaselineMap, _kHubFretesTopKeys)) return true;
    if (!_hubDeepEq.equals(_mergeFreteConfigCache, _hubBaselineFreteConfig)) return true;
    if (!_hubDeepEq.equals(_mergeCuponsCache, _hubBaselineCuponsMerge)) return true;
    return false;
  }

  /// Hierarquia: erro de validação → alterações pendentes → ok (com baseline) → neutro.
  ({_HubModuleSignal signal, String? tooltip}) _hubCardStateForPane(
    _Pane pane,
    bool dirty,
    List<({String campo, String msg})> salvarItems,
    List<String> pubAvisos,
  ) {
    String? errDetail;
    for (final p in salvarItems) {
      if (_kCampoSalvarParaPane[p.campo] == pane) {
        errDetail = p.msg;
        break;
      }
    }
    if (errDetail == null && salvarItems.isEmpty) {
      if (pane == _Pane.identidade && _nomeCtrl.text.trim().isEmpty) {
        errDetail = 'Informe o nome da loja.';
      } else if (pane == _Pane.midias &&
          _logoUrlDesktop == null &&
          _logoUrlMobile == null) {
        errDetail = 'Adicione pelo menos uma logo (desktop ou mobile).';
      }
    }
    if (errDetail == null && pane == _Pane.publicar) {
      if (salvarItems.isNotEmpty || pubAvisos.isNotEmpty) {
        errDetail = [
          ...salvarItems.map((e) => e.msg),
          ...pubAvisos,
        ].join('\n');
      }
    }

    if (errDetail != null) {
      return (
        signal: _HubModuleSignal.error,
        tooltip: errDetail,
      );
    }
    if (dirty) {
      return (
        signal: _HubModuleSignal.pending,
        tooltip: 'Há alterações de rascunho neste módulo em relação ao último ponto salvo.',
      );
    }
    if (_hubBaselineMap != null) {
      return (
        signal: _HubModuleSignal.ok,
        tooltip: 'Sem pendências de rascunho nem problemas detectados neste módulo.',
      );
    }
    return (signal: _HubModuleSignal.neutral, tooltip: null);
  }

  List<String> _dedupeHubStrings(List<String> input) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in input) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  /// Mensagens de validação/publicação exibidas no hub — mesma base para o banner do módulo.
  List<String> _listHubErrorMessagesForPane(_Pane pane) {
    final salvar = _coletarProblemasSalvar();
    final pubAvisos = salvar.isEmpty ? _listaAvisosPublicarNomeLogo() : <String>[];

    if (pane == _Pane.publicar) {
      final m = <String>[];
      if (salvar.isNotEmpty) {
        m.addAll(salvar.map((e) => e.msg));
      }
      m.addAll(pubAvisos);
      return _dedupeHubStrings(m);
    }

    final out = <String>[];
    for (final p in salvar) {
      if (_kCampoSalvarParaPane[p.campo] == pane) {
        out.add(p.msg);
      }
    }
    if (salvar.isEmpty) {
      if (pane == _Pane.identidade && _nomeCtrl.text.trim().isEmpty) {
        out.add('Informe o nome da loja.');
      }
      if (pane == _Pane.midias &&
          _logoUrlDesktop == null &&
          _logoUrlMobile == null) {
        out.add('Adicione pelo menos uma logo (desktop ou mobile).');
      }
    }
    return _dedupeHubStrings(out);
  }

  Widget _buildModulePaneErrorBanner(BuildContext context, ColorScheme cs, _Pane pane) {
    return _LojaConfigModulePaneErrorBanner(
      messages: _listHubErrorMessagesForPane(pane),
      colorScheme: cs,
    );
  }

  ({_HubModuleSignal signal, String? tooltip}) _hubCardStateFretes(bool dirty) {
    if (dirty) {
      return (
        signal: _HubModuleSignal.pending,
        tooltip: 'Há alterações de fretes ou cupons no rascunho em relação ao último ponto salvo.',
      );
    }
    if (_hubBaselineMap != null) {
      return (
        signal: _HubModuleSignal.ok,
        tooltip: 'Sem alterações pendentes de fretes/cupons no rascunho.',
      );
    }
    return (
      signal: _HubModuleSignal.neutral,
      tooltip: 'Abrir fretes e cupons em tela dedicada.',
    );
  }

  bool _hubFilterAcceptsSignal(_HubModuleFilter filter, _HubModuleSignal signal) {
    return switch (filter) {
      _HubModuleFilter.all => true,
      _HubModuleFilter.error => signal == _HubModuleSignal.error,
      _HubModuleFilter.pending => signal == _HubModuleSignal.pending,
      _HubModuleFilter.ok => signal == _HubModuleSignal.ok,
      _HubModuleFilter.neutral => signal == _HubModuleSignal.neutral,
    };
  }

  /// Ordenação visual do hub: erro → pendente → ok → neutro (empate = ordem de [_lojaConfigNavItems]).
  int _hubSignalPriority(_HubModuleSignal s) {
    return switch (s) {
      _HubModuleSignal.error => 0,
      _HubModuleSignal.pending => 1,
      _HubModuleSignal.ok => 2,
      _HubModuleSignal.neutral => 3,
    };
  }

  /// Normaliza texto para busca (minúsculas + sem acentos, via pacote [diacritic]).
  String _hubFoldForSearch(String raw) => removeDiacritics(raw.toLowerCase());

  bool _hubSearchMatchesModule(Map<String, dynamic> item, String queryFolded) {
    if (queryFolded.isEmpty) return true;
    final label = _hubFoldForSearch('${item['label'] ?? ''}');
    final sub = _hubFoldForSearch('${item['subtitle'] ?? ''}');
    final rail = _hubFoldForSearch('${item['railLabel'] ?? ''}');
    return label.contains(queryFolded) ||
        sub.contains(queryFolded) ||
        rail.contains(queryFolded);
  }

  /// Texto agregado para o atalho Fretes & Cupons (título + subtítulo + palavras-chave).
  static const String _kHubFretesSearchBlob =
      'fretes cupons frete cupom cupons desconto entrega envio shipping correios melhor envio melhorenvio frenet tela dedicada';

  bool _hubSearchMatchesFretes(String queryFolded) {
    if (queryFolded.isEmpty) return true;
    return _hubFoldForSearch(_kHubFretesSearchBlob).contains(queryFolded);
  }

  /// Contexto compartilhado para navegação por erros no hub (sem duplicar leitura de draft).
  ({
    Map<String, dynamic>? currentFull,
    List<({String campo, String msg})> hubSalvar,
    List<String> hubPubAvisos,
    _HubModuleSignal fretesSignal,
  }) _hubNavigationContext() {
    Map<String, dynamic>? currentFull;
    try {
      if (_resolvedLojaId != null) {
        currentFull = _buildConfigMap(storeId: _activeStoreId());
      }
    } catch (_) {}
    final hubSalvar = _coletarProblemasSalvar();
    final hubPubAvisos = hubSalvar.isEmpty ? _listaAvisosPublicarNomeLogo() : <String>[];
    final fretesDirty =
        currentFull != null && _hubFretesShortcutHasPendingChanges(currentFull);
    final fretesSignal = _hubCardStateFretes(fretesDirty).signal;
    return (
      currentFull: currentFull,
      hubSalvar: hubSalvar,
      hubPubAvisos: hubPubAvisos,
      fretesSignal: fretesSignal,
    );
  }

  /// Ordem global do hub (sem filtro/busca): Fretes com `origIndex` -1, depois módulos na ordem de [_lojaConfigNavItems].
  List<({bool fretes, _Pane? pane, _HubModuleSignal signal, int origIndex})> _hubGlobalSortedRows({
    required Map<String, dynamic>? currentFull,
    required List<({String campo, String msg})> hubSalvar,
    required List<String> hubPubAvisos,
    required _HubModuleSignal fretesSignal,
  }) {
    final nav = _lojaConfigNavItems();
    final rows = <({bool fretes, _Pane? pane, _HubModuleSignal signal, int origIndex})>[];
    rows.add((fretes: true, pane: null, signal: fretesSignal, origIndex: -1));
    for (var i = 0; i < nav.length; i++) {
      final item = nav[i];
      final pane = item['pane'] as _Pane;
      final dirty =
          currentFull != null && _hubModuleHasPendingChanges(pane, currentFull);
      final signal = _hubCardStateForPane(pane, dirty, hubSalvar, hubPubAvisos).signal;
      rows.add((fretes: false, pane: pane, signal: signal, origIndex: i));
    }
    rows.sort((a, b) {
      final c = _hubSignalPriority(a.signal).compareTo(_hubSignalPriority(b.signal));
      if (c != 0) return c;
      return a.origIndex.compareTo(b.origIndex);
    });
    return rows;
  }

  /// Abre o primeiro item em erro na ordem global do hub (ignora filtro/busca). Fretes só se `signal == error`.
  void _openFirstHubErrorTarget() {
    final ctx = _hubNavigationContext();
    final rows = _hubGlobalSortedRows(
      currentFull: ctx.currentFull,
      hubSalvar: ctx.hubSalvar,
      hubPubAvisos: ctx.hubPubAvisos,
      fretesSignal: ctx.fretesSignal,
    );

    for (final r in rows) {
      if (r.signal != _HubModuleSignal.error) continue;
      _openHubErrorTarget((fretes: r.fretes, pane: r.pane));
      return;
    }
  }

  /// Itens anterior/próximo na fila global de erros (mesma ordem do hub). Só posiciona se o painel atual estiver na fila (linhas de módulo, não Fretes).
  ({({bool fretes, _Pane? pane})? prev, ({bool fretes, _Pane? pane})? next}) _hubErrorPrevNextForCurrentPane() {
    final ctx = _hubNavigationContext();
    final rows = _hubGlobalSortedRows(
      currentFull: ctx.currentFull,
      hubSalvar: ctx.hubSalvar,
      hubPubAvisos: ctx.hubPubAvisos,
      fretesSignal: ctx.fretesSignal,
    );
    final errs = rows.where((r) => r.signal == _HubModuleSignal.error).toList();
    for (var i = 0; i < errs.length; i++) {
      final e = errs[i];
      if (e.fretes) continue;
      if (e.pane == _pane) {
        final p = i > 0 ? errs[i - 1] : null;
        final n = i + 1 < errs.length ? errs[i + 1] : null;
        return (
          prev: p != null ? (fretes: p.fretes, pane: p.pane) : null,
          next: n != null ? (fretes: n.fretes, pane: n.pane) : null,
        );
      }
    }
    return (prev: null, next: null);
  }

  void _openHubErrorTarget(({bool fretes, _Pane? pane}) t) {
    if (t.fretes) {
      unawaited(_openFretesCuponsScreenIfAllowed());
      return;
    }
    _openConfigModule(t.pane!);
  }

  Future<void> _openFretesCuponsScreenIfAllowed() async {
    if (!await PlanAccessResolver.allows(PlanGateFeature.fretesCupons)) {
      if (!mounted) return;
      _showCatalogUpgradeDialog(
        PlanMatrix.upgradeHint(PlanGateFeature.fretesCupons),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const FretesCuponsScreen(),
      ),
    );
  }

  void _openPrevHubErrorTarget() {
    final p = _hubErrorPrevNextForCurrentPane().prev;
    if (p == null) return;
    _openHubErrorTarget(p);
  }

  void _openNextHubErrorTarget() {
    final n = _hubErrorPrevNextForCurrentPane().next;
    if (n == null) return;
    _openHubErrorTarget(n);
  }

  // ---------------------------------
  // ESTADO GERAL
  // ---------------------------------
  bool _carregando = true;
  bool _salvando = false;
  bool _sincronizando = false;
  bool _erroCarregamento = false;
  String _mensagemErro = '';
  bool _offline = false;

  late Box _configBox;
  String? _slug;
  String? _lojaId;
  String? _resolvedLojaId;

  /// Evita [initState] + pull-to-refresh simultâneos disparando dois loads completos.
  Future<void>? _initConfigInFlight;

  /// Preserva `frete_config` / `cupons` do draft sem `get()` em todo auto-save (ver [_salvarRascunho]).
  dynamic _mergeFreteConfigCache;
  dynamic _mergeCuponsCache;

  int? _catalogPaletteContentHash;
  List<CatalogColorSuggestion>? _cachedPaletteSuggestions;
  List<CatalogColorSuggestion>? _cachedPaletteOverview;

  int _debugLojaConfigBuildCount = 0;

  /// Snapshot do rascunho após carga/salvamento — comparação por módulo (hub).
  Map<String, dynamic>? _hubBaselineMap;
  dynamic _hubBaselineFreteConfig;
  dynamic _hubBaselineCuponsMerge;
  bool _hubBaselinePublicarCampanha = false;
  bool _hubBaselinePublicarRoleta = false;

  _Pane _pane = _Pane.identidade;
  /// `true` = painel inicial com cards; `false` = tela cheia de um módulo (mesmo [State], sem duplicar lógica).
  bool _hubMode = true;
  /// Filtro dos cards no hub (módulos + atalho Fretes & Cupons).
  _HubModuleFilter _hubModuleFilter = _HubModuleFilter.all;
  /// Busca por nome/descrição no hub (combina com o filtro por estado).
  final TextEditingController _hubSearchCtrl = TextEditingController();
  _MediaTab _mediaTab = _MediaTab.desktop;
  _LayoutPreset? _layoutPreset;

  final GlobalKey<_PaneTemaWidgetState> _paneTemaKey = GlobalKey<_PaneTemaWidgetState>();

  void _invalidateCatalogPaletteCaches() {
    _catalogPaletteContentHash = null;
    _cachedPaletteSuggestions = null;
    _cachedPaletteOverview = null;
  }

  /// Atualiza cores de tema sem [State.setState] no estado principal — reconstrói só o subtree do painel Temas e Cores.
  void _applyTemaColor(VoidCallback apply) {
    apply();
    _invalidateCatalogPaletteCaches();
    _paneTemaKey.currentState?.setState(() {});
  }

  // Tutorial flutuante (somente na primeira configuração)
  bool _mostrarTutorial = false;
  int _tutorialPasso = 0;

  // Campos com erro de validação (para destacar ao falhar Salvar)
  final Set<String> _camposComErro = {};

  /// Foco no primeiro campo com erro ao abrir o módulo (não substitui os controllers).
  final FocusNode _focusNomeLoja = FocusNode(debugLabel: 'lojaConfig_nomeLoja');
  final FocusNode _focusWaVendedor = FocusNode(debugLabel: 'lojaConfig_waVendedor');
  final FocusNode _focusPedidoBaseUrl = FocusNode(debugLabel: 'lojaConfig_pedidoBase');
  final FocusNode _focusSacWhatsapp = FocusNode(debugLabel: 'lojaConfig_sacWa');
  final FocusNode _focusWhatsappRodape = FocusNode(debugLabel: 'lojaConfig_waRodape');
  final GlobalKey _midiasLogoSectionKey = GlobalKey(debugLabel: 'lojaConfig_midiasLogo');

  // ---------------------------------
  // CONTROLES BÁSICOS / IDENTIDADE
  // ---------------------------------
  final TextEditingController _nomeCtrl = TextEditingController();
  final TextEditingController _slugCtrl = TextEditingController(); // ✅ SLUG AMIGÁVEL
  final TextEditingController _linkCurtoCtrl = TextEditingController(); // ✅ LINK CURTO: /c/{linkCurto} → /loja/{slug}
  final TextEditingController _subdominioMascaraCtrl = TextEditingController(); // ✅ MÁSCARA: nathypratasefolheados.masterpalm.com
  final TextEditingController _subdominioDominioBaseCtrl = TextEditingController(text: 'mastepalm.com.br');
  final TextEditingController _waCtrl = TextEditingController();
  final TextEditingController _pedidoBaseCtrl = TextEditingController();
  final TextEditingController _dominioCatalogoCtrl = TextEditingController();
  String _dominioCatalogoStatus = kDominioStatusNaoConfigurado;
  String? _dominioProviderId;
  int? _dominioCatalogoUpdatedAt;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _catalogDomainOpSub;
  String? _catalogDomainOpExpectedTarget;
  String? _catalogDomainOpDnsObserved;
  String? _catalogDomainOpLastCheckLabel;
  String? _catalogDomainOpError;

  // ---------------------------------
  // MÍDIAS (logo / banners)
  // ---------------------------------
  String? _logoUrlDesktop;
  String? _logoUrlMobile;
  List<String> _bannersDesktop = [];
  List<String> _bannersMobile = [];
  bool _logoDesktopAlterado = false;
  bool _logoMobileAlterado = false;
  bool _bannersDesktopAlterados = false;
  bool _bannersMobileAlterados = false;

  // Dimensões logo/banners
  final TextEditingController _dLogoH = TextEditingController(text: '105');
  final TextEditingController _dLogoW = TextEditingController(text: '327');
  final TextEditingController _mLogoH = TextEditingController(text: '105');
  final TextEditingController _mLogoW = TextEditingController(text: '327');

  final TextEditingController _dBanH = TextEditingController(text: '256');
  final TextEditingController _dBanW = TextEditingController(text: '1280');
  final TextEditingController _mBanH = TextEditingController(text: '300');
  final TextEditingController _mBanW = TextEditingController(text: '562');

  // ---------------------------------
  // TEMA / CORES (mantido para compatibilidade)
  // ---------------------------------
  Color _cFundo = const Color(0xFF050509);
  Color _cCard = const Color(0xFF11111A);
  Color _cTexto = Colors.white;
  Color _cPrimaria = const Color(0xFF00A8FF);
  Color _cBotaoTexto = Colors.white;
  Color _cCabecalho = const Color(0xFF050509);

  // Checkout
  Color _cCarrinhoCard = const Color(0xFF11111A);
  Color _cCarrinhoCampo = const Color(0xFF1E1E24);
  Color _cCarrinhoTexto = Colors.white70;
  Color _cCarrinhoLabel = Colors.white;
  Color _cCarrinhoTotal = Colors.greenAccent;

  // ✅ NOVO: Cores adicionais unificadas (uiColors expandido)
  Color _cTextSecondary = const Color(0xFFB0B0B0);
  Color _cCardTextPrimary = Colors.white;
  Color _cCardTextSecondary = const Color(0xFFB0B0B0);
  Color _cPriceHighlight = const Color(0xFF4ADE80);
  Color _cDanger = const Color(0xFFEF4444);
  Color _cFieldHint = const Color(0xFF6B7280);
  Color _cFieldBorder = const Color(0xFF374151);
  Color _cDivider = const Color(0xFF374151);
  Color _cButtonSecondaryBg = Colors.transparent;
  Color _cButtonSecondaryText = const Color(0xFF00A8FF);
  Color _cButtonSecondaryBorder = const Color(0xFF00A8FF);
  Color _cBadgeBackground = const Color(0xFF00A8FF).withOpacity(0.15);
  Color _cBadgeText = const Color(0xFF00A8FF);
  Color _cIcon = Colors.white;
  Color _cShadow = Colors.black45;

  // ✅ NOVO: Cores separadas do Cabeçalho
  Color _cHeaderText = Colors.white;
  Color _cHeaderIcon = Colors.white;
  Color _cHeaderSearchBg = Colors.white10;
  Color _cHeaderSearchText = Colors.white;
  Color _cHeaderSearchHint = Colors.white70;

  // ✅ NOVO: Cores separadas do Rodapé
  Color _cFooterBackground = const Color(0xFF050509);
  Color _cFooterText = Colors.white;
  Color _cFooterTextSecondary = Colors.white70;
  Color _cFooterIcon = Colors.white70;
  Color _cFooterLink = const Color(0xFF00A8FF);
  Color _cFooterDivider = Colors.white24;

  // ✅ NOVO: Cores da tela Dicas e Informações
  Color _cDicasBackground = const Color(0xFFF8F9FA);
  Color _cDicasFooterBg = Colors.white;
  Color _cDicasFooterText = Colors.black87;
  Color _cDicasButtonBg = const Color(0xFF22C55E);
  Color _cDicasButtonText = Colors.white;
  Color _cDicasTopicPrimary = const Color(0xFF22C55E);

  // Layout cards
  int _gridDesktopCols = 4;
  int _gridMobileCols = 2;
  bool _cardShowShadow = true;
  double _cardBorderRadius = 20;
  String _layoutCatalogo = CatalogLayoutConfig.classic;
  String _productCardSize = 'medium';

  /// Acordeão aberto no painel Layout dos cards (mesmo padrão de Temas e Cores).
  String? _layoutPaneAccordionOpenId = 'layout_geral';

  bool _promoBarEnabled = false;
  final TextEditingController _promoBarTextCtrl = TextEditingController();
  final TextEditingController _promoBarLinkCtrl = TextEditingController();
  Color _promoBarBg = const Color(0xFFFF4F96);
  Color _promoBarText = Colors.white;
  /// Texto longo do letreiro rola automaticamente (layout minimalista).
  bool _promoBarMarquee = true;

  final TextEditingController _minimalSearchPlaceholderCtrl =
      TextEditingController(text: 'O que você está procurando?');

  bool _minimalBestSellersEnabled = true;
  final TextEditingController _minimalBestSellersTitleCtrl =
      TextEditingController(text: 'Mais vendidos');
  final TextEditingController _minimalBestSellersCountCtrl =
      TextEditingController(text: '10');

  bool _heroBannerEnabled = false;
  final TextEditingController _heroBannerTitleCtrl = TextEditingController();
  final TextEditingController _heroBannerSubtitleCtrl = TextEditingController();
  final TextEditingController _heroBannerButtonTextCtrl = TextEditingController();
  final TextEditingController _heroBannerButtonLinkCtrl = TextEditingController();
  final TextEditingController _heroBannerImageCtrl = TextEditingController();
  final TextEditingController _heroBannerMobileImageCtrl = TextEditingController();
  // Banner minimalista: cartão + tipografia (separado do tema geral)
  Color _heroCardBg = const Color(0xFFE8E8E8);
  Color _heroTitleColor = Colors.white;
  Color _heroSubtitleColor = Colors.white;
  Color _heroButtonBg = const Color(0xFF00A8FF);
  Color _heroButtonTextColor = Colors.white;
  final TextEditingController _heroBannerHeightCtrl =
      TextEditingController(text: '180');
  final TextEditingController _heroBannerCardRadiusCtrl =
      TextEditingController(text: '18');
  final TextEditingController _heroBannerOverlayCtrl =
      TextEditingController(text: '0.16');
  final TextEditingController _heroBannerTitleSizeCtrl =
      TextEditingController(text: '17');
  final TextEditingController _heroBannerSubtitleSizeCtrl =
      TextEditingController(text: '13');
  final TextEditingController _heroBannerButtonSizeCtrl =
      TextEditingController(text: '13');
  final TextEditingController _heroBannerButtonRadiusCtrl =
      TextEditingController(text: '8');
  int _heroTitleFontWeight = 600;
  int _heroSubtitleFontWeight = 400;
  int _heroButtonFontWeight = 600;
  String _heroTitleCase = 'none';
  String _heroSubtitleCase = 'none';
  String _heroButtonCase = 'none';

  final TextEditingController _catImgModaCtrl = TextEditingController();
  final TextEditingController _catImgCalcadosCtrl = TextEditingController();
  final TextEditingController _catImgBolsasCtrl = TextEditingController();
  final TextEditingController _catImgCategoriaCtrl = TextEditingController();
  final TextEditingController _catImgCategoriaIdCtrl = TextEditingController();
  final TextEditingController _catImgUrlCtrl = TextEditingController();
  String? _catSelectedFromStore;
  Map<String, String> _categoryImagesByName = {};
  Map<String, String> _categoryImagesById = {};
  List<String> _knownCategoryNames = [];

  // ---------------------------------
  // FRETES
  // ---------------------------------
  String _freteProvider = 'manual';
  final TextEditingController _melhorEnvioTokenCtrl = TextEditingController();
  final TextEditingController _correiosUserCtrl = TextEditingController();
  final TextEditingController _correiosSenhaCtrl = TextEditingController();
  final TextEditingController _frenetTokenCtrl = TextEditingController();

  final TextEditingController _freteNomeCtrl = TextEditingController();
  final TextEditingController _freteValorCtrl = TextEditingController();
  final List<Map<String, dynamic>> _fretes = [];

  // ---------------------------------
  // CUPONS
  // ---------------------------------
  final TextEditingController _cupomNomeCtrl = TextEditingController();
  final TextEditingController _cupomValorCtrl = TextEditingController();
  final List<Map<String, dynamic>> _cupons = [];

  // ---------------------------------
  // MENU & PÁGINAS
  // ---------------------------------
  bool _menuShowCategorias = true;
  bool _menuShowEntrar = false;
  bool _menuShowContato = true;
  bool _menuShowSac = true;
  bool _menuShowQuemSomos = true;
  bool _menuShowDicas = true;
  bool _exibirAvaliacoesCatalogo = false;
  CatalogAvaliacoesOrdem _catalogAvaliacoesOrdem =
      CatalogAvaliacoesOrdem.maisRecentes;
  bool _showMobileMenuGrid = true;

  /// Dicas e informações (cuidados, garantias, qualidade) – lista de mapas para o catálogo.
  List<Map<String, dynamic>> _dicas = [];

  final TextEditingController _quemSomosTituloCtrl =
      TextEditingController(text: 'Quem somos');
  final TextEditingController _quemSomosTextoCtrl = TextEditingController();

  /// Página "Sobre a loja" no catálogo público (rodapé → Sobre a loja).
  final TextEditingController _sobreLojaTituloCtrl = TextEditingController();
  final TextEditingController _sobreLojaSubtituloCtrl = TextEditingController();
  final TextEditingController _sobreLojaBannerUrlCtrl = TextEditingController();
  final TextEditingController _sobreLojaIntroCtrl = TextEditingController();
  final TextEditingController _sobreLojaMissaoCtrl = TextEditingController();
  final TextEditingController _sobreLojaVisaoCtrl = TextEditingController();
  final TextEditingController _sobreLojaValoresCtrl = TextEditingController();
  final TextEditingController _sobreLojaDestaquesCtrl = TextEditingController();
  final TextEditingController _sobreLojaEnderecoCtrl = TextEditingController();
  final TextEditingController _sobreLojaHorarioCtrl = TextEditingController();
  final TextEditingController _sobreLojaEmailCtrl = TextEditingController();
  bool _sobreLojaMostrarLegais = true;

  // ---------------------------------
  // TAXAS FINANCEIRAS (Relatórios Financeiros e Financeiro & Metas)
  // Valores padrão; usuário pode alterar em Loja Config > Taxas Financeiras
  // ---------------------------------
  final TextEditingController _taxaCartaoCtrl = TextEditingController(text: '5.0');
  final TextEditingController _taxaMEICtrl = TextEditingController(text: '3.5');
  final TextEditingController _custosFixosCtrl = TextEditingController(text: '10.0');
  final TextEditingController _custoEmbalagemCtrl = TextEditingController(text: '3.0');

  // SAC
  final TextEditingController _sacWhatsappCtrl = TextEditingController();
  final TextEditingController _sacEmailCtrl = TextEditingController();

  // ---------------------------------
  // RODAPÉ
  // ---------------------------------
  final List<String> _payments = [];
  final TextEditingController _instagramCtrl = TextEditingController();
  final TextEditingController _facebookCtrl = TextEditingController();
  final TextEditingController _tiktokCtrl = TextEditingController();
  final TextEditingController _telegramCtrl = TextEditingController();
  final TextEditingController _kwaiCtrl = TextEditingController();
  final TextEditingController _linkedinCtrl = TextEditingController();
  final TextEditingController _emailRodapeCtrl = TextEditingController();
  final TextEditingController _whatsappRodapeCtrl = TextEditingController();
  final TextEditingController _sobreCtrl = TextEditingController();
  final TextEditingController _trocasCtrl = TextEditingController();
  final TextEditingController _loginCtrl = TextEditingController();
  final TextEditingController _razaoCtrl = TextEditingController();
  final TextEditingController _cnpjCtrl = TextEditingController();

  // ---------------------------------
  // CAMPANHAS E ROLETA (Sorteios)
  // ---------------------------------
  bool _campanhaAtiva = false;
  bool _roletaAtiva = false;
  String? _campanhaAtivaId;
  String? _campanhaAtivaNome;

  // ---------------------------------
  // INIT / LOAD
  // ---------------------------------
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
    unawaited(_initConfig());
    unawaited(_loadPlanAccessTier());
    _verificarConectividade();
    _setupAutoSaveListeners();
  }

  // ✅ Configura listeners para auto-save em todos os campos de texto
  void _setupAutoSaveListeners() {
    // Identidade
    _nomeCtrl.addListener(_scheduleAutoSave);
    _slugCtrl.addListener(_scheduleAutoSave);
    _linkCurtoCtrl.addListener(_scheduleAutoSave);
    _subdominioMascaraCtrl.addListener(_scheduleAutoSave);
    _subdominioDominioBaseCtrl.addListener(_scheduleAutoSave);
    _waCtrl.addListener(_scheduleAutoSave);
    _pedidoBaseCtrl.addListener(_scheduleAutoSave);
    _dominioCatalogoCtrl.addListener(_onDominioCatalogoEdited);

    // Dimensões de mídia
    _dLogoH.addListener(_scheduleAutoSave);
    _dLogoW.addListener(_scheduleAutoSave);
    _mLogoH.addListener(_scheduleAutoSave);
    _mLogoW.addListener(_scheduleAutoSave);
    _dBanH.addListener(_scheduleAutoSave);
    _dBanW.addListener(_scheduleAutoSave);
    _mBanH.addListener(_scheduleAutoSave);
    _mBanW.addListener(_scheduleAutoSave);
    _promoBarTextCtrl.addListener(_scheduleAutoSave);
    _promoBarLinkCtrl.addListener(_scheduleAutoSave);
    _minimalSearchPlaceholderCtrl.addListener(_scheduleAutoSave);
    _heroBannerTitleCtrl.addListener(_scheduleAutoSave);
    _heroBannerSubtitleCtrl.addListener(_scheduleAutoSave);
    _heroBannerButtonTextCtrl.addListener(_scheduleAutoSave);
    _heroBannerButtonLinkCtrl.addListener(_scheduleAutoSave);
    _heroBannerImageCtrl.addListener(_scheduleAutoSave);
    _heroBannerMobileImageCtrl.addListener(_scheduleAutoSave);
    _heroBannerHeightCtrl.addListener(_scheduleAutoSave);
    _heroBannerCardRadiusCtrl.addListener(_scheduleAutoSave);
    _heroBannerOverlayCtrl.addListener(_scheduleAutoSave);
    _heroBannerTitleSizeCtrl.addListener(_scheduleAutoSave);
    _heroBannerSubtitleSizeCtrl.addListener(_scheduleAutoSave);
    _heroBannerButtonSizeCtrl.addListener(_scheduleAutoSave);
    _heroBannerButtonRadiusCtrl.addListener(_scheduleAutoSave);
    _catImgCategoriaCtrl.addListener(_scheduleAutoSave);
    _catImgCategoriaIdCtrl.addListener(_scheduleAutoSave);
    _catImgUrlCtrl.addListener(_scheduleAutoSave);
    _minimalBestSellersTitleCtrl.addListener(_scheduleAutoSave);
    _minimalBestSellersCountCtrl.addListener(_scheduleAutoSave);

    // Fretes e Cupons
    _melhorEnvioTokenCtrl.addListener(_scheduleAutoSave);
    _correiosUserCtrl.addListener(_scheduleAutoSave);
    _correiosSenhaCtrl.addListener(_scheduleAutoSave);
    _frenetTokenCtrl.addListener(_scheduleAutoSave);
    _freteNomeCtrl.addListener(_scheduleAutoSave);
    _freteValorCtrl.addListener(_scheduleAutoSave);
    _cupomNomeCtrl.addListener(_scheduleAutoSave);
    _cupomValorCtrl.addListener(_scheduleAutoSave);

    // Menu e Páginas
    _quemSomosTituloCtrl.addListener(_scheduleAutoSave);
    _quemSomosTextoCtrl.addListener(_scheduleAutoSave);
    _sobreLojaTituloCtrl.addListener(_scheduleAutoSave);
    _sobreLojaSubtituloCtrl.addListener(_scheduleAutoSave);
    _sobreLojaBannerUrlCtrl.addListener(_scheduleAutoSave);
    _sobreLojaIntroCtrl.addListener(_scheduleAutoSave);
    _sobreLojaMissaoCtrl.addListener(_scheduleAutoSave);
    _sobreLojaVisaoCtrl.addListener(_scheduleAutoSave);
    _sobreLojaValoresCtrl.addListener(_scheduleAutoSave);
    _sobreLojaDestaquesCtrl.addListener(_scheduleAutoSave);
    _sobreLojaEnderecoCtrl.addListener(_scheduleAutoSave);
    _sobreLojaHorarioCtrl.addListener(_scheduleAutoSave);
    _sobreLojaEmailCtrl.addListener(_scheduleAutoSave);
    _sacWhatsappCtrl.addListener(_scheduleAutoSave);
    _sacEmailCtrl.addListener(_scheduleAutoSave);

    // Rodapé
    _instagramCtrl.addListener(_scheduleAutoSave);
    _facebookCtrl.addListener(_scheduleAutoSave);
    _tiktokCtrl.addListener(_scheduleAutoSave);
    _telegramCtrl.addListener(_scheduleAutoSave);
    _kwaiCtrl.addListener(_scheduleAutoSave);
    _linkedinCtrl.addListener(_scheduleAutoSave);
    _emailRodapeCtrl.addListener(_scheduleAutoSave);
    _whatsappRodapeCtrl.addListener(_scheduleAutoSave);
    _sobreCtrl.addListener(_scheduleAutoSave);
    _trocasCtrl.addListener(_scheduleAutoSave);
    _loginCtrl.addListener(_scheduleAutoSave);
    _razaoCtrl.addListener(_scheduleAutoSave);
    _cnpjCtrl.addListener(_scheduleAutoSave);
  }

  void _onDominioCatalogoEdited() {
    if (normalizeCatalogDomainInput(_dominioCatalogoCtrl.text).isEmpty) {
      if (_dominioCatalogoStatus != kDominioStatusNaoConfigurado || _dominioProviderId != null) {
        setState(() {
          _dominioCatalogoStatus = kDominioStatusNaoConfigurado;
          _dominioProviderId = null;
        });
      }
    }
    _scheduleSyncCatalogDomainListener();
    _scheduleAutoSave();
  }

  void _scheduleSyncCatalogDomainListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCatalogDomainListener();
    });
  }

  String? _formatCatalogDomainCheckAt(dynamic v) {
    if (v == null) return null;
    DateTime? dt;
    if (v is Timestamp) {
      dt = v.toDate();
    }
    dt ??= DateTime.tryParse(v.toString());
    if (dt == null) return null;
    final d = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  void _syncCatalogDomainListener() {
    _catalogDomainOpSub?.cancel();
    _catalogDomainOpSub = null;
    final lojaStr = _resolvedLojaId?.trim() ?? '';
    if (lojaStr.isEmpty) return;
    final raw = normalizeCatalogDomainInput(_dominioCatalogoCtrl.text);
    if (raw.isEmpty) {
      if (mounted) {
        setState(() {
          _catalogDomainOpExpectedTarget = null;
          _catalogDomainOpDnsObserved = null;
          _catalogDomainOpLastCheckLabel = null;
          _catalogDomainOpError = null;
        });
      }
      return;
    }
    final host = recommendedCatalogFqdn(raw);
    _catalogDomainOpSub = FirebaseFirestore.instance
        .collection('lojas')
        .doc(lojaStr)
        .collection('dominios_catalogo')
        .doc(host)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      if (!snap.exists || snap.data() == null) {
        setState(() {
          _catalogDomainOpExpectedTarget = null;
          _catalogDomainOpDnsObserved = null;
          _catalogDomainOpLastCheckLabel = null;
          _catalogDomainOpError = null;
        });
        return;
      }
      final d = snap.data()!;
      final exp = (d['expectedTarget'] ?? '').toString().trim();
      final obs = (d['dnsObservedTarget'] ?? '').toString().trim();
      final err = (d['lastError'] ?? '').toString().trim();
      final st = (d['status'] ?? '').toString().trim();
      setState(() {
        _catalogDomainOpExpectedTarget = exp.isNotEmpty ? exp : kCatalogPublicCnameTarget;
        _catalogDomainOpDnsObserved = obs.isNotEmpty ? obs : null;
        _catalogDomainOpLastCheckLabel = _formatCatalogDomainCheckAt(d['lastCheckAt']);
        _catalogDomainOpError = err.isNotEmpty ? err : null;
        if (st.isNotEmpty) {
          _dominioCatalogoStatus = dominioStatusFromStorage(st, hasDomain: true);
        }
      });
    });
  }

  Future<void> _addDominioCatalogoAndOpenGuide() async {
    final norm = normalizeCatalogDomainInput(_dominioCatalogoCtrl.text);
    if (norm.isEmpty) {
      _snack('Informe o domínio desejado.', isError: true);
      return;
    }
    final loja = _resolvedLojaId?.trim() ?? '';
    if (loja.isEmpty) {
      _snack('Loja ativa não encontrada.', isError: true);
      return;
    }
    setState(() => _salvando = true);
    try {
      final res = await CatalogDomainWorkflowService.submitRequest(
        lojaId: loja,
        dominioUserInput: norm,
        providerId: _dominioProviderId,
      );
      final hostFinal = (res['hostFinal'] ?? '').toString().trim();
      final status = (res['status'] ?? kDominioStatusSolicitado).toString().trim();
      final upd = (res['dominioUpdatedAt'] as num?)?.toInt();
      if (!mounted) return;
      setState(() {
        if (hostFinal.isNotEmpty) {
          _dominioCatalogoCtrl.text = hostFinal;
        } else {
          _dominioCatalogoCtrl.text = norm;
        }
        _dominioCatalogoStatus = dominioStatusFromStorage(status, hasDomain: true);
        _dominioCatalogoUpdatedAt = upd ?? DateTime.now().millisecondsSinceEpoch;
        final p = res['providerId']?.toString().trim();
        if (p != null && p.isNotEmpty) {
          _dominioProviderId = p;
        }
      });
      _scheduleSyncCatalogDomainListener();
      await _salvarRascunho(validar: false);
      if (!mounted) return;
      await _openCatalogDomainSetupScreen();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        _snack(
          CatalogDomainWorkflowService.messageFromFunctionsException(e) ??
              'Erro ao registrar domínio.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _snack('Erro ao registrar domínio: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _openCatalogDomainGuideOnly() async {
    await _openCatalogDomainSetupScreen();
  }

  Future<void> _openCatalogDomainSetupScreen() async {
    final norm = normalizeCatalogDomainInput(_dominioCatalogoCtrl.text);
    final loja = _resolvedLojaId?.trim() ?? '';
    if (loja.isEmpty) {
      _snack('Loja ativa não encontrada.', isError: true);
      return;
    }
    final result = await Navigator.of(context).push<CatalogDomainSetupPopResult?>(
      MaterialPageRoute(
        builder: (ctx) => CatalogDomainSetupScreen(
          lojaId: loja,
          dominioInformado: norm,
          statusInicial: _dominioCatalogoStatus,
          dominioProviderAtual: _dominioProviderId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result.status != null && result.status!.trim().isNotEmpty) {
        _dominioCatalogoStatus = result.status!.trim();
      }
      final p = result.dominioProvider?.trim();
      if (p != null && p.isNotEmpty) {
        _dominioProviderId = p;
      }
    });
    await _salvarRascunho(validar: false);
  }

  // ✅ Agenda auto-save com debounce de 2 segundos (sem validação - só ao clicar Salvar/Publicar)
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_carregando) {
        logD('💾 [AUTO-SAVE] Salvando alterações automaticamente...');
        _salvarRascunho(validar: false);
      }
    });
  }

  /// Usado por [_PaneIdentidadeWidget]: [setState] deve ficar no State (não em StatelessWidget).
  void _setStateIfSlugEmptyFromNome() {
    if (_slugCtrl.text.trim().isEmpty) {
      final autoSlug = _nomeCtrl.text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      setState(() => _slugCtrl.text = autoSlug);
    }
  }

  /// Rebuild leve (helper text / campos sanitizados) — painel identidade em `part`.
  void _setStateIdentidadeHelperRebuild() {
    setState(() {});
  }

  /// Tabs Desktop/Mobile no painel mídias — `part`.
  void _setMediaTab(_MediaTab tab) {
    setState(() => _mediaTab = tab);
  }

  void _onHubSearchChanged() => setState(() {});

  void _clearHubSearch() {
    _hubSearchCtrl.clear();
    setState(() {});
  }

  void _setHubModuleFilterIfChanged(_HubModuleFilter value) {
    if (_hubModuleFilter != value) setState(() => _hubModuleFilter = value);
  }

  /// Painel Layout — acordeão (`loja_config_part_pane_wrappers.dart`).
  void _toggleLayoutAccordion(String id) {
    setState(() {
      if (_layoutPaneAccordionOpenId == id) {
        _layoutPaneAccordionOpenId = null;
      } else {
        _layoutPaneAccordionOpenId = id;
      }
    });
  }

  /// Pull-to-refresh na vista de módulo (fora do hub).
  Future<void> _refreshModuleConfigFromPull() async {
    setState(() => _erroCarregamento = false);
    await _verificarConectividade();
    await _initConfig();
  }

  // --- Pane Menu & páginas: switches/dropdown (setState em [_PaneMenuWidget]) ---
  void _menuSetShowCategorias(bool v) {
    setState(() => _menuShowCategorias = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetShowEntrar(bool v) {
    setState(() => _menuShowEntrar = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetShowContato(bool v) {
    setState(() => _menuShowContato = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetShowSac(bool v) {
    setState(() => _menuShowSac = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetShowQuemSomos(bool v) {
    setState(() => _menuShowQuemSomos = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetShowDicas(bool v) {
    setState(() => _menuShowDicas = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetExibirAvaliacoesCatalogo(bool v) {
    setState(() => _exibirAvaliacoesCatalogo = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetCatalogAvaliacoesOrdem(CatalogAvaliacoesOrdem v) {
    setState(() => _catalogAvaliacoesOrdem = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetShowMobileMenuGrid(bool v) {
    setState(() => _showMobileMenuGrid = v);
    _salvarRascunho(validar: false);
  }

  void _menuSetSobreLojaMostrarLegais(bool v) {
    setState(() => _sobreLojaMostrarLegais = v);
    _salvarRascunho(validar: false);
  }

  /// Painel Rodapé — bandeiras de pagamento (`loja_config_part_pane_rodape.dart`).
  void _rodapeOnPaymentChanged(String p, bool? v) {
    setState(() {
      if (v == true) {
        _payments.add(p);
      } else {
        _payments.remove(p);
      }
    });
    _salvarRascunho(validar: false);
  }

  bool _isHttpUrlLeve(String raw) {
    final s = raw.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  Widget _buildSobreLojaPreview(BuildContext context) {
    final theme = Theme.of(context);
    final previewListenables = Listenable.merge([
      _sobreLojaTituloCtrl,
      _sobreLojaSubtituloCtrl,
      _sobreLojaBannerUrlCtrl,
      _sobreLojaIntroCtrl,
      _sobreLojaDestaquesCtrl,
    ]);

    return AnimatedBuilder(
      animation: previewListenables,
      builder: (context, _) {
        final titulo = _sobreLojaTituloCtrl.text.trim().isEmpty
            ? 'Sobre a loja'
            : _sobreLojaTituloCtrl.text.trim();
        final subtitulo = _sobreLojaSubtituloCtrl.text.trim();
        final intro = _sobreLojaIntroCtrl.text.trim();
        final resumoIntro = intro.isEmpty
            ? 'Escreva um texto de apresentação para mostrar história, diferenciais e propósito da sua marca.'
            : intro;
        final chips = _sobreLojaDestaquesCtrl.text
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(4)
            .toList();
        final bannerUrl = _sobreLojaBannerUrlCtrl.text.trim();
        final hasBanner = _isHttpUrlLeve(bannerUrl);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.7),
            ),
            color: theme.colorScheme.surfaceContainerLowest,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 128,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasBanner)
                      Image(
                        image: mpImageProvider(bannerUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildSobreLojaPreviewPlaceholder(theme),
                      )
                    else
                      _buildSobreLojaPreviewPlaceholder(theme),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.10),
                            Colors.black.withOpacity(0.52),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          shadows: [
                            Shadow(color: Colors.black45, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitulo.isNotEmpty)
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (subtitulo.isNotEmpty) const SizedBox(height: 8),
                    Text(
                      resumoIntro,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: chips
                            .map(
                              (c) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.1),
                                ),
                                child: Text(
                                  c,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSobreLojaPreviewPlaceholder(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withOpacity(0.18),
            primary.withOpacity(0.07),
            theme.colorScheme.secondary.withOpacity(0.08),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -16,
            right: -12,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 74,
              color: primary.withOpacity(0.16),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Text(
              'Banner da loja',
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white.withOpacity(0.94),
                fontWeight: FontWeight.w700,
                shadows: const [
                  Shadow(color: Colors.black45, blurRadius: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initConfig() async {
    if (_initConfigInFlight != null) {
      if (kDebugMode) logD('[LOJA_CONFIG_LOAD_ONCE] coalescing with in-flight init');
      return _initConfigInFlight!;
    }
    final f = _runInitConfig();
    _initConfigInFlight = f;
    try {
      await f;
    } finally {
      _initConfigInFlight = null;
    }
  }

  Future<void> _runInitConfig() async {
    try {
      // 1) Descobre lojaId/slug usando StoreContext (FONTE ÚNICA)
      final id = await StoreResolverFacade.resolveForAdminApp();
      logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      logD('🏪 [LOJA CONFIG] StoreResolverFacade.resolveForAdminApp() = $id');
      if (kDebugMode) logD('[LOJA_CONFIG_RESOLVE_ONCE] resolve concluído (carga inicial / refresh)');

      // Mostra todas as fontes de loja
      final sessao = Hive.isBoxOpen('sessao') ? Hive.box('sessao') : null;
      final config = Hive.isBoxOpen('config') ? Hive.box('config') : null;
      logD('   sessao.store_id = ${sessao?.get('store_id')}');
      logD('   config.store_id = ${config?.get('store_id')}');
      logD('   FirebaseAuth.uid = ${FirebaseAuth.instance.currentUser?.uid}');
      logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      if (id == null || id.trim().isEmpty) {
        logD('❌ [LOJA CONFIG] Nenhuma loja ativa');
        if (mounted) {
          _snack(
              'Nenhuma loja ativa. Faça login novamente (admin/vendedor) para carregar a loja.',
              isError: true);
          Navigator.of(context).maybePop();
        }
        return;
      }

      setState(() {
        _lojaId = id.trim();
        _slug = _lojaId;
        _resolvedLojaId = _lojaId;
      });

      logD('✅ [LOJA CONFIG] Loja resolvida: $_lojaId');

      // 2) Abre box Hive local
      _configBox = await Hive.openBox(HiveBoxNames.lojaConfig(_lojaId!));

      // 3) ✅ SEMPRE carrega do Firestore PRIMEIRO (fonte da verdade)
      // Isso garante que logo e banner não sejam perdidos após flutter run
      logD('📥 [LOJA CONFIG] Carregando configuração do Firestore...');
      await _loadFromFirestore();
      await _loadKnownCategoryNamesFromStore();

      // 3.1) Carrega status de campanhas e roleta
      await _carregarStatusCampanhasERoleta();

      // 4) Fallback Hive: se mídia vazia, carregar rascunho completo do Hive
      if (_isMidiaVazia()) {
        logD('⚠️ [LOJA CONFIG] Mídia vazia, tentando rascunho local do Hive...');
        final local = _configBox.get('draft_config');
        if (local is Map) {
          _applyConfigMap(Map<String, dynamic>.from(local));
          logD('✅ [LOJA CONFIG] Mídia aplicada do Hive');
        }
      }
      // 5) Complementar do Hive: sempre preenche campos vazios (null ou "") com dados locais
      final local = _configBox.get('draft_config');
      if (local is Map) {
        final lm = Map<String, dynamic>.from(local);
        final ld = (lm['media']?['desktop'] ?? lm) as Map?;
        final lmobile = (lm['media']?['mobile'] ?? lm) as Map?;
        final localLogoD = (ld?['logoUrl'] ?? lm['logoDesktopUrl'])?.toString().trim();
        final localLogoM = (lmobile?['logoUrl'] ?? lm['logoMobileUrl'])?.toString().trim();
        final bdRaw = ld?['banners'] ?? lm['bannersDesktop'];
        final bmRaw = lmobile?['banners'] ?? lm['bannersMobile'];
        final localBannersD = (bdRaw is List) ? bdRaw.map((e) => e.toString()).toList() : <String>[];
        final localBannersM = (bmRaw is List) ? bmRaw.map((e) => e.toString()).toList() : <String>[];
        final precisaLogoD = (_logoUrlDesktop ?? '').trim().isEmpty && (localLogoD ?? '').isNotEmpty;
        final precisaLogoM = (_logoUrlMobile ?? '').trim().isEmpty && (localLogoM ?? '').isNotEmpty;
        final precisaBd = _bannersDesktop.isEmpty && localBannersD.isNotEmpty;
        final precisaBm = _bannersMobile.isEmpty && localBannersM.isNotEmpty;
        if (precisaLogoD || precisaLogoM || precisaBd || precisaBm) {
          logD('📥 [LOJA CONFIG] Complementando mídia com dados locais do Hive');
          setState(() {
            if (precisaLogoD && localLogoD != null) _logoUrlDesktop = localLogoD;
            if (precisaLogoM && localLogoM != null) _logoUrlMobile = localLogoM;
            if (precisaBd) _bannersDesktop = localBannersD;
            if (precisaBm) _bannersMobile = localBannersM;
          });
        }
      }
    } catch (e, stack) {
      logD('❌ Erro ao carregar config loja (type=${e.runtimeType})');
      logD('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _erroCarregamento = true;
          _mensagemErro = e.toString().replaceAll('Exception:', '').trim();
          if (_mensagemErro.length > 80) _mensagemErro = '${_mensagemErro.substring(0, 80)}...';
        });
        _showModernSnackBar('Erro ao carregar: ${e.toString().split('\n').first}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
        _verificarTutorialPrimeiraVez();
      }
      if (mounted && !_erroCarregamento && _resolvedLojaId != null) {
        _captureHubBaseline();
      }
    }
  }

  static const _tutorialPassos = [
    ('Identidade & Contato', 'Nome da loja, WhatsApp e configurações básicas de contato.', Icons.storefront_outlined),
    ('Mídias & Banners', 'Logo e banners para desktop e mobile. Envie imagens para personalizar seu catálogo.', Icons.photo_library_outlined),
    ('Tema & Cores', 'Defina as cores do catálogo, botões e fundo para combinar com sua marca.', Icons.palette_outlined),
    ('Layout dos cards', 'Colunas, sombras e bordas dos cards de produto no catálogo.', Icons.dashboard_customize_outlined),
    ('Menu & Páginas', 'Configure quais itens aparecem no menu: categorias, entrar, contato, SAC, Quem somos.', Icons.menu_open_outlined),
    ('Dicas e informações', 'Cuidados, garantias e qualidade – página linkada no menu do catálogo.', Icons.lightbulb_outline),
    ('Rodapé & Links', 'Redes sociais, políticas de troca, sobre a loja e informações legais.', Icons.view_day_outlined),
    ('Taxas Financeiras', 'Configure taxas usadas em relatórios e metas financeiras.', Icons.percent_outlined),
    ('Fretes & Cupons', 'Abra a tela dedicada para fretes e cupons de desconto.', Icons.local_shipping_outlined),
    ('Publicar catálogo', 'Depois de configurar tudo, clique aqui para publicar e tornar seu catálogo visível online.', Icons.cloud_upload_outlined),
  ];

  Future<void> _verificarTutorialPrimeiraVez() async {
    if (_carregando || !mounted) return;
    try {
      final cfg = Hive.isBoxOpen('config') ? Hive.box('config') : await Hive.openBox('config');
      final visto = cfg.get('tutorial_loja_config_visto') == true;
      if (!visto && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _mostrarTutorial = true);
        });
      }
    } catch (_) {}
  }

  Future<void> _fecharTutorial() async {
    setState(() {
      _mostrarTutorial = false;
      _tutorialPasso = 0;
    });
    try {
      final cfg = Hive.isBoxOpen('config') ? Hive.box('config') : await Hive.openBox('config');
      await cfg.put('tutorial_loja_config_visto', true);
    } catch (_) {}
  }

  Future<void> _verificarConectividade() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final online = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
      if (mounted) setState(() => _offline = !online);
    } catch (_) {}
  }

  Future<void> _retryCarregar() async {
    setState(() {
      _carregando = true;
      _erroCarregamento = false;
      _mensagemErro = '';
    });
    await _initConfig();
  }

  /// Carrega o status das campanhas e roleta do Firestore
  Future<void> _carregarStatusCampanhasERoleta() async {
    if (_resolvedLojaId == null) return;

    try {
      final lojaId = _resolvedLojaId!;
      if (kDebugMode) logD('[LOJA_CONFIG_CAMPANHAS_ONCE] buscando campanhas/roleta (init ou refresh)');
      logD('🎰 [CONFIG] Carregando status de campanhas e roleta para: $lojaId');

      // 1. Buscar campanhas ativas (limit para reduzir custo; suficiente para achar uma ativa)
      final campanhasSnap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('campanhas_sorteio')
          .limit(50)
          .get();

      final now = DateTime.now();
      Map<String, dynamic>? campanhaAtiva;

      for (final doc in campanhasSnap.docs) {
        final data = doc.data();
        final isAtiva = data['ativa'] == true ||
            data['status'] == 'aberta' ||
            data['status'] == 'ativa';

        if (!isAtiva) continue;

        final dataInicio = (data['dataInicio'] as Timestamp?)?.toDate();
        final dataFim = (data['dataFim'] as Timestamp?)?.toDate();

        final dentroDoInicio = dataInicio == null ||
            dataInicio.isBefore(now) ||
            dataInicio.isAtSameMomentAs(now);
        final dentroDoFim = dataFim == null || dataFim.isAfter(now);

        if (dentroDoInicio && dentroDoFim) {
          campanhaAtiva = {'id': doc.id, ...data};
          break;
        }
      }

      // 2. Buscar config da roleta
      final roletaDoc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('roleta_sorte')
          .get();

      final roletaAtiva = roletaDoc.exists && roletaDoc.data()?['ativa'] == true;

      if (mounted) {
        setState(() {
          _campanhaAtiva = campanhaAtiva != null;
          _campanhaAtivaId = campanhaAtiva?['id'];
          _campanhaAtivaNome = campanhaAtiva?['nome'] ?? campanhaAtiva?['titulo'];
          _roletaAtiva = roletaAtiva;
        });

        logD('✅ [CONFIG] Campanha ativa: $_campanhaAtiva ($_campanhaAtivaNome)');
        logD('✅ [CONFIG] Roleta ativa: $_roletaAtiva');
      }
    } catch (e) {
      logD('⚠️ [CONFIG] Erro ao carregar status de campanhas/roleta (type=${e.runtimeType})');
    }
  }

  /// Toggle para ativar/desativar campanha
  Future<void> _toggleCampanhaAtiva(bool novoValor) async {
    if (_campanhaAtivaId == null && novoValor) {
      _snack('Nenhuma campanha cadastrada. Crie uma campanha primeiro na seção de Sorteios.');
      return;
    }

    if (_campanhaAtivaId == null) return;

    try {
      setState(() => _salvando = true);

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(_resolvedLojaId)
          .collection('campanhas_sorteio')
          .doc(_campanhaAtivaId)
          .update({
        'ativa': novoValor,
        'status': novoValor ? 'aberta' : 'pausada',
      });

      setState(() {
        _campanhaAtiva = novoValor;
      });

      _captureHubBaseline();
      _snack(novoValor
          ? '✅ Campanha ativada! O banner aparecerá no catálogo.'
          : '⏸️ Campanha desativada.');
    } catch (e) {
      _snack('Erro ao atualizar campanha: $e', isError: true);
    } finally {
      setState(() => _salvando = false);
    }
  }

  /// Toggle para ativar/desativar roleta
  Future<void> _toggleRoletaAtiva(bool novoValor) async {
    try {
      setState(() => _salvando = true);

      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(_resolvedLojaId)
          .collection('config')
          .doc('roleta_sorte')
          .set({
        'ativa': novoValor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _roletaAtiva = novoValor;
      });

      _captureHubBaseline();
      _snack(novoValor
          ? '✅ Roleta ativada! Clientes poderão girar após compras.'
          : '⏸️ Roleta desativada.');
    } catch (e) {
      _snack('Erro ao atualizar roleta: $e', isError: true);
    } finally {
      setState(() => _salvando = false);
    }
  }

  int _parseIntCtrl(TextEditingController c, int fallback) {
    final v = int.tryParse(c.text.trim());
    return v ?? fallback;
  }

  double _parseDoubleCtrl(TextEditingController c, double fallback) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v ?? fallback;
  }

  int? _intFrom(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<void> _loadFromFirestore() async {
    if (_slug == null) return;

    logD('🔍 [FIRESTORE] Buscando config em: lojas/$_slug/draft_config/config');

    try {
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(_slug)
          .collection('draft_config')
          .doc('config')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        logD('✅ [FIRESTORE] draft_config encontrado! Aplicando...');
        if (kDebugMode) logD('[LOJA_CONFIG_FIRESTORE_ONCE] draft_config aplicado (carga inicial / refresh)');
        final converted = Map<String, dynamic>.from(data);
        _applyConfigMap(converted);
        _mergeFreteConfigCache = data['frete_config'];
        _mergeCuponsCache = data['cupons'];
      } else {
        logD('⚠️ [FIRESTORE] draft_config não encontrado');
        _mergeFreteConfigCache = null;
        _mergeCuponsCache = null;
      }

      // Doc da loja: pré-preenche nome/WhatsApp (cadastro inicial) e fallback de mídia
      final lojaDoc = await FirebaseFirestore.instance.collection('lojas').doc(_slug).get();
      if (lojaDoc.exists && lojaDoc.data() != null) {
        final d = lojaDoc.data()!;
        // Pré-preenche nome e WhatsApp quando vazios (ex.: primeiro acesso após onboarding)
        final nomeLoja = (d['name'] ?? d['nome'] ?? d['nomeLoja'] ?? '').toString().trim();
        final whatsE164 = (d['whatsappE164'] ?? d['whatsapp'] ?? '').toString().trim();
        if (nomeLoja.isNotEmpty && _nomeCtrl.text.trim().isEmpty) {
          setState(() => _nomeCtrl.text = nomeLoja);
          logD('📝 [LOJA CONFIG] Nome da loja pré-preenchido com: $nomeLoja');
        }
        if (whatsE164.isNotEmpty && _waCtrl.text.trim().isEmpty) {
          setState(() => _waCtrl.text = _extrairApenasDigitos(whatsE164));
          logD('📝 [LOJA CONFIG] WhatsApp pré-preenchido');
        }
      }

      // Fallback: se mídia vazia, usar doc da loja já carregado (config publicado)
      if (_isMidiaVazia() && lojaDoc.exists && lojaDoc.data() != null) {
        logD('📥 [FIRESTORE] Mídia vazia, tentando loja doc (config publicado)...');
        final d = lojaDoc.data()!;
          final media = d['media'] as Map<String, dynamic>?;
          final desktop = media?['desktop'] as Map?;
          final mobile = media?['mobile'] as Map?;
          final logoD = (desktop?['logoUrl'] ?? d['logoDesktopUrl'])?.toString();
          final logoM = (mobile?['logoUrl'] ?? d['logoMobileUrl'])?.toString();
          final bd = (desktop?['banners'] ?? d['bannersDesktop']) as List?;
          final bm = (mobile?['banners'] ?? d['bannersMobile']) as List?;
          if ((logoD != null && logoD.isNotEmpty) || (logoM != null && logoM.isNotEmpty) ||
              (bd != null && bd.isNotEmpty) || (bm != null && bm.isNotEmpty)) {
            setState(() {
              if ((_logoUrlDesktop == null || _logoUrlDesktop!.isEmpty) && logoD != null && logoD.isNotEmpty) _logoUrlDesktop = logoD;
              if ((_logoUrlMobile == null || _logoUrlMobile!.isEmpty) && logoM != null && logoM.isNotEmpty) _logoUrlMobile = logoM;
              if (_bannersDesktop.isEmpty && bd != null && bd.isNotEmpty) _bannersDesktop = bd.map((e) => e.toString()).toList();
              if (_bannersMobile.isEmpty && bm != null && bm.isNotEmpty) _bannersMobile = bm.map((e) => e.toString()).toList();
            });
            logD('✅ [FIRESTORE] Mídia carregada do config publicado');
          }
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logD('⚠️ [FIRESTORE] Sem permissão - usando dados locais');
      } else {
        logD('❌ [FIRESTORE] Erro ao carregar (type=${e.runtimeType})');
      }
    } catch (e) {
      logD('❌ [FIRESTORE] Erro inesperado (type=${e.runtimeType})');
    }
  }

  bool _isMidiaVazia() {
    final logoD = (_logoUrlDesktop ?? '').trim().isEmpty;
    final logoM = (_logoUrlMobile ?? '').trim().isEmpty;
    return logoD && logoM && _bannersDesktop.isEmpty && _bannersMobile.isEmpty;
  }

  /// Converte valor do Firestore para String (aceita String ou num, evita campo WhatsApp vazio quando salvo como número).
  static String? _stringFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is num) return v.toString();
    return v.toString();
  }

  void _applyConfigMap(Map<String, dynamic> data) {
    setState(() {
      _nomeCtrl.text = (data['nome'] as String?) ?? _nomeCtrl.text;
      _slugCtrl.text = (data['slug'] as String?) ?? _slugCtrl.text; // ✅ CARREGAR SLUG
    _linkCurtoCtrl.text = (data['linkCurto'] as String?) ?? _linkCurtoCtrl.text; // ✅ CARREGAR LINK CURTO
      _subdominioMascaraCtrl.text = (data['subdominioMascara'] ?? data['subdominio_mascara'] ?? '').toString().trim();
      _subdominioDominioBaseCtrl.text = (data['subdominioDominioBase'] ?? data['subdominio_dominio_base'] ?? 'mastepalm.com.br').toString().trim();
      _dominioCatalogoCtrl.text = (data['dominioCatalogo'] ?? '').toString().trim();
      final domProv = (data['dominioProvider'] ?? '').toString().trim();
      _dominioProviderId = domProv.isEmpty ? null : domProv;
      _dominioCatalogoStatus = dominioStatusFromStorage(
        (data['dominioStatus'] ?? '').toString(),
        hasDomain: _dominioCatalogoCtrl.text.isNotEmpty,
      );
      _dominioCatalogoUpdatedAt = (data['dominioUpdatedAt'] as num?)?.toInt();
      final waRaw = _stringFromDynamic(data['whatsapp']);
      _waCtrl.text = waRaw == null ? _waCtrl.text : (waRaw.trim().isEmpty ? '' : _extrairApenasDigitos(waRaw));
      _pedidoBaseCtrl.text =
          (data['pedidoBaseUrl'] as String?) ?? _pedidoBaseCtrl.text;

      // mídia - prioriza nova estrutura media.desktop/mobile, senão usa legado
      final mediaRaw = data['media'];
      final Map<String, dynamic> mediaData = mediaRaw is Map
          ? Map<String, dynamic>.from(mediaRaw)
          : {};
      final desktopMediaRaw = mediaData['desktop'];
      final Map<String, dynamic> desktopMedia = desktopMediaRaw is Map
          ? Map<String, dynamic>.from(desktopMediaRaw)
          : {};
      final mobileMediaRaw = mediaData['mobile'];
      final Map<String, dynamic> mobileMedia = mobileMediaRaw is Map
          ? Map<String, dynamic>.from(mobileMediaRaw)
          : {};

      _logoUrlDesktop = (desktopMedia['logoUrl'] as String?) ??
                        (data['logoDesktopUrl'] as String?);
      _logoUrlMobile = (mobileMedia['logoUrl'] as String?) ??
                       (data['logoMobileUrl'] as String?);

      _bannersDesktop = (desktopMedia['banners'] as List?)?.map((e) => e.toString()).toList() ??
                        (data['bannersDesktop'] as List?)?.map((e) => e.toString()).toList() ??
                        [];
      _bannersMobile = (mobileMedia['banners'] as List?)?.map((e) => e.toString()).toList() ??
                       (data['bannersMobile'] as List?)?.map((e) => e.toString()).toList() ??
                       [];

      // dimensões logo/banners - prioriza nova estrutura
      _dLogoH.text = (_intFrom(desktopMedia['logoH']) ??
                      _intFrom(data['dLogoH']) ??
                      int.tryParse(_dLogoH.text) ?? 105).toString();
      _dLogoW.text = (_intFrom(desktopMedia['logoW']) ??
                      _intFrom(data['dLogoW']) ??
                      int.tryParse(_dLogoW.text) ?? 327).toString();
      _mLogoH.text = (_intFrom(mobileMedia['logoH']) ??
                      _intFrom(data['mLogoH']) ??
                      int.tryParse(_mLogoH.text) ?? 105).toString();
      _mLogoW.text = (_intFrom(mobileMedia['logoW']) ??
                      _intFrom(data['mLogoW']) ??
                      int.tryParse(_mLogoW.text) ?? 327).toString();

      _dBanH.text = (_intFrom(desktopMedia['bannerH']) ??
                     _intFrom(data['dBanH']) ??
                     int.tryParse(_dBanH.text) ?? 256).toString();
      _dBanW.text = (_intFrom(desktopMedia['bannerW']) ??
                     _intFrom(data['dBanW']) ??
                     int.tryParse(_dBanW.text) ?? 1280).toString();
      _mBanH.text = (_intFrom(mobileMedia['bannerH']) ??
                     _intFrom(data['mBanH']) ??
                     int.tryParse(_mBanH.text) ?? 300).toString();
      _mBanW.text = (_intFrom(mobileMedia['bannerW']) ??
                     _intFrom(data['mBanW']) ??
                     int.tryParse(_mBanW.text) ?? 562).toString();

      // ✅ CORRIGIDO: Lê de 'theme' (mesma estrutura do public_catalog)
      final themeRaw = data['theme'];
      final Map<String, dynamic> theme = themeRaw is Map
          ? Map<String, dynamic>.from(themeRaw)
          : {};

      // Função helper para converter cor (aceita int ou String hexadecimal)
      int? colorToInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is String) {
          final cleaned = v.replaceAll('#', '');
          return int.tryParse(cleaned, radix: 16);
        }
        return null;
      }

      if (theme.isNotEmpty) {
        final fundo = colorToInt(theme['fundo']);
        final card = colorToInt(theme['card']);
        final texto = colorToInt(theme['texto']);
        final prim = colorToInt(theme['primaria']);
        final botaoTxt = colorToInt(theme['botaoTexto']);
        final cabecalho = colorToInt(theme['cabecalho']);
        if (fundo != null) _cFundo = Color(fundo);
        if (card != null) _cCard = Color(card);
        if (texto != null) _cTexto = Color(texto);
        if (prim != null) _cPrimaria = Color(prim);
        if (botaoTxt != null) _cBotaoTexto = Color(botaoTxt);
        if (cabecalho != null) _cCabecalho = Color(cabecalho);
      }

      // ✅ CORRIGIDO: Lê de 'checkoutTheme' (mesma estrutura do public_catalog)
      final checkoutThemeRaw = data['checkoutTheme'];
      final Map<String, dynamic> checkoutTheme = checkoutThemeRaw is Map
          ? Map<String, dynamic>.from(checkoutThemeRaw)
          : {};

      final cCard = colorToInt(checkoutTheme['card']);
      final cCampo = colorToInt(checkoutTheme['campo']);
      final cTexto = colorToInt(checkoutTheme['texto']);
      final cLabel = colorToInt(checkoutTheme['label']);
      final cTotal = colorToInt(checkoutTheme['total']);

      if (cCard != null) _cCarrinhoCard = Color(cCard);
      if (cCampo != null) _cCarrinhoCampo = Color(cCampo);
      if (cTexto != null) _cCarrinhoTexto = Color(cTexto);
      if (cLabel != null) _cCarrinhoLabel = Color(cLabel);
      if (cTotal != null) _cCarrinhoTotal = Color(cTotal);

      // ✅ NOVO: Carrega uiColors (cores unificadas expandidas)
      final uiColorsRaw = data['uiColors'];
      final Map<String, dynamic> uiColors = uiColorsRaw is Map
          ? Map<String, dynamic>.from(uiColorsRaw)
          : {};

      if (uiColors.isNotEmpty) {
        final textSecondary = colorToInt(uiColors['textSecondary']);
        final cardTextPrimary = colorToInt(uiColors['cardTextPrimary']);
        final cardTextSecondary = colorToInt(uiColors['cardTextSecondary']);
        final priceHighlight = colorToInt(uiColors['priceHighlight']);
        final danger = colorToInt(uiColors['danger']);
        final fieldHint = colorToInt(uiColors['fieldHint']);
        final fieldBorder = colorToInt(uiColors['fieldBorder']);
        final dividerColor = colorToInt(uiColors['dividerColor']);
        final buttonSecondaryBg = colorToInt(uiColors['buttonSecondaryBg']);
        final buttonSecondaryText = colorToInt(uiColors['buttonSecondaryText']);
        final buttonSecondaryBorder = colorToInt(uiColors['buttonSecondaryBorder']);
        final badgeBackground = colorToInt(uiColors['badgeBackground']);
        final badgeText = colorToInt(uiColors['badgeText']);
        final iconColor = colorToInt(uiColors['iconColor']);
        final shadowColor = colorToInt(uiColors['shadowColor']);

        if (textSecondary != null) _cTextSecondary = Color(textSecondary);
        if (cardTextPrimary != null) _cCardTextPrimary = Color(cardTextPrimary);
        if (cardTextSecondary != null) _cCardTextSecondary = Color(cardTextSecondary);
        if (priceHighlight != null) _cPriceHighlight = Color(priceHighlight);
        if (danger != null) _cDanger = Color(danger);
        if (fieldHint != null) _cFieldHint = Color(fieldHint);
        if (fieldBorder != null) _cFieldBorder = Color(fieldBorder);
        if (dividerColor != null) _cDivider = Color(dividerColor);
        if (buttonSecondaryBg != null) _cButtonSecondaryBg = Color(buttonSecondaryBg);
        if (buttonSecondaryText != null) _cButtonSecondaryText = Color(buttonSecondaryText);
        if (buttonSecondaryBorder != null) _cButtonSecondaryBorder = Color(buttonSecondaryBorder);
        if (badgeBackground != null) _cBadgeBackground = Color(badgeBackground);
        if (badgeText != null) _cBadgeText = Color(badgeText);
        if (iconColor != null) _cIcon = Color(iconColor);
        if (shadowColor != null) _cShadow = Color(shadowColor);
      }

      // ✅ NOVO: Carrega catalogHeaderColors (cores do cabeçalho)
      final headerColorsRaw = data['catalogHeaderColors'];
      final Map<String, dynamic> headerColors = headerColorsRaw is Map
          ? Map<String, dynamic>.from(headerColorsRaw)
          : {};

      if (headerColors.isNotEmpty) {
        final headerText = colorToInt(headerColors['text']);
        final headerIcon = colorToInt(headerColors['icon']);
        final searchBg = colorToInt(headerColors['searchBackground']);
        final searchText = colorToInt(headerColors['searchText']);
        final searchHint = colorToInt(headerColors['searchHint']);

        if (headerText != null) _cHeaderText = Color(headerText);
        if (headerIcon != null) _cHeaderIcon = Color(headerIcon);
        if (searchBg != null) _cHeaderSearchBg = Color(searchBg);
        if (searchText != null) _cHeaderSearchText = Color(searchText);
        if (searchHint != null) _cHeaderSearchHint = Color(searchHint);
      }

      // ✅ NOVO: Carrega catalogFooterColors (cores do rodapé)
      final footerColorsRaw = data['catalogFooterColors'];
      final Map<String, dynamic> footerColors = footerColorsRaw is Map
          ? Map<String, dynamic>.from(footerColorsRaw)
          : {};

      if (footerColors.isNotEmpty) {
        final footerBg = colorToInt(footerColors['background']);
        final footerText = colorToInt(footerColors['text']);
        final footerTextSecondary = colorToInt(footerColors['textSecondary']);
        final footerIcon = colorToInt(footerColors['icon']);
        final footerLink = colorToInt(footerColors['link']);
        final footerDivider = colorToInt(footerColors['divider']);

        if (footerBg != null) _cFooterBackground = Color(footerBg);
        if (footerText != null) _cFooterText = Color(footerText);
        if (footerTextSecondary != null) _cFooterTextSecondary = Color(footerTextSecondary);
        if (footerIcon != null) _cFooterIcon = Color(footerIcon);
        if (footerLink != null) _cFooterLink = Color(footerLink);
        if (footerDivider != null) _cFooterDivider = Color(footerDivider);
      }

      // ✅ NOVO: Carrega catalogDicasColors (cores da tela Dicas)
      final dicasColorsRaw = data['catalogDicasColors'];
      final Map<String, dynamic> dicasColors = dicasColorsRaw is Map
          ? Map<String, dynamic>.from(dicasColorsRaw)
          : {};

      if (dicasColors.isNotEmpty) {
        final dBg = colorToInt(dicasColors['background']);
        final dFooterBg = colorToInt(dicasColors['footerBackground']);
        final dFooterText = colorToInt(dicasColors['footerText']);
        final dBtnBg = colorToInt(dicasColors['buttonBackground']);
        final dBtnText = colorToInt(dicasColors['buttonText']);
        final dTopic = colorToInt(dicasColors['topicPrimary']);

        if (dBg != null) _cDicasBackground = Color(dBg);
        if (dFooterBg != null) _cDicasFooterBg = Color(dFooterBg);
        if (dFooterText != null) _cDicasFooterText = Color(dFooterText);
        if (dBtnBg != null) _cDicasButtonBg = Color(dBtnBg);
        if (dBtnText != null) _cDicasButtonText = Color(dBtnText);
        if (dTopic != null) _cDicasTopicPrimary = Color(dTopic);
      }

      // === LAYOUT ================================================
      _gridDesktopCols = (data['gridDesktopCols'] as int?) ?? _gridDesktopCols;
      _gridMobileCols = (data['gridMobileCols'] as int?) ?? _gridMobileCols;
      _cardShowShadow = (data['cardShowShadow'] as bool?) ?? _cardShowShadow;
      _cardBorderRadius =
          (data['cardBorderRadius'] as num?)?.toDouble() ?? _cardBorderRadius;
      _layoutCatalogo = CatalogLayoutConfig.normalize(
        data['layoutCatalogo'] ?? data['layout_catalogo'],
      );
      _productCardSize = (() {
        final v = (data['productCardSize'] ?? 'medium')
            .toString()
            .trim()
            .toLowerCase();
        if (v == 'small' || v == 'medium' || v == 'large') return v;
        return 'medium';
      })();

      final promoBarRaw = data['promoBar'];
      final promoBar = promoBarRaw is Map
          ? Map<String, dynamic>.from(promoBarRaw)
          : <String, dynamic>{};
      _promoBarEnabled = (promoBar['enabled'] as bool?) ?? _promoBarEnabled;
      _promoBarTextCtrl.text =
          (promoBar['text'] ?? _promoBarTextCtrl.text).toString();
      _promoBarLinkCtrl.text =
          (promoBar['link'] ?? _promoBarLinkCtrl.text).toString();
      final promoBg = colorToInt(promoBar['backgroundColor']);
      final promoText = colorToInt(promoBar['textColor']);
      if (promoBg != null) _promoBarBg = Color(promoBg);
      if (promoText != null) _promoBarText = Color(promoText);
      _promoBarMarquee = (promoBar['marquee'] as bool?) ?? _promoBarMarquee;

      final minimalSearchRaw = data['minimalSearch'];
      final minimalSearch = minimalSearchRaw is Map
          ? Map<String, dynamic>.from(minimalSearchRaw)
          : <String, dynamic>{};
      _minimalSearchPlaceholderCtrl.text =
          (minimalSearch['placeholder'] ?? _minimalSearchPlaceholderCtrl.text)
              .toString();

      final heroBannerRaw = data['heroBanner'];
      final heroBanner = heroBannerRaw is Map
          ? Map<String, dynamic>.from(heroBannerRaw)
          : <String, dynamic>{};
      _heroBannerEnabled = (heroBanner['enabled'] as bool?) ?? _heroBannerEnabled;
      _heroBannerTitleCtrl.text =
          (heroBanner['title'] ?? _heroBannerTitleCtrl.text).toString();
      _heroBannerSubtitleCtrl.text =
          (heroBanner['subtitle'] ?? _heroBannerSubtitleCtrl.text).toString();
      _heroBannerButtonTextCtrl.text =
          (heroBanner['buttonText'] ?? _heroBannerButtonTextCtrl.text).toString();
      _heroBannerButtonLinkCtrl.text =
          (heroBanner['buttonLink'] ?? _heroBannerButtonLinkCtrl.text).toString();
      _heroBannerImageCtrl.text =
          (heroBanner['image'] ?? _heroBannerImageCtrl.text).toString();
      _heroBannerMobileImageCtrl.text =
          (heroBanner['mobileImage'] ?? _heroBannerMobileImageCtrl.text).toString();

      int heroWeightFrom(dynamic v, int def) {
        if (v is int) return v.clamp(100, 900);
        if (v is num) return v.toInt().clamp(100, 900);
        final s = '$v'.toLowerCase();
        if (s.contains('bold') || s == 'w700' || s == '700') return 700;
        if (s == 'w800' || s == '800') return 800;
        if (s == 'w600' || s == '600') return 600;
        if (s == 'w500' || s == '500') return 500;
        if (s == 'w400' || s == '400') return 400;
        final p = int.tryParse(s);
        if (p != null && p >= 100 && p <= 900) return p;
        return def;
      }

      final heroCard = heroBanner['card'] is Map
          ? Map<String, dynamic>.from(heroBanner['card'] as Map)
          : <String, dynamic>{};
      final heroTitleStyle = heroBanner['titleStyle'] is Map
          ? Map<String, dynamic>.from(heroBanner['titleStyle'] as Map)
          : <String, dynamic>{};
      final heroSubtitleStyle = heroBanner['subtitleStyle'] is Map
          ? Map<String, dynamic>.from(heroBanner['subtitleStyle'] as Map)
          : <String, dynamic>{};
      final heroButtonStyle = heroBanner['buttonStyle'] is Map
          ? Map<String, dynamic>.from(heroBanner['buttonStyle'] as Map)
          : <String, dynamic>{};

      final hcBg =
          colorToInt(heroCard['backgroundColor']) ?? colorToInt(heroBanner['backgroundColor']);
      if (hcBg != null) {
        _heroCardBg = Color(hcBg);
      } else {
        _heroCardBg = _cCard;
      }
      final legacyText = colorToInt(heroBanner['textColor']);
      final tCol = colorToInt(heroTitleStyle['color']) ?? legacyText;
      if (tCol != null) _heroTitleColor = Color(tCol);
      final sCol = colorToInt(heroSubtitleStyle['color']);
      if (sCol != null) {
        _heroSubtitleColor = Color(sCol);
      } else if (tCol != null) {
        _heroSubtitleColor = Color(tCol).withOpacity(0.96);
      }
      final btnBg = colorToInt(heroButtonStyle['backgroundColor']) ??
          colorToInt(heroButtonStyle['background']) ??
          colorToInt(heroBanner['buttonColor']);
      if (btnBg != null) {
        _heroButtonBg = Color(btnBg);
      } else {
        _heroButtonBg = _cPrimaria;
      }
      final btnTx = colorToInt(heroButtonStyle['textColor']);
      if (btnTx != null) _heroButtonTextColor = Color(btnTx);

      if (heroBanner['height'] != null) {
        _heroBannerHeightCtrl.text = '${heroBanner['height']}';
      }
      final cr = heroCard['borderRadius'] ?? heroBanner['borderRadius'];
      if (cr != null) {
        _heroBannerCardRadiusCtrl.text = '$cr';
      }
      if (heroBanner['overlayOpacity'] != null) {
        _heroBannerOverlayCtrl.text = '${heroBanner['overlayOpacity']}';
      }
      if (heroTitleStyle['fontSize'] != null) {
        _heroBannerTitleSizeCtrl.text = '${heroTitleStyle['fontSize']}';
      }
      if (heroSubtitleStyle['fontSize'] != null) {
        _heroBannerSubtitleSizeCtrl.text = '${heroSubtitleStyle['fontSize']}';
      }
      if (heroButtonStyle['fontSize'] != null) {
        _heroBannerButtonSizeCtrl.text = '${heroButtonStyle['fontSize']}';
      }
      if (heroButtonStyle['borderRadius'] != null) {
        _heroBannerButtonRadiusCtrl.text = '${heroButtonStyle['borderRadius']}';
      }
      _heroTitleFontWeight =
          heroWeightFrom(heroTitleStyle['fontWeight'], _heroTitleFontWeight);
      _heroSubtitleFontWeight =
          heroWeightFrom(heroSubtitleStyle['fontWeight'], _heroSubtitleFontWeight);
      _heroButtonFontWeight =
          heroWeightFrom(heroButtonStyle['fontWeight'], _heroButtonFontWeight);
      _heroTitleCase =
          (heroTitleStyle['letterCase'] ?? 'none').toString().trim();
      if (_heroTitleCase.isEmpty) _heroTitleCase = 'none';
      _heroSubtitleCase =
          (heroSubtitleStyle['letterCase'] ?? 'none').toString().trim();
      if (_heroSubtitleCase.isEmpty) _heroSubtitleCase = 'none';
      _heroButtonCase =
          (heroButtonStyle['letterCase'] ?? 'none').toString().trim();
      if (_heroButtonCase.isEmpty) _heroButtonCase = 'none';

      final catVisualRaw = data['categoryVisuals'];
      final catVisual = catVisualRaw is Map
          ? Map<String, dynamic>.from(catVisualRaw)
          : <String, dynamic>{};
      final catImgsRaw = catVisual['images'];
      final catImgs = catImgsRaw is Map
          ? Map<String, dynamic>.from(catImgsRaw)
          : <String, dynamic>{};
      final catImgsByIdRaw = catVisual['imagesById'];
      final catImgsById = catImgsByIdRaw is Map
          ? Map<String, dynamic>.from(catImgsByIdRaw)
          : <String, dynamic>{};
      final catImgsByNormRaw = catVisual['imagesByNameNorm'];
      final catImgsByNorm = catImgsByNormRaw is Map
          ? Map<String, dynamic>.from(catImgsByNormRaw)
          : <String, dynamic>{};
      final mergedByName = <String, String>{};
      for (final e in catImgs.entries) {
        final k = e.key.toString().trim();
        final v = e.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          mergedByName[k] = v;
        }
      }
      for (final e in catImgsByNorm.entries) {
        final k = e.key.toString().trim();
        final v = e.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          mergedByName[k] = v;
          mergedByName['name:$k'] = v;
        }
      }
      final mergedById = <String, String>{};
      for (final e in catImgsById.entries) {
        final k = e.key.toString().trim();
        final v = e.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) mergedById[k] = v;
      }
      _categoryImagesByName = mergedByName;
      _categoryImagesById = mergedById;
      final known = <String>{..._knownCategoryNames};
      for (final k in mergedByName.keys) {
        if (k.startsWith('name:')) continue;
        if (k == _normalizeCategoryKey(k)) continue;
        known.add(k);
      }
      _knownCategoryNames = known.toList()..sort();
      _catImgModaCtrl.text = (catImgs['Moda'] ?? '').toString();
      _catImgCalcadosCtrl.text = (catImgs['Calcados'] ?? '').toString();
      _catImgBolsasCtrl.text = (catImgs['Bolsas'] ?? '').toString();

      final mbsRaw = data['minimalBestSellers'];
      final mbs = mbsRaw is Map
          ? Map<String, dynamic>.from(mbsRaw)
          : <String, dynamic>{};
      _minimalBestSellersEnabled =
          (mbs['enabled'] as bool?) ?? _minimalBestSellersEnabled;
      _minimalBestSellersTitleCtrl.text =
          (mbs['title'] ?? _minimalBestSellersTitleCtrl.text).toString();
      _minimalBestSellersCountCtrl.text =
          '${mbs['count'] ?? _minimalBestSellersCountCtrl.text}';

      final presetStr = data['layoutPreset'] as String?;
      if (presetStr != null) {
        _layoutPreset = _presetFromString(presetStr);
      }

      // === FRETES ================================================
      _freteProvider = (data['freteProvider'] as String?) ?? _freteProvider;

      _melhorEnvioTokenCtrl.text =
          (data['melhorEnvioToken'] as String?) ?? _melhorEnvioTokenCtrl.text;

      _correiosUserCtrl.text =
          (data['correiosUser'] as String?) ?? _correiosUserCtrl.text;

      _correiosSenhaCtrl.text =
          (data['correiosSenha'] as String?) ?? _correiosSenhaCtrl.text;

      _frenetTokenCtrl.text =
          (data['frenetToken'] as String?) ?? _frenetTokenCtrl.text;

      _fretes
        ..clear()
        ..addAll(((data['fretes'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)));

      // cupons
      _cupons
        ..clear()
        ..addAll(((data['cupons'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)));

      // menu
      final menuRaw = data['menu'];
      final Map<String, dynamic> menu = menuRaw is Map
          ? Map<String, dynamic>.from(menuRaw)
          : {};
      _menuShowCategorias =
          (menu['categorias'] as bool?) ?? _menuShowCategorias;
      _menuShowEntrar = (menu['entrar'] as bool?) ?? _menuShowEntrar;
      _menuShowContato = (menu['contato'] as bool?) ?? _menuShowContato;
      _menuShowSac = (menu['sac'] as bool?) ?? _menuShowSac;
      _menuShowQuemSomos =
          (menu['quemSomos'] as bool?) ?? _menuShowQuemSomos;
      _menuShowDicas = (menu['dicas'] as bool?) ?? _menuShowDicas;
      _exibirAvaliacoesCatalogo = (data['exibirAvaliacoesCatalogo'] as bool?) ??
          _exibirAvaliacoesCatalogo;
      _catalogAvaliacoesOrdem = CatalogAvaliacoesOrdem.fromFirestore(
        data['catalogAvaliacoesOrdem'],
      );
      _showMobileMenuGrid =
          (menu['mobileMenuGrid'] as bool?) ?? _showMobileMenuGrid;

      // dicas (lista de cuidados, garantias, qualidade etc.)
      final dicasRaw = data['dicas'];
      _dicas = [];
      if (dicasRaw is List) {
        for (final e in dicasRaw) {
          if (e is Map) {
            _dicas.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
          }
        }
      }

      // quem somos
      final quemRaw = data['quemSomos'];
      final Map<String, dynamic> quem = quemRaw is Map
          ? Map<String, dynamic>.from(quemRaw)
          : {};
      _quemSomosTituloCtrl.text =
          (quem['titulo'] as String?) ?? _quemSomosTituloCtrl.text;
      _quemSomosTextoCtrl.text =
          (quem['texto'] as String?) ?? _quemSomosTextoCtrl.text;

      // SAC
      final sacRaw = data['sac'];
      final Map<String, dynamic> sac = sacRaw is Map
          ? Map<String, dynamic>.from(sacRaw)
          : {};
      final sacWa = _stringFromDynamic(sac['whatsapp']);
      _sacWhatsappCtrl.text = sacWa == null ? _sacWhatsappCtrl.text : (sacWa.trim().isEmpty ? '' : _extrairApenasDigitos(sacWa));
      _sacEmailCtrl.text = (sac['email'] as String?) ?? _sacEmailCtrl.text;

      // ✅ CORRIGIDO: Lê de 'rodape' (fonte principal) com fallback em 'links' (retrocompatibilidade)
      final rodapeRaw = data['rodape'];
      final Map<String, dynamic> rodape = rodapeRaw is Map
          ? Map<String, dynamic>.from(rodapeRaw)
          : {};
      final linksRaw = data['links'];
      final Map<String, dynamic> links = linksRaw is Map
          ? Map<String, dynamic>.from(linksRaw)
          : {};
      _instagramCtrl.text =
          (rodape['instagram'] as String?) ?? (links['instagram'] as String?) ?? _instagramCtrl.text;
      _facebookCtrl.text =
          (rodape['facebook'] as String?) ?? (links['facebook'] as String?) ?? _facebookCtrl.text;
      _tiktokCtrl.text =
          (rodape['tiktok'] as String?) ?? _tiktokCtrl.text;
      _telegramCtrl.text =
          (rodape['telegram'] as String?) ?? _telegramCtrl.text;
      _kwaiCtrl.text =
          (rodape['kwai'] as String?) ?? _kwaiCtrl.text;
      _linkedinCtrl.text =
          (rodape['linkedin'] as String?) ?? _linkedinCtrl.text;
      _emailRodapeCtrl.text =
          (rodape['email'] as String?) ?? _emailRodapeCtrl.text;
      final rodapeWa = _stringFromDynamic(rodape['whatsapp']);
      _whatsappRodapeCtrl.text = rodapeWa == null ? _whatsappRodapeCtrl.text : (rodapeWa.trim().isEmpty ? '' : _extrairApenasDigitos(rodapeWa));
      _sobreCtrl.text = (rodape['sobre'] as String?) ?? (links['sobre'] as String?) ?? _sobreCtrl.text;
      final slRaw = data['sobreLojaCatalogo'];
      if (slRaw is Map) {
        final sl = Map<String, dynamic>.from(
            slRaw.map((k, v) => MapEntry(k.toString(), v)));
        _sobreLojaTituloCtrl.text =
            (sl['titulo'] as String?) ?? _sobreLojaTituloCtrl.text;
        _sobreLojaSubtituloCtrl.text =
            (sl['subtitulo'] as String?) ?? _sobreLojaSubtituloCtrl.text;
        _sobreLojaBannerUrlCtrl.text = (sl['bannerUrl'] as String?) ??
            (sl['banner_url'] as String?) ??
            _sobreLojaBannerUrlCtrl.text;
        _sobreLojaIntroCtrl.text =
            (sl['introducao'] as String?) ?? _sobreLojaIntroCtrl.text;
        _sobreLojaMissaoCtrl.text =
            (sl['missao'] as String?) ?? _sobreLojaMissaoCtrl.text;
        _sobreLojaVisaoCtrl.text =
            (sl['visao'] as String?) ?? _sobreLojaVisaoCtrl.text;
        _sobreLojaValoresCtrl.text =
            (sl['valores'] as String?) ?? _sobreLojaValoresCtrl.text;
        final destRaw = sl['destaques'];
        if (destRaw is List) {
          _sobreLojaDestaquesCtrl.text = destRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .join('\n');
        }
        _sobreLojaEnderecoCtrl.text =
            (sl['endereco'] as String?) ?? _sobreLojaEnderecoCtrl.text;
        _sobreLojaHorarioCtrl.text = (sl['horarioAtendimento'] as String?) ??
            (sl['horario'] as String?) ??
            _sobreLojaHorarioCtrl.text;
        _sobreLojaEmailCtrl.text = (sl['emailContato'] as String?) ??
            (sl['email'] as String?) ??
            _sobreLojaEmailCtrl.text;
        _sobreLojaMostrarLegais = sl['mostrarDadosLegais'] != false;
        final ext = (sl['linkExternoUrl'] ?? sl['linkExterno'] ?? '')
            .toString()
            .trim();
        if (ext.isNotEmpty) _sobreCtrl.text = ext;
      }
      _trocasCtrl.text = (rodape['trocas'] as String?) ?? (links['trocas'] as String?) ?? _trocasCtrl.text;
      _loginCtrl.text = (rodape['login'] as String?) ?? (links['login'] as String?) ?? _loginCtrl.text;
      _razaoCtrl.text = (rodape['razao'] as String?) ?? _razaoCtrl.text;
      _cnpjCtrl.text = (rodape['cnpj'] as String?) ?? _cnpjCtrl.text;

      _payments
        ..clear()
        ..addAll(
            ((rodape['payments'] as List?) ?? []).map((e) => e.toString()));

      // Taxas financeiras (Relatórios Financeiros e Financeiro & Metas)
      final taxasRaw = data['taxas'];
      if (taxasRaw is Map) {
        final taxas = Map<String, dynamic>.from(taxasRaw);
        _taxaCartaoCtrl.text = (_doubleFrom(taxas['cartao']) ?? 5.0).toString();
        _taxaMEICtrl.text = (_doubleFrom(taxas['mei']) ?? 3.5).toString();
        _custosFixosCtrl.text = (_doubleFrom(taxas['custosFixos']) ?? 10.0).toString();
        _custoEmbalagemCtrl.text = (_doubleFrom(taxas['embalagem']) ?? 3.0).toString();
      }
    });
    _scheduleSyncCatalogDomainListener();
  }

  double? _doubleFrom(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  String _normalizeCategoryKey(String raw) {
    final s = raw
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[àáâãä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll('ç', 'c');
    return s
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> _loadKnownCategoryNamesFromStore() async {
    final lojaId = _resolvedLojaId;
    if (lojaId == null || lojaId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(lojaId)
          .collection('produtos')
          .where('ativo', isEqualTo: true)
          .limit(1000)
          .get();
      final names = <String>{};
      for (final d in snap.docs) {
        final m = d.data();
        final c = (m['categoria'] ?? m['categoria_nome'] ?? '').toString().trim();
        if (c.isNotEmpty) names.add(c);
      }
      if (!mounted) return;
      setState(() {
        _knownCategoryNames = names.toList()..sort();
      });
    } catch (_) {
      // Catálogo segue funcionando; em erro, mantém fallback por digitação.
    }
  }

  void _upsertCategoryImageConfig() {
    final selected = _catSelectedFromStore?.trim() ?? '';
    final categoryName =
        selected.isNotEmpty ? selected : _catImgCategoriaCtrl.text.trim();
    final categoryId = _catImgCategoriaIdCtrl.text.trim();
    final imageUrl = _catImgUrlCtrl.text.trim();
    if (categoryName.isEmpty || imageUrl.isEmpty) return;

    final normalized = _normalizeCategoryKey(categoryName);
    _categoryImagesByName[categoryName] = imageUrl;
    _categoryImagesByName[normalized] = imageUrl;
    _categoryImagesByName['name:$normalized'] = imageUrl;
    if (categoryId.isNotEmpty) {
      _categoryImagesById[categoryId] = imageUrl;
    }

    if (!_knownCategoryNames.contains(categoryName)) {
      _knownCategoryNames = [..._knownCategoryNames, categoryName]..sort();
    }
  }

  // ✅ ESTRUTURA ALINHADA COM PUBLIC_CATALOG
  Map<String, dynamic> _buildConfigMap({required String storeId}) {
    // ✅ SLUG AMIGÁVEL: Se não tiver slug configurado, gera automaticamente do nome
    String slugFinal = _slugCtrl.text.trim();
    if (slugFinal.isEmpty) {
      slugFinal = _nomeCtrl.text.trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      if (slugFinal.isEmpty) slugFinal = storeId;
    }

    final pedidoBaseRaw = _pedidoBaseCtrl.text.trim();
    final pedidoBaseUrl = pedidoBaseRaw.isEmpty
        ? ''
        : (pedidoBaseRaw.contains('://') ? pedidoBaseRaw : 'https://$pedidoBaseRaw');

    final linkCurto = _linkCurtoCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    final subMascara = _subdominioMascaraCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final subDominio = _subdominioDominioBaseCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9.-]'), '');
    final domNorm = normalizeCatalogDomainInput(_dominioCatalogoCtrl.text);
    return {
      'slug': slugFinal, // ✅ SLUG AMIGÁVEL para URL pública
      if (linkCurto.isNotEmpty) 'linkCurto': linkCurto, // ✅ Link curto: app.mastepalm.com.br/c/{linkCurto}
      if (subMascara.isNotEmpty) 'subdominioMascara': subMascara,
      if (subMascara.isNotEmpty) 'subdominioDominioBase': subDominio.isNotEmpty ? subDominio : 'mastepalm.com.br',
      'dominioCatalogo': domNorm,
      'dominioStatus': dominioStatusForConfigMap(domNorm, _dominioCatalogoStatus),
      if (domNorm.isNotEmpty && _dominioCatalogoUpdatedAt != null)
        'dominioUpdatedAt': _dominioCatalogoUpdatedAt,
      if (domNorm.isEmpty)
        'dominioProvider': ''
      else if (_dominioProviderId != null && _dominioProviderId!.trim().isNotEmpty)
        'dominioProvider': _dominioProviderId!.trim(),
      'lojaId': storeId,
      'nome': _nomeCtrl.text.trim(),
      'whatsapp': () {
        final t = _waCtrl.text.trim();
        final digits = _extrairApenasDigitos(t);
        return digits.isNotEmpty ? digits : t;
      }(),
      'pedidoBaseUrl': pedidoBaseUrl,
      'layoutPreset':
          _layoutPreset != null ? _presetToString(_layoutPreset!) : null,
      
      // ✅ CORRIGIDO: Salva em 'theme' (igual ao que o public_catalog lê)
      // Salva como int (mais compatível e eficiente)
      'theme': {
        'fundo': _cFundo.value,
        'card': _cCard.value,
        'texto': _cTexto.value,
        'primaria': _cPrimaria.value,
        'botaoTexto': _cBotaoTexto.value,
        'cabecalho': _cCabecalho.value,
      },

      // ✅ CORRIGIDO: Salva em 'checkoutTheme' (igual ao que o public_catalog lê)
      'checkoutTheme': {
        'card': _cCarrinhoCard.value,
        'campo': _cCarrinhoCampo.value,
        'texto': _cCarrinhoTexto.value,
        'label': _cCarrinhoLabel.value,
        'total': _cCarrinhoTotal.value,
      },

      // ✅ NOVO: Cores unificadas do catálogo e checkout
      'uiColors': {
        'background': _cFundo.value,
        'cardBackground': _cCard.value,
        'textPrimary': _cTexto.value,
        'textSecondary': _cTextSecondary.value,
        'cardTextPrimary': _cCardTextPrimary.value,
        'cardTextSecondary': _cCardTextSecondary.value,
        'labelText': _cCarrinhoLabel.value,
        'priceHighlight': _cPriceHighlight.value,
        'danger': _cDanger.value,
        'fieldBackground': _cCarrinhoCampo.value,
        'fieldText': _cCarrinhoTexto.value,
        'fieldHint': _cFieldHint.value,
        'fieldBorder': _cFieldBorder.value,
        'dividerColor': _cDivider.value,
        'buttonPrimaryBg': _cPrimaria.value,
        'buttonPrimaryText': _cBotaoTexto.value,
        'buttonSecondaryBg': _cButtonSecondaryBg.value,
        'buttonSecondaryText': _cButtonSecondaryText.value,
        'buttonSecondaryBorder': _cButtonSecondaryBorder.value,
        'badgeBackground': _cBadgeBackground.value,
        'badgeText': _cBadgeText.value,
        'iconColor': _cIcon.value,
        'shadowColor': _cShadow.value,
      },

      // ✅ NOVO: Cores do cabeçalho do catálogo
      'catalogHeaderColors': {
        'background': _cCabecalho.value,
        'text': _cHeaderText.value,
        'icon': _cHeaderIcon.value,
        'searchBackground': _cHeaderSearchBg.value,
        'searchText': _cHeaderSearchText.value,
        'searchHint': _cHeaderSearchHint.value,
      },

      // ✅ NOVO: Cores do rodapé do catálogo
      'catalogFooterColors': {
        'background': _cFooterBackground.value,
        'text': _cFooterText.value,
        'textSecondary': _cFooterTextSecondary.value,
        'icon': _cFooterIcon.value,
        'link': _cFooterLink.value,
        'divider': _cFooterDivider.value,
      },

      // ✅ NOVO: Cores da tela Dicas e Informações
      'catalogDicasColors': {
        'background': _cDicasBackground.value,
        'footerBackground': _cDicasFooterBg.value,
        'footerText': _cDicasFooterText.value,
        'buttonBackground': _cDicasButtonBg.value,
        'buttonText': _cDicasButtonText.value,
        'topicPrimary': _cDicasTopicPrimary.value,
      },
      
      'gridDesktopCols': _gridDesktopCols,
      'gridMobileCols': _gridMobileCols,
      'cardShowShadow': _cardShowShadow,
      'cardBorderRadius': _cardBorderRadius,
      'layoutCatalogo': _layoutCatalogo,
      'productCardSize': _productCardSize,
      'promoBar': {
        'enabled': _promoBarEnabled,
        'text': _promoBarTextCtrl.text.trim(),
        'backgroundColor': _promoBarBg.value,
        'textColor': _promoBarText.value,
        'link': _promoBarLinkCtrl.text.trim(),
        'height': 34,
        'alignment': 'center',
        'bold': true,
        'marquee': _promoBarMarquee,
      },
      'minimalSearch': {
        'placeholder': _minimalSearchPlaceholderCtrl.text.trim().isEmpty
            ? 'O que você está procurando?'
            : _minimalSearchPlaceholderCtrl.text.trim(),
        'height': 44,
        'radius': 10,
        'background': Colors.white.value,
        'borderColor': const Color(0x1A000000).value,
      },
      'heroBanner': {
        'enabled': _heroBannerEnabled,
        'title': _heroBannerTitleCtrl.text.trim(),
        'subtitle': _heroBannerSubtitleCtrl.text.trim(),
        'buttonText': _heroBannerButtonTextCtrl.text.trim(),
        'buttonLink': _heroBannerButtonLinkCtrl.text.trim(),
        'image': _heroBannerImageCtrl.text.trim(),
        'mobileImage': _heroBannerMobileImageCtrl.text.trim(),
        'height': double.tryParse(
                _heroBannerHeightCtrl.text.replaceAll(',', '.')) ??
            180,
        'borderRadius': double.tryParse(
                _heroBannerCardRadiusCtrl.text.replaceAll(',', '.')) ??
            18,
        'overlayOpacity': double.tryParse(
                _heroBannerOverlayCtrl.text.replaceAll(',', '.')) ??
            0.16,
        'textColor': _heroTitleColor.value,
        'buttonColor': _heroButtonBg.value,
        'backgroundColor': _heroCardBg.value,
        'card': {
          'backgroundColor': _heroCardBg.value,
          'borderRadius': double.tryParse(
                  _heroBannerCardRadiusCtrl.text.replaceAll(',', '.')) ??
              18,
        },
        'titleStyle': {
          'color': _heroTitleColor.value,
          'fontSize': double.tryParse(
                  _heroBannerTitleSizeCtrl.text.replaceAll(',', '.')) ??
              17,
          'fontWeight': _heroTitleFontWeight,
          'letterCase': _heroTitleCase,
        },
        'subtitleStyle': {
          'color': _heroSubtitleColor.value,
          'fontSize': double.tryParse(
                  _heroBannerSubtitleSizeCtrl.text.replaceAll(',', '.')) ??
              13,
          'fontWeight': _heroSubtitleFontWeight,
          'letterCase': _heroSubtitleCase,
        },
        'buttonStyle': {
          'backgroundColor': _heroButtonBg.value,
          'textColor': _heroButtonTextColor.value,
          'fontSize': double.tryParse(
                  _heroBannerButtonSizeCtrl.text.replaceAll(',', '.')) ??
              13,
          'fontWeight': _heroButtonFontWeight,
          'borderRadius': double.tryParse(
                  _heroBannerButtonRadiusCtrl.text.replaceAll(',', '.')) ??
              8,
          'letterCase': _heroButtonCase,
        },
      },
      'categoryVisuals': {
        'showTitle': true,
        'shape': 'circle',
        'imageSize': 76,
        'spacing': 12,
        'images': {
          ..._categoryImagesByName,
          if (_catImgModaCtrl.text.trim().isNotEmpty)
            'Moda': _catImgModaCtrl.text.trim(),
          if (_catImgCalcadosCtrl.text.trim().isNotEmpty)
            'Calcados': _catImgCalcadosCtrl.text.trim(),
          if (_catImgBolsasCtrl.text.trim().isNotEmpty)
            'Bolsas': _catImgBolsasCtrl.text.trim(),
        },
        'imagesById': {
          ..._categoryImagesById,
        },
        'imagesByNameNorm': {
          for (final e in _categoryImagesByName.entries)
            if (!e.key.startsWith('name:'))
              _normalizeCategoryKey(e.key): e.value,
        },
      },
      'minimalProductGrid': {
        'aspectRatio': 0.56,
        'mainAxisSpacing': 16,
        'crossAxisSpacing': 12,
        'imageCacheWidth': 640,
        'imageCacheHeight': 860,
        'cardShowShadow': false,
        'cardBorderRadius': 16,
      },
      'minimalBestSellers': {
        'enabled': _minimalBestSellersEnabled,
        'title': _minimalBestSellersTitleCtrl.text.trim().isEmpty
            ? 'Mais vendidos'
            : _minimalBestSellersTitleCtrl.text.trim(),
        'count': int.tryParse(_minimalBestSellersCountCtrl.text.trim()) ?? 10,
      },

      // ✅ CORRIGIDO: Estrutura media.desktop / media.mobile (igual ao que o public_catalog lê)
      'media': {
        'desktop': {
          'logoUrl': _logoUrlDesktop,
          'banners': _bannersDesktop,
          'logoH': _parseIntCtrl(_dLogoH, 105),
          'logoW': _parseIntCtrl(_dLogoW, 327),
          'bannerH': _parseIntCtrl(_dBanH, 256),
          'bannerW': _parseIntCtrl(_dBanW, 1280),
        },
        'mobile': {
          'logoUrl': _logoUrlMobile,
          'banners': _bannersMobile,
          'logoH': _parseIntCtrl(_mLogoH, 105),
          'logoW': _parseIntCtrl(_mLogoW, 327),
          'bannerH': _parseIntCtrl(_mBanH, 300),
          'bannerW': _parseIntCtrl(_mBanW, 562),
        },
      },

      // ✅ COMPAT: Mantém campos legados para retrocompatibilidade
      'logoDesktopUrl': _logoUrlDesktop,
      'logoMobileUrl': _logoUrlMobile,
      'bannersDesktop': _bannersDesktop,
      'bannersMobile': _bannersMobile,
      'dLogoH': _parseIntCtrl(_dLogoH, 105),
      'dLogoW': _parseIntCtrl(_dLogoW, 327),
      'mLogoH': _parseIntCtrl(_mLogoH, 105),
      'mLogoW': _parseIntCtrl(_mLogoW, 327),
      'dBanH': _parseIntCtrl(_dBanH, 256),
      'dBanW': _parseIntCtrl(_dBanW, 1280),
      'mBanH': _parseIntCtrl(_mBanH, 300),
      'mBanW': _parseIntCtrl(_mBanW, 562),
      'freteProvider': _freteProvider,
      'melhorEnvioToken': _melhorEnvioTokenCtrl.text.trim(),
      'correiosUser': _correiosUserCtrl.text.trim(),
      'correiosSenha': _correiosSenhaCtrl.text.trim(),
      'frenetToken': _frenetTokenCtrl.text.trim(),
      'fretes': _fretes,
      'cupons': _cupons,
      'menu': {
        'categorias': _menuShowCategorias,
        'entrar': _menuShowEntrar,
        'contato': _menuShowContato,
        'sac': _menuShowSac,
        'quemSomos': _menuShowQuemSomos,
        'dicas': _menuShowDicas,
        'mobileMenuGrid': _showMobileMenuGrid,
      },
      'exibirAvaliacoesCatalogo': _exibirAvaliacoesCatalogo,
      'catalogAvaliacoesOrdem': _catalogAvaliacoesOrdem.firestoreValue,
      'dicas': _dicas,
      'quemSomos': {
        'titulo': _quemSomosTituloCtrl.text.trim(),
        'texto': _quemSomosTextoCtrl.text.trim(),
      },
      'sobreLojaCatalogo': {
        'titulo': _sobreLojaTituloCtrl.text.trim(),
        'subtitulo': _sobreLojaSubtituloCtrl.text.trim(),
        'bannerUrl': _sobreLojaBannerUrlCtrl.text.trim(),
        'introducao': _sobreLojaIntroCtrl.text.trim(),
        'missao': _sobreLojaMissaoCtrl.text.trim(),
        'visao': _sobreLojaVisaoCtrl.text.trim(),
        'valores': _sobreLojaValoresCtrl.text.trim(),
        'destaques': _sobreLojaDestaquesCtrl.text
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'endereco': _sobreLojaEnderecoCtrl.text.trim(),
        'horarioAtendimento': _sobreLojaHorarioCtrl.text.trim(),
        'emailContato': _sobreLojaEmailCtrl.text.trim(),
        'mostrarDadosLegais': _sobreLojaMostrarLegais,
        'linkExternoUrl': _sobreCtrl.text.trim(),
      },
      'sac': {
        'whatsapp': _sacWhatsappCtrl.text.trim(),
        'email': _sacEmailCtrl.text.trim(),
      },
      
      // ✅ CORRIGIDO: Salva payments em 'rodape' (igual ao que o public_catalog lê)
      'rodape': {
        'instagram': _instagramCtrl.text.trim(),
        'facebook': _facebookCtrl.text.trim(),
        'tiktok': _tiktokCtrl.text.trim(),
        'telegram': _telegramCtrl.text.trim(),
        'kwai': _kwaiCtrl.text.trim(),
        'linkedin': _linkedinCtrl.text.trim(),
        'email': _emailRodapeCtrl.text.trim(),
        'whatsapp': _whatsappRodapeCtrl.text.trim(),
        'sobre': _sobreCtrl.text.trim(),
        'trocas': _trocasCtrl.text.trim(),
        'login': _loginCtrl.text.trim(),
        'razao': _razaoCtrl.text.trim(),
        'cnpj': _cnpjCtrl.text.trim(),
        'payments': _payments,
      },
      // ✅ Sincronizado: 'links' espelha rodape para retrocompatibilidade (catálogo usa rodape com fallback em links)
      'links': {
        'instagram': _instagramCtrl.text.trim(),
        'facebook': _facebookCtrl.text.trim(),
        'sobre': _sobreCtrl.text.trim(),
        'trocas': _trocasCtrl.text.trim(),
        'login': _loginCtrl.text.trim(),
      },

      // Taxas usadas em Relatórios Financeiros e Financeiro & Metas (valores padrão; usuário pode alterar)
      'taxas': {
        'cartao': _parseDoubleCtrl(_taxaCartaoCtrl, 5.0),
        'mei': _parseDoubleCtrl(_taxaMEICtrl, 3.5),
        'custosFixos': _parseDoubleCtrl(_custosFixosCtrl, 10.0),
        'embalagem': _parseDoubleCtrl(_custoEmbalagemCtrl, 3.0),
      },
    };
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    _showModernSnackBar(msg, isError: isError);
  }

  /// Extrai apenas dígitos (0-9) do valor. Usado para normalizar WhatsApp.
  static String _extrairApenasDigitos(String? v) {
    if (v == null || v.isEmpty) return '';
    // Remove tudo que não seja dígito ASCII (evita unicode, espaços especiais, etc)
    return v.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Valida WhatsApp E.164: aceita 10 a 15 dígitos (Brasil: 55+DDD+número).
  /// Aceita formatação: 5511999999999, 55 11 99999-9999, +55 33 99994-5282, etc.
  bool _validarWhatsApp(String? v) {
    if (v == null || v.trim().isEmpty) return true;
    final nums = _extrairApenasDigitos(v.trim());
    return nums.length >= 10 && nums.length <= 15;
  }

  /// Valida URL (opcional - vazio é ok). Aceita URL sem esquema (ex: app.mastepalm.com.br/pedido).
  bool _validarUrl(String? v) {
    if (v == null || v.trim().isEmpty) return true;
    final s = v.trim();
    final toParse = s.contains('://') ? s : 'https://$s';
    final uri = Uri.tryParse(toParse);
    return uri != null && (uri.hasScheme && (uri.host.isNotEmpty || uri.hasAbsolutePath));
  }

  /// Valida e corrige dimensão (50-2000)
  void _corrigirDimensao(TextEditingController c, {int min = 50, int max = 2000}) {
    final v = int.tryParse(c.text.trim());
    if (v != null && (v < min || v > max)) {
      c.text = v.clamp(min, max).toString();
    }
  }

  /// Problemas que impedem salvar/publicar (fonte única para [_validarAntesDeSalvar] e indicadores do hub).
  List<({String campo, String msg})> _coletarProblemasSalvar() {
    final out = <({String campo, String msg})>[];
    if (!_validarWhatsApp(_waCtrl.text)) {
      out.add((
        campo: 'whatsapp',
        msg: 'WhatsApp do vendedor inválido. Use 10 a 15 dígitos (ex: 5533999998888).',
      ));
    }
    if (!_validarWhatsApp(_sacWhatsappCtrl.text)) {
      out.add((
        campo: 'sac_whatsapp',
        msg: 'WhatsApp do SAC inválido (se preenchido, use 10 a 15 dígitos).',
      ));
    }
    if (!_validarWhatsApp(_whatsappRodapeCtrl.text)) {
      out.add((
        campo: 'whatsapp_rodape',
        msg: 'WhatsApp do rodapé inválido (se preenchido, use 10 a 15 dígitos).',
      ));
    }
    if (!_validarUrl(_pedidoBaseCtrl.text)) {
      out.add((campo: 'pedido_base', msg: 'URL de pedido inválida.'));
    }
    return out;
  }

  /// Avisos de publicação quando [_coletarProblemasSalvar] está vazio (mesmas regras que [_validarAntesDePublicar]).
  List<String> _listaAvisosPublicarNomeLogo() {
    final avisos = <String>[];
    if (_nomeCtrl.text.trim().isEmpty) {
      avisos.add('Informe o nome da loja.');
    }
    if (_logoUrlDesktop == null && _logoUrlMobile == null) {
      avisos.add('Adicione pelo menos uma logo (desktop ou mobile).');
    }
    return avisos;
  }

  void _corrigirDimensoesMidiaForm() {
    for (final c in [_dLogoH, _dLogoW, _mLogoH, _mLogoW, _dBanH, _dBanW, _mBanH, _mBanW]) {
      _corrigirDimensao(c);
    }
  }

  /// Retorna lista de erros e set de campos com erro
  ({List<String> erros, Set<String> campos}) _validarAntesDeSalvar({bool incluirCampos = true}) {
    final items = _coletarProblemasSalvar();
    _corrigirDimensoesMidiaForm();
    return (
      erros: items.map((e) => e.msg).toList(),
      campos: incluirCampos ? items.map((e) => e.campo).toSet() : <String>{},
    );
  }

  void _limparErroCampo(String campo) {
    if (_camposComErro.remove(campo)) setState(() {});
  }

  /// Validação extra antes de publicar (requisitos mínimos)
  List<String>? _validarAntesDePublicar() {
    _corrigirDimensoesMidiaForm();
    final items = _coletarProblemasSalvar();
    if (items.isNotEmpty) return items.map((e) => e.msg).toList();
    final avisos = _listaAvisosPublicarNomeLogo();
    return avisos.isEmpty ? null : avisos;
  }

  Future<bool> _syncAndValidateLojaAtiva() async {
    final id = _resolvedLojaId?.trim();
    if (id != null &&
        id.isNotEmpty &&
        _lojaId == id &&
        _slug == id) {
      if (kDebugMode) {
        logD('[LOJA_CONFIG_RESOLVE_ONCE] skip StoreResolver — loja já resolvida ($_resolvedLojaId)');
      }
      return true;
    }

    final atual = (await StoreResolverFacade.resolveForAdminApp())?.trim();
    if (atual == null || atual.isEmpty) {
      _snack('Nenhuma loja ativa. Faça login novamente.', isError: true);
      return false;
    }

    final esperado = atual;

    if (_slug != esperado || _lojaId != esperado) {
      logD('⚠️ Loja divergente! sincronizando sessão');

      setState(() {
        _lojaId = esperado;
        _slug = esperado;
        _resolvedLojaId = esperado;
      });

      _configBox = await Hive.openBox(HiveBoxNames.lojaConfig(esperado));

      // Recarregar configurações do Firestore para a loja correta
      await _loadFromFirestore();
      setState(() {});
    }

    return true;
  }

  Future<void> _salvarRascunho({bool validar = true}) async {
    if (_salvando) return;

    if (!await _syncAndValidateLojaAtiva()) return;

    if (validar) {
      final r = _validarAntesDeSalvar();
      if (r.erros.isNotEmpty) {
        setState(() {
          _camposComErro.clear();
          _camposComErro.addAll(r.campos);
          _hubMode = false;
          if (r.campos.contains('whatsapp') || r.campos.contains('pedido_base')) {
            _pane = _Pane.identidade;
          } else if (r.campos.contains('sac_whatsapp')) {
            _pane = _Pane.menu;
          } else if (r.campos.contains('whatsapp_rodape')) {
            _pane = _Pane.rodape;
          } else {
            _pane = _Pane.identidade;
          }
        });
        _scheduleFirstErrorFieldFocus(_pane);
        _snack(r.erros.first, isError: true);
        return;
      }
      _camposComErro.clear();
    }

    final loja = _activeStoreId();

    setState(() => _salvando = true);
    try {
      Map<String, dynamic> data = _buildConfigMap(storeId: loja);

      // Preservar frete_config e cupons do draft atual (salvos na tela Fretes e Cupons).
      // Auto-save: sem GET no Firestore — usa cache do último load/save (evita leitura a cada 2s).
      // Salvar com validação: GET para capturar alterações feitas em Fretes/Cupons noutra aba.
      try {
        if (validar) {
          if (kDebugMode) logD('[LOJA_CONFIG_FIRESTORE_ONCE] merge draft GET (salvar com validação)');
          final draftSnap = await FirebaseFirestore.instance
              .collection('lojas')
              .doc(loja)
              .collection('draft_config')
              .doc('config')
              .get();
          if (draftSnap.exists && draftSnap.data() != null) {
            final draft = draftSnap.data()!;
            if (draft['frete_config'] != null) {
              data = Map<String, dynamic>.from(data);
              data['frete_config'] = draft['frete_config'];
              _mergeFreteConfigCache = draft['frete_config'];
            }
            if (draft['cupons'] != null) {
              data = Map<String, dynamic>.from(data);
              data['cupons'] = draft['cupons'];
              _mergeCuponsCache = draft['cupons'];
            }
          }
        } else {
          if (kDebugMode) logD('[LOJA_CONFIG_FIRESTORE_ONCE] skip draft GET (auto-save; cache merge)');
          if (_mergeFreteConfigCache != null) {
            data = Map<String, dynamic>.from(data);
            data['frete_config'] = _mergeFreteConfigCache;
          }
          if (_mergeCuponsCache != null) {
            data = Map<String, dynamic>.from(data);
            data['cupons'] = _mergeCuponsCache;
          }
        }
      } catch (_) {}

      if (data['frete_config'] != null) _mergeFreteConfigCache = data['frete_config'];
      if (data['cupons'] != null) _mergeCuponsCache = data['cupons'];

      if (kDebugMode) {
        logD('\n${"=" * 80}');
        logD('💾💾💾 [CONFIG] SALVANDO RASCUNHO 💾💾💾');
        logD('=' * 80);
        logD('Loja: $loja');
        logD('Logo Desktop: ${_logoUrlDesktop ?? "VAZIO"}');
        logD('Logo Mobile: ${_logoUrlMobile ?? "VAZIO"}');
        logD('Banners Desktop (${_bannersDesktop.length}): $_bannersDesktop');
        logD('Banners Mobile (${_bannersMobile.length}): $_bannersMobile');
        logD('-' * 80);
        logD('Estrutura media no Map:');
        logD('  media.desktop.logoUrl: ${data['media']?['desktop']?['logoUrl']}');
        logD('  media.desktop.banners: ${data['media']?['desktop']?['banners']}');
        logD('  media.mobile.logoUrl: ${data['media']?['mobile']?['logoUrl']}');
        logD('  media.mobile.banners: ${data['media']?['mobile']?['banners']}');
        logD('${'=' * 80}\n');
      }

      await _configBox.put('draft_config', data);
      await _configBox.flush();

      try {
        final ref = FirebaseFirestore.instance
            .collection('lojas')
            .doc(loja)
            .collection('draft_config')
            .doc('config');

        await ref.set(data, SetOptions(merge: true));

        logD('✅ [CONFIG] Salvo no Firestore: lojas/$loja/draft_config/config');
        _snack('Rascunho salvo com sucesso.');
        _captureHubBaseline();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          logD('⚠️ [CONFIG] Sem permissão para salvar no Firestore - mantido apenas localmente');
          _snack('Rascunho salvo localmente (sem permissão para sincronizar online).');
          _captureHubBaseline();
        } else {
          rethrow;
        }
      }
    } catch (e) {
      logD('❌ [CONFIG] Erro ao salvar (type=${e.runtimeType})');
      _snack('Erro ao salvar rascunho: $e', isError: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _sincronizarTudo() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    try {
      final results = await SyncFirestoreScript.syncTudo();
      if (!mounted) return;
      if (results['success'] == true) {
        final p = results['produtos'] as Map<String, int>? ?? {};
        final c = results['clientes'] as Map<String, int>? ?? {};
        _snack(
          'Sincronizado: ${p['synced'] ?? 0} produtos, ${c['synced'] ?? 0} clientes',
          isError: false,
        );
      } else {
        final err = results['errors'] as List<dynamic>?;
        _snack(err != null && err.isNotEmpty ? err.first.toString() : 'Erro na sincronização', isError: true);
      }
    } catch (e) {
      if (mounted) _snack('Erro ao sincronizar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _publicarTudo() async {
    if (_salvando) return;

    if (!await _syncAndValidateLojaAtiva()) return;
    if (!mounted) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_upload, color: _primaryColor, size: 28),
            SizedBox(width: 12),
            Text('Publicar catálogo?'),
          ],
        ),
        content: const Text(
          'As alterações serão publicadas e ficarão visíveis para seus clientes. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _successColor),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    // Validação extra antes de publicar (nome, logo)
    final avisosPublicar = _validarAntesDePublicar();
    if (avisosPublicar != null && avisosPublicar.isNotEmpty && mounted) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Atenção'),
          content: Text(
            'Recomendamos corrigir antes de publicar:\n\n${avisosPublicar.join('\n')}\n\nDeseja publicar mesmo assim?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Corrigir'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _successColor),
              child: const Text('Publicar mesmo assim'),
            ),
          ],
        ),
      );
      if (continuar != true || !mounted) return;
    }

    final r = _validarAntesDeSalvar();
    if (r.erros.isNotEmpty) {
      setState(() {
        _camposComErro.clear();
        _camposComErro.addAll(r.campos);
        _hubMode = false;
        if (r.campos.contains('whatsapp') || r.campos.contains('pedido_base')) {
          _pane = _Pane.identidade;
        } else if (r.campos.contains('sac_whatsapp')) {
          _pane = _Pane.menu;
        } else if (r.campos.contains('whatsapp_rodape')) {
          _pane = _Pane.rodape;
        } else {
          _pane = _Pane.identidade;
        }
      });
      _scheduleFirstErrorFieldFocus(_pane);
      _snack(r.erros.first, isError: true);
      return;
    }
    final avisos = <String>[];
    if (_nomeCtrl.text.trim().isEmpty) avisos.add('Informe o nome da loja.');
    // ✅ Logo: exige só se nunca publicou (se já tem publicado, será preservado)
    final temLogoForm = (_logoUrlDesktop ?? '').trim().isNotEmpty || (_logoUrlMobile ?? '').trim().isNotEmpty;
    if (!temLogoForm) {
      bool temLogoTemPublicada = false;
      try {
        final loja = _activeStoreId();
        final liveSnap = await FirebaseFirestore.instance
            .collection('lojas').doc(loja).collection('config').doc('config').get();
        if (liveSnap.exists && liveSnap.data() != null) {
          final live = liveSnap.data()!;
          final ld = (live['logoDesktopUrl'] ?? live['media']?['desktop']?['logoUrl'])?.toString().trim();
          final lm = (live['logoMobileUrl'] ?? live['media']?['mobile']?['logoUrl'])?.toString().trim();
          temLogoTemPublicada = (ld != null && ld.isNotEmpty) || (lm != null && lm.isNotEmpty);
        }
      } catch (_) {}
      if (!temLogoTemPublicada) avisos.add('Adicione pelo menos uma logo.');
    }
    if (avisos.isNotEmpty) {
      _snack(avisos.first, isError: true);
      return;
    }

    final loja = _activeStoreId();

    setState(() => _salvando = true);

    try {
      final fs = FirebaseFirestore.instance;
      final lojaDoc = fs.collection('lojas').doc(loja);

      // 0) Lê o draft atual e mescla com nosso data para preservar frete_config, cupons, etc (salvos em Fretes e Cupons)
      Map<String, dynamic> data = _buildConfigMap(storeId: loja);

      // 0.1) ✅ Logo e banner: se não houver novo selecionado, preserva o último publicado
      try {
        final liveSnap = await lojaDoc.collection('config').doc('config').get();
        if (liveSnap.exists && liveSnap.data() != null) {
          final live = liveSnap.data()!;
          data = Map<String, dynamic>.from(data);

          final logoD = (_logoUrlDesktop ?? '').trim();
          final logoM = (_logoUrlMobile ?? '').trim();
          final banD = _bannersDesktop;
          final banM = _bannersMobile;

          if (logoD.isEmpty && !_logoDesktopAlterado) {
            final prev = (live['logoDesktopUrl'] ?? live['media']?['desktop']?['logoUrl'])?.toString().trim();
            if (prev != null && prev.isNotEmpty) {
              data['logoDesktopUrl'] = prev;
              data['media'] ??= {};
              (data['media'] as Map)['desktop'] ??= {};
              ((data['media'] as Map)['desktop'] as Map)['logoUrl'] = prev;
            }
          }
          if (logoM.isEmpty && !_logoMobileAlterado) {
            final prev = (live['logoMobileUrl'] ?? live['media']?['mobile']?['logoUrl'])?.toString().trim();
            if (prev != null && prev.isNotEmpty) {
              data['logoMobileUrl'] = prev;
              data['media'] ??= {};
              (data['media'] as Map)['mobile'] ??= {};
              ((data['media'] as Map)['mobile'] as Map)['logoUrl'] = prev;
            }
          }
          if (banD.isEmpty && !_bannersDesktopAlterados) {
            final prev = (live['bannersDesktop'] ?? live['media']?['desktop']?['banners']);
            if (prev is List && prev.isNotEmpty) {
              final list = prev.map((e) => e.toString()).toList();
              data['bannersDesktop'] = list;
              data['media'] ??= {};
              (data['media'] as Map)['desktop'] ??= {};
              ((data['media'] as Map)['desktop'] as Map)['banners'] = list;
            }
          }
          if (banM.isEmpty && !_bannersMobileAlterados) {
            final prev = (live['bannersMobile'] ?? live['media']?['mobile']?['banners']);
            if (prev is List && prev.isNotEmpty) {
              final list = prev.map((e) => e.toString()).toList();
              data['bannersMobile'] = list;
              data['media'] ??= {};
              (data['media'] as Map)['mobile'] ??= {};
              ((data['media'] as Map)['mobile'] as Map)['banners'] = list;
            }
          }
        }
      } catch (_) {}

      try {
        final draftSnap = await lojaDoc.collection('draft_config').doc('config').get();
        if (draftSnap.exists && draftSnap.data() != null) {
          final draft = Map<String, dynamic>.from(draftSnap.data()!);
          // Preserva frete_config (Melhor Envio, SuperFrete, etc) e cupons vindos de Fretes e Cupons
          if (draft['frete_config'] != null) {
            data = Map<String, dynamic>.from(data);
            data['frete_config'] = draft['frete_config'];
          }
          if (draft['cupons'] != null) {
            data = Map<String, dynamic>.from(data);
            data['cupons'] = draft['cupons'];
          }
        }
      } catch (_) {}

      if (kDebugMode) {
        logD('\n${"=" * 80}');
        logD('🚀🚀🚀 [PUBLICAR] PUBLICANDO CATÁLOGO 🚀🚀🚀');
        logD('=' * 80);
        logD('LojaId: $loja');
        logD('theme.primaria: ${data['theme']?['primaria']}');
        if (data['theme']?['primaria'] != null) {
          final color = data['theme']['primaria'] as int;
          logD('Cor hex: #${color.toRadixString(16).padLeft(8, '0').toUpperCase()}');
        }
        logD('Destino: lojas/$loja/config/config');
        logD('${'=' * 80}\n');
      }

      // 1) Garante rascunho
      if (kDebugMode) logD('📝 Salvando em draft_config...');
      await lojaDoc
          .collection('draft_config')
          .doc('config')
          .set(data, SetOptions(merge: true));
      if (kDebugMode) logD('✅ Draft salvo!');

      // 1.1) Atualiza cache local para não perder mídia na próxima carga
      await _configBox.put('draft_config', data);
      await _configBox.flush();

      // 2) Publica em config/config (LIVE)
      if (kDebugMode) logD('🌐 Publicando em config (LIVE)...');
      await lojaDoc
          .collection('config')
          .doc('config')
          .set(data, SetOptions(merge: true));
      if (kDebugMode) logD('✅ Config LIVE publicado!');

      // 2.0) Invalida cache do catálogo no APK/Web para a próxima abertura usar config publicada
      CatalogCacheService.invalidate(loja, preview: false);
      if (kDebugMode) logD('🔄 [PUBLICAR] Cache do catálogo invalidado (APK/Web verá alterações na próxima abertura).');

      // 2.0b) Paleta legada: mantém `config_catalogo_live/main` alinhado ao [theme] publicado em config/config.
      await CatalogoConfigService.mirrorOfficialThemePaletteToLegacyLive(loja);

      // 2.1) Publica config/fretes para o FreteService (Melhor Envio, SuperFrete, etc.)
      final fc = data['frete_config'] as Map<String, dynamic>?;
      if (fc != null) {
        try {
          final cepO = (fc['cep_origem'] ?? fc['cepOrigem'] ?? '').toString().trim();
          final pesoEmb = double.tryParse((fc['peso_embalagem'] ?? '50').toString()) ?? 50.0;
          final fretesDoc = <String, dynamic>{
            'provider': (fc['provider'] ?? 'manual').toString(),
            'cepOrigem': cepO,
            'pesoEmbalagem': pesoEmb,
            'melhorEnvio': {'token': (fc['melhor_envio_token'] ?? '').toString().trim()},
            'superfrete': {
              'token': (fc['superfrete_token'] ?? '').toString().trim(),
              'sandbox': fc['superfrete_sandbox'] == true,
            },
            'correios': {
              'usuario': (fc['correios_user'] ?? '').toString().trim(),
              'senha': (fc['correios_senha'] ?? '').toString().trim(),
            },
            'frenet': {'token': (fc['frenet_token'] ?? '').toString().trim()},
            'manualFretes': (data['fretes'] is List) ? data['fretes'] as List : [],
            'updatedAt': FieldValue.serverTimestamp(),
          };
          await lojaDoc.collection('config').doc('fretes').set(fretesDoc, SetOptions(merge: true));
          if (kDebugMode) logD('✅ config/fretes publicado (catálogo/frete).');
        } catch (e) {
          if (kDebugMode) logD('⚠️ [PUBLICAR] config/fretes falhou (type=${e.runtimeType})');
        }
      }

      // 3) Espelha no doc raiz (com slug amigável, link curto e máscara de subdomínio)
      final slugFinal = data['slug'] ?? loja;
      final linkCurto = (data['linkCurto'] ?? '').toString().trim().toLowerCase();
      final subMascara = (data['subdominioMascara'] ?? '').toString().trim().toLowerCase();
      final subDominio = (data['subdominioDominioBase'] ?? 'mastepalm.com.br').toString().trim().toLowerCase();
      final updateData = <String, dynamic>{
        'slug': slugFinal,
        'lojaId': loja,
        'nome': _nomeCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'publishedAt': FieldValue.serverTimestamp(),
      };
      if (linkCurto.isNotEmpty) updateData['linkCurto'] = linkCurto;
      if (subMascara.isNotEmpty) {
        updateData['subdominioMascara'] = subMascara;
        updateData['subdominioDominioBase'] = subDominio.isNotEmpty ? subDominio : 'mastepalm.com.br';
      }
      await lojaDoc.set(updateData, SetOptions(merge: true));

      // 4) Publica produtos (LIVE)
      logD('🚀 [PUBLICAR] Iniciando publicação de produtos para LIVE...');
      await CatalogoSyncService.pushAllToLive(lojaIdOverride: loja);
      logD('✅ [PUBLICAR] Produtos publicados com sucesso!');

      // 5) IMPORTANTE: Atualizar Hive local com as configurações publicadas
      // para evitar sobrescrita na próxima sincronização
      logD('💾 [PUBLICAR] Atualizando cache local (Hive)...');
      final configBox = Hive.box('config');
      await configBox.put('theme_primaria', data['theme']?['primaria']);
      await configBox.put('theme_fundo', data['theme']?['fundo']);
      await configBox.put('theme_card', data['theme']?['card']);
      await configBox.put('theme_texto', data['theme']?['texto']);
      await configBox.put('theme_botaoTexto', data['theme']?['botaoTexto']);
      logD('✅ [PUBLICAR] Cache local atualizado!');

      if (mounted) {
        setState(() {
          _logoDesktopAlterado = false;
          _logoMobileAlterado = false;
          _bannersDesktopAlterados = false;
          _bannersMobileAlterados = false;
        });
      }

      _snack('Catálogo publicado! Alterações já estão no site e no app.');
      _captureHubBaseline();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        logD('⚠️ [PUBLICAR] Sem permissão para publicar');
        _snack('Sem permissão para publicar. Verifique se você é administrador da loja.', isError: true);
      } else {
        logD('❌ [PUBLICAR] Erro Firebase (type=${e.runtimeType})');
        _snack('Erro ao publicar: ${e.message}', isError: true);
      }
    } catch (e) {
      logD('❌ [PUBLICAR] Erro inesperado (type=${e.runtimeType})');
      _snack('Erro ao publicar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  // ================= PRESETS DE TEMA =================

  _LayoutPreset? _presetFromString(String s) {
    switch (s) {
      case 'masterPadrao':
        return _LayoutPreset.masterPadrao;
      case 'masterLuxo':
        return _LayoutPreset.masterLuxo;
      case 'darkClean':
        return _LayoutPreset.darkClean;
    }
    return null;
  }

  String _presetToString(_LayoutPreset p) {
    switch (p) {
      case _LayoutPreset.masterPadrao:
        return 'masterPadrao';
      case _LayoutPreset.masterLuxo:
        return 'masterLuxo';
      case _LayoutPreset.darkClean:
        return 'darkClean';
    }
  }

  void _applyPreset(_LayoutPreset preset) {
    setState(() {
      _layoutPreset = preset;
      switch (preset) {
        case _LayoutPreset.masterPadrao:
          // Cores base
          _cFundo = const Color(0xFF050509);
          _cCard = const Color(0xFF11111A);
          _cTexto = Colors.white;
          _cPrimaria = const Color(0xFF00A8FF);
          _cBotaoTexto = Colors.white;
          _cCabecalho = const Color(0xFF050509);
          // Cores expandidas
          _cTextSecondary = const Color(0xFFB0B0B0);
          _cCardTextPrimary = Colors.white;
          _cCardTextSecondary = const Color(0xFFB0B0B0);
          _cPriceHighlight = const Color(0xFF4ADE80);
          _cDanger = const Color(0xFFEF4444);
          _cFieldHint = const Color(0xFF6B7280);
          _cFieldBorder = const Color(0xFF374151);
          _cDivider = const Color(0xFF374151);
          _cButtonSecondaryBg = Colors.transparent;
          _cButtonSecondaryText = const Color(0xFF00A8FF);
          _cButtonSecondaryBorder = const Color(0xFF00A8FF);
          _cBadgeBackground = const Color(0xFF00A8FF).withOpacity(0.15);
          _cBadgeText = const Color(0xFF00A8FF);
          _cIcon = Colors.white;
          _cShadow = Colors.black45;
          // Cabeçalho
          _cHeaderText = Colors.white;
          _cHeaderIcon = Colors.white;
          _cHeaderSearchBg = Colors.white10;
          _cHeaderSearchText = Colors.white;
          _cHeaderSearchHint = Colors.white70;
          // Rodapé
          _cFooterBackground = const Color(0xFF050509);
          _cFooterText = Colors.white;
          _cFooterTextSecondary = Colors.white70;
          _cFooterIcon = Colors.white70;
          _cFooterLink = const Color(0xFF00A8FF);
          _cFooterDivider = Colors.white24;
          // Carrinho
          _cCarrinhoCard = const Color(0xFF11111A);
          _cCarrinhoCampo = const Color(0xFF1E1E24);
          _cCarrinhoTexto = Colors.white70;
          _cCarrinhoLabel = Colors.white;
          _cCarrinhoTotal = const Color(0xFF4ADE80);
          break;

        case _LayoutPreset.masterLuxo:
          // Cores base
          _cFundo = const Color(0xFF08080B);
          _cCard = const Color(0xFF14141E);
          _cTexto = const Color(0xFFF5F5F5);
          _cPrimaria = const Color(0xFFFFD700);
          _cBotaoTexto = Colors.black;
          _cCabecalho = const Color(0xFF08080B);
          // Cores expandidas
          _cTextSecondary = const Color(0xFFD4D4D4);
          _cCardTextPrimary = const Color(0xFFF5F5F5);
          _cCardTextSecondary = const Color(0xFFD4D4D4);
          _cPriceHighlight = const Color(0xFFFFD700);
          _cDanger = const Color(0xFFDC2626);
          _cFieldHint = const Color(0xFF9CA3AF);
          _cFieldBorder = const Color(0xFF4B5563);
          _cDivider = const Color(0xFF4B5563);
          _cButtonSecondaryBg = Colors.transparent;
          _cButtonSecondaryText = const Color(0xFFFFD700);
          _cButtonSecondaryBorder = const Color(0xFFFFD700);
          _cBadgeBackground = const Color(0xFFFFD700).withOpacity(0.15);
          _cBadgeText = const Color(0xFFFFD700);
          _cIcon = const Color(0xFFF5F5F5);
          _cShadow = Colors.black54;
          // Cabeçalho
          _cHeaderText = const Color(0xFFF5F5F5);
          _cHeaderIcon = const Color(0xFFFFD700);
          _cHeaderSearchBg = Colors.white10;
          _cHeaderSearchText = const Color(0xFFF5F5F5);
          _cHeaderSearchHint = const Color(0xFFD4D4D4);
          // Rodapé
          _cFooterBackground = const Color(0xFF08080B);
          _cFooterText = const Color(0xFFF5F5F5);
          _cFooterTextSecondary = const Color(0xFFD4D4D4);
          _cFooterIcon = const Color(0xFFFFD700);
          _cFooterLink = const Color(0xFFFFD700);
          _cFooterDivider = const Color(0xFF4B5563);
          // Carrinho
          _cCarrinhoCard = const Color(0xFF14141E);
          _cCarrinhoCampo = const Color(0xFF1E1E24);
          _cCarrinhoTexto = const Color(0xFFD4D4D4);
          _cCarrinhoLabel = const Color(0xFFF5F5F5);
          _cCarrinhoTotal = const Color(0xFFFFD700);
          break;

        case _LayoutPreset.darkClean:
          // Cores base
          _cFundo = const Color(0xFF101014);
          _cCard = const Color(0xFF1E1E24);
          _cTexto = Colors.white70;
          _cPrimaria = const Color(0xFF00FFA3);
          _cBotaoTexto = Colors.black;
          _cCabecalho = const Color(0xFF101014);
          // Cores expandidas
          _cTextSecondary = const Color(0xFF9CA3AF);
          _cCardTextPrimary = Colors.white70;
          _cCardTextSecondary = const Color(0xFF9CA3AF);
          _cPriceHighlight = const Color(0xFF00FFA3);
          _cDanger = const Color(0xFFF87171);
          _cFieldHint = const Color(0xFF6B7280);
          _cFieldBorder = const Color(0xFF374151);
          _cDivider = const Color(0xFF374151);
          _cButtonSecondaryBg = Colors.transparent;
          _cButtonSecondaryText = const Color(0xFF00FFA3);
          _cButtonSecondaryBorder = const Color(0xFF00FFA3);
          _cBadgeBackground = const Color(0xFF00FFA3).withOpacity(0.15);
          _cBadgeText = const Color(0xFF00FFA3);
          _cIcon = Colors.white70;
          _cShadow = Colors.black38;
          // Cabeçalho
          _cHeaderText = Colors.white70;
          _cHeaderIcon = const Color(0xFF00FFA3);
          _cHeaderSearchBg = Colors.white10;
          _cHeaderSearchText = Colors.white70;
          _cHeaderSearchHint = const Color(0xFF9CA3AF);
          // Rodapé
          _cFooterBackground = const Color(0xFF101014);
          _cFooterText = Colors.white70;
          _cFooterTextSecondary = const Color(0xFF9CA3AF);
          _cFooterIcon = const Color(0xFF00FFA3);
          _cFooterLink = const Color(0xFF00FFA3);
          _cFooterDivider = const Color(0xFF374151);
          // Carrinho
          _cCarrinhoCard = const Color(0xFF1E1E24);
          _cCarrinhoCampo = const Color(0xFF262630);
          _cCarrinhoTexto = const Color(0xFF9CA3AF);
          _cCarrinhoLabel = Colors.white70;
          _cCarrinhoTotal = const Color(0xFF00FFA3);
          break;
      }
    });

    _salvarRascunho(validar: false);
  }

  /// Preenche o estado de cores do catálogo a partir de um preset visual (sem alterar [_layoutPreset]).
  void _applyCatalogPaletteColorsToState(CatalogPaletteColors p) {
    _cFundo = p.cFundo;
    _cCard = p.cCard;
    _cTexto = p.cTexto;
    _cPrimaria = p.cPrimaria;
    _cBotaoTexto = p.cBotaoTexto;
    _cCabecalho = p.cCabecalho;
    _cCarrinhoCard = p.cCarrinhoCard;
    _cCarrinhoCampo = p.cCarrinhoCampo;
    _cCarrinhoTexto = p.cCarrinhoTexto;
    _cCarrinhoLabel = p.cCarrinhoLabel;
    _cCarrinhoTotal = p.cCarrinhoTotal;
    _cTextSecondary = p.cTextSecondary;
    _cCardTextPrimary = p.cCardTextPrimary;
    _cCardTextSecondary = p.cCardTextSecondary;
    _cPriceHighlight = p.cPriceHighlight;
    _cDanger = p.cDanger;
    _cFieldHint = p.cFieldHint;
    _cFieldBorder = p.cFieldBorder;
    _cDivider = p.cDivider;
    _cButtonSecondaryBg = p.cButtonSecondaryBg;
    _cButtonSecondaryText = p.cButtonSecondaryText;
    _cButtonSecondaryBorder = p.cButtonSecondaryBorder;
    _cBadgeBackground = p.cBadgeBackground;
    _cBadgeText = p.cBadgeText;
    _cIcon = p.cIcon;
    _cShadow = p.cShadow;
    _cHeaderText = p.cHeaderText;
    _cHeaderIcon = p.cHeaderIcon;
    _cHeaderSearchBg = p.cHeaderSearchBg;
    _cHeaderSearchText = p.cHeaderSearchText;
    _cHeaderSearchHint = p.cHeaderSearchHint;
    _cFooterBackground = p.cFooterBackground;
    _cFooterText = p.cFooterText;
    _cFooterTextSecondary = p.cFooterTextSecondary;
    _cFooterIcon = p.cFooterIcon;
    _cFooterLink = p.cFooterLink;
    _cFooterDivider = p.cFooterDivider;
    _cDicasBackground = p.cDicasBackground;
    _cDicasFooterBg = p.cDicasFooterBg;
    _cDicasFooterText = p.cDicasFooterText;
    _cDicasButtonBg = p.cDicasButtonBg;
    _cDicasButtonText = p.cDicasButtonText;
    _cDicasTopicPrimary = p.cDicasTopicPrimary;
    _promoBarBg = p.promoBarBg;
    _promoBarText = p.promoBarText;
    _heroCardBg = p.heroCardBg;
    _heroTitleColor = p.heroTitleColor;
    _heroSubtitleColor = p.heroSubtitleColor;
    _heroButtonBg = p.heroButtonBg;
    _heroButtonTextColor = p.heroButtonTextColor;
  }

  Future<void> _confirmApplyVisualPalette(CatalogVisualPalettePreset preset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final sw = preset.colors.previewSwatches;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Aplicar “${preset.title}”?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.description, style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 14),
                Text(
                  'Serão atualizadas de uma vez as principais cores do catálogo: página, cards, textos, botões, preços, carrinho, cabeçalho, rodapé, dicas, barra promocional e banner hero. '
                  'Nada é publicado automaticamente no site — use Publicar quando quiser. Você pode editar cada cor depois.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Prévia',
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in sw)
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(ctx).colorScheme.outline.withOpacity(0.3),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aplicar paleta'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    setState(() => _applyCatalogPaletteColorsToState(preset.colors));
    _salvarRascunho(validar: false);
    _snack('Paleta “${preset.title}” aplicada ao rascunho. Ajuste as cores se quiser e publique quando estiver pronto.');
  }

  CatalogStoreMiniPreviewColors _catalogMiniPreviewColors() {
    return CatalogStoreMiniPreviewColors(
      pageBackground: _cFundo,
      headerBackground: _cCabecalho,
      headerText: _cHeaderText,
      headerIcon: _cHeaderIcon,
      searchBackground: _cHeaderSearchBg,
      searchHint: _cHeaderSearchHint,
      promoBackground: _promoBarBg,
      promoForeground: _promoBarText,
      heroCardBackground: _heroCardBg,
      heroTitle: _heroTitleColor,
      heroSubtitle: _heroSubtitleColor,
      heroButtonBackground: _heroButtonBg,
      heroButtonForeground: _heroButtonTextColor,
      cardBackground: _cCard,
      cardShadow: _cShadow,
      cardTitle: _cCardTextPrimary,
      cardSubtitle: _cCardTextSecondary,
      priceHighlight: _cPriceHighlight,
      badgeBackground: _cBadgeBackground,
      badgeForeground: _cBadgeText,
      primaryButtonBackground: _cPrimaria,
      primaryButtonForeground: _cBotaoTexto,
      outlineButtonBorder: _cButtonSecondaryBorder,
      outlineButtonForeground: _cButtonSecondaryText,
      cartPanelBackground: _cCarrinhoCard,
      cartFieldBackground: _cCarrinhoCampo,
      cartLabel: _cCarrinhoLabel,
      cartBody: _cCarrinhoTexto,
      cartTotal: _cCarrinhoTotal,
      footerBackground: _cFooterBackground,
      footerText: _cFooterText,
      footerSecondary: _cFooterTextSecondary,
      divider: _cDivider,
    );
  }

  String _miniPreviewStoreName() {
    final t = _nomeCtrl.text.trim();
    return t.isEmpty ? 'Sua loja' : t;
  }

  Future<void> _abrirPreviewCatalogo() async {
    final lojaId = _activeStoreId();
    final tier = await PlanAccessResolver.currentTier();
    if (!mounted) return;

    // Web: usa rota nomeada para manter histórico do browser (voltar no iPhone/Chrome).
    if (kIsWeb) {
      Navigator.of(context).pushNamed(
        '/loja_preview',
        arguments: <String, dynamic>{'lojaId': lojaId},
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicCatalogScreen(
          lojaId: lojaId,
          preview: true,
          adminPreviewTier: tier,
        ),
      ),
    );
  }

  void _showModernSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ================= UI PRINCIPAL =================

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      _debugLojaConfigBuildCount++;
      if (_debugLojaConfigBuildCount == 1 || _debugLojaConfigBuildCount % 50 == 0) {
        logD('[LOJA_CONFIG_BUILD_COUNT] $_debugLojaConfigBuildCount');
      }
    }
    if (_carregando && !_erroCarregamento) {
      return Scaffold(
        backgroundColor: _surfaceColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: _primaryColor),
              const SizedBox(height: 16),
              Text(
                'Carregando configurações...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_erroCarregamento) {
      return Scaffold(
        backgroundColor: _surfaceColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _errorColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline, size: 64, color: _errorColor),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Erro ao carregar configurações',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _mensagemErro.isNotEmpty ? _mensagemErro : 'Verifique sua conexão e tente novamente.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _retryCarregar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Voltar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final publicBase =
        (_configBox.get('public_base_url') ?? 'https://app.mastepalm.com.br')
            .toString();

    final lojaAtiva = _activeStoreId();

    // ✅ USA SLUG AMIGÁVEL na URL pública (se disponível)
    String slugParaUrl = _slugCtrl.text.trim();
    if (slugParaUrl.isEmpty) {
      // Fallback: gera slug do nome
      slugParaUrl = _nomeCtrl.text.trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
    }
    if (slugParaUrl.isEmpty) {
      slugParaUrl = lojaAtiva; // Último fallback: usa ID técnico
    }

    final linkCurto = _linkCurtoCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    final urlPublica = linkCurto.isNotEmpty
        ? '$publicBase/c/$linkCurto'
        : '$publicBase/loja/$slugParaUrl';

    final isWide = MediaQuery.of(context).size.width >= 980;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_hubMode) {
      return Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: _buildModuleConfigView(cs, isDark),
          ),
          if (_mostrarTutorial) _buildTutorialOverlay(),
        ],
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _erroCarregamento = false);
            await _verificarConectividade();
            await _initConfig();
          },
          color: _primaryColor,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: _primaryColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: _buildLojaConfigAppBarActions(cs, isDark),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_primaryColor, _secondaryColor],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50,
                        top: -50,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -30,
                        bottom: -30,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Configurações da Loja',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Escolha um módulo abaixo para editar com foco',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_offline)
              SliverToBoxAdapter(
                child: _LojaConfigOfflineConnectivityStripe(
                  onVerificar: _verificarConectividade,
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // URL pública fixa no topo
                    _buildUrlCard(urlPublica),
                    if (_isFreeLimitedCatalog) ...[
                      const SizedBox(height: 12),
                      _buildFreeLimitedCatalogBanner(cs),
                    ],
                    if (_isBasicCatalog) ...[
                      const SizedBox(height: 12),
                      _buildBasicCatalogBanner(cs),
                    ],
                    const SizedBox(height: 12),
                    if (!_isFreeLimitedCatalog)
                      _buildUrlCard(
                        '$urlPublica?page=dicas',
                        label: 'Link da tela Dicas e Informações',
                        subtitle: 'Use este link para enviar somente a página de dicas ao cliente',
                      ),
                    if (!_isFreeLimitedCatalog) const SizedBox(height: 16),
                    if (!_isFreeLimitedCatalog) ...[
                      CatalogStorePaletteCard(
                        entries: _catalogPaletteOverviewEntries(),
                        compactStrip: true,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildLojaConfigHub(isWide),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
          if (_mostrarTutorial) _buildTutorialOverlay(),
        ],
      ),
    );
  }

  Widget _buildTutorialOverlay() {
    final passo = _tutorialPassos[_tutorialPasso];
    final total = _tutorialPassos.length;
    return _LojaConfigTutorialOverlay(
      primaryColor: _primaryColor,
      title: passo.$1,
      body: passo.$2,
      icon: passo.$3,
      stepIndex: _tutorialPasso,
      totalSteps: total,
      onPular: _fecharTutorial,
      onProximo: () => setState(() => _tutorialPasso++),
      onConcluir: _fecharTutorial,
    );
  }

  Widget _buildUrlCard(String urlPublica, {String? label, String? subtitle}) {
    return _LojaConfigUrlCard(
      urlPublica: urlPublica,
      label: label,
      subtitle: subtitle,
      primaryColor: _primaryColor,
      onCopy: () async {
        await Clipboard.setData(ClipboardData(text: urlPublica));
        _showModernSnackBar('URL copiada!');
      },
    );
  }

  /// Ações compartilhadas entre o hub (SliverAppBar) e a vista de módulo (AppBar).
  List<Widget> _buildLojaConfigAppBarActions(ColorScheme cs, bool isDark) {
    final hubErrEdges =
        !_hubMode ? _hubErrorPrevNextForCurrentPane() : (prev: null, next: null);
    final compact = MediaQuery.sizeOf(context).width < 420;
    final actionIconColor = isDark ? cs.primary : Colors.white;

    return [
      if (_salvando)
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      IconButton(
        icon: Icon(Icons.save_outlined, color: actionIconColor),
        tooltip: 'Salvar',
        onPressed: _salvando ? null : _salvarRascunho,
      ),
      if (_sincronizando)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        )
      else
        IconButton(
          icon: Icon(Icons.cloud_sync_outlined, color: actionIconColor),
          tooltip: 'Sincronizar dados',
          onPressed: _sincronizarTudo,
        ),
      IconButton(
        icon: Icon(Icons.cloud_upload_outlined, color: actionIconColor),
        tooltip: 'Publicar (salva e publica)',
        onPressed: _salvando ? null : _publicarTudo,
      ),
      IconButton(
        icon: Icon(Icons.visibility_outlined, color: actionIconColor),
        tooltip: 'Pré-visualizar',
        onPressed: _salvando ? null : () => unawaited(_abrirPreviewCatalogo()),
      ),
      if (hubErrEdges.next != null)
        compact
            ? IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                tooltip: 'Ir para o próximo erro',
                onPressed: _openNextHubErrorTarget,
              )
            : Tooltip(
                message: 'Ir para o próximo módulo com erro na ordem do hub.',
                waitDuration: const Duration(milliseconds: 400),
                child: TextButton.icon(
                  onPressed: _openNextHubErrorTarget,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.skip_next_rounded, size: 20),
                  label: const Text(
                    'Próximo erro',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1),
                  ),
                ),
              ),
      if (hubErrEdges.prev != null)
        compact
            ? IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                tooltip: 'Ir para o erro anterior',
                onPressed: _openPrevHubErrorTarget,
              )
            : Tooltip(
                message: 'Ir para o módulo com erro anterior na ordem do hub.',
                waitDuration: const Duration(milliseconds: 400),
                child: TextButton.icon(
                  onPressed: _openPrevHubErrorTarget,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.skip_previous_rounded, size: 20),
                  label: const Text(
                    'Erro anterior',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1),
                  ),
                ),
              ),
      const SizedBox(width: 8),
    ];
  }

  /// Tela cheia de um módulo: mesmos widgets de edição, mesmo estado (sem [Navigator.push]).
  Widget _buildModuleConfigView(ColorScheme cs, bool isDark) {
    return _ModuleConfigViewShell(host: this, cs: cs, isDark: isDark);
  }

  /// Metadados de navegação por painel (mesma ordem do enum de fluxo atual).
  List<Map<String, dynamic>> _lojaConfigNavItems() {
    return <Map<String, dynamic>>[
      {
        'pane': _Pane.identidade,
        'label': 'Identidade & Contato',
        'railLabel': 'Identidade',
        'subtitle': 'Nome, WhatsApp, domínio próprio do catálogo e dados básicos',
        'icon': Icons.storefront_outlined,
      },
      {
        'pane': _Pane.midias,
        'label': 'Mídias & Banners',
        'railLabel': 'Mídias',
        'subtitle': 'Logo e banners para desktop e mobile',
        'icon': Icons.photo_library_outlined,
      },
      {
        'pane': _Pane.tema,
        'label': 'Tema & Cores',
        'railLabel': 'Tema',
        'subtitle': 'Cores do catálogo e checkout',
        'icon': Icons.palette_outlined,
      },
      {
        'pane': _Pane.layout,
        'label': 'Layout dos cards',
        'railLabel': 'Layout',
        'subtitle': 'Colunas, sombras, bordas',
        'icon': Icons.dashboard_customize_outlined,
      },
      {
        'pane': _Pane.menu,
        'label': 'Menu & Páginas',
        'railLabel': 'Menu',
        'subtitle': 'Configurar navegação do catálogo',
        'icon': Icons.menu_open_outlined,
      },
      {
        'pane': _Pane.dicas,
        'label': 'Dicas e informações',
        'railLabel': 'Dicas',
        'subtitle': 'Cuidados, garantias, qualidade – link no menu do catálogo',
        'icon': Icons.lightbulb_outline,
      },
      {
        'pane': _Pane.rodape,
        'label': 'Rodapé & Links',
        'railLabel': 'Rodapé',
        'subtitle': 'Redes sociais, políticas, sobre',
        'icon': Icons.view_day_outlined,
      },
      {
        'pane': _Pane.financeiro,
        'label': 'Taxas Financeiras',
        'railLabel': 'Taxas',
        'subtitle': 'Relatórios Financeiros e Financeiro & Metas',
        'icon': Icons.percent_outlined,
      },
      {
        'pane': _Pane.publicar,
        'label': 'Publicar catálogo',
        'railLabel': 'Publicar',
        'subtitle': 'Publicar alterações no site',
        'icon': Icons.cloud_upload_outlined,
      },
    ];
  }

  InputDecorationTheme _lojaConfigInputDecorationTheme(ColorScheme cs) {
    final r = BorderRadius.circular(10);
    return InputDecorationTheme(
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      isDense: false,
      labelStyle: TextStyle(
        color: cs.onSurfaceVariant.withOpacity(0.95),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
      floatingLabelStyle: TextStyle(
        color: cs.primary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: cs.onSurfaceVariant.withOpacity(0.75),
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      helperStyle: TextStyle(
        color: cs.onSurfaceVariant.withOpacity(0.88),
        fontSize: 12,
        height: 1.35,
      ),
      errorStyle: TextStyle(color: cs.error, fontSize: 12, height: 1.3),
      prefixIconColor: cs.onSurfaceVariant,
      border: OutlineInputBorder(borderRadius: r),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
        borderRadius: r,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 1.5),
        borderRadius: r,
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.error, width: 1.5),
        borderRadius: r,
      ),
    );
  }

  /// Mesmo Theme dos campos que estava dentro de cada ExpansionTile.
  Widget _wrapLojaConfigFieldTheme(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: _lojaConfigInputDecorationTheme(cs),
      ),
      child: child,
    );
  }

  /// Apenas o switch de painéis — mesma árvore de widgets de antes.
  Widget _buildPaneEditorFor(_Pane pane) {
    if (_paneLockedForCatalogConfig(pane)) {
      return _buildFreeLimitedLockedPaneBody();
    }
    return switch (pane) {
      _Pane.identidade => _paneIdentidade(),
      _Pane.midias => _paneMidias(),
      _Pane.tema => _paneTema(),
      _Pane.layout => _paneLayout(),
      _Pane.menu => _paneMenu(),
      _Pane.dicas => _paneDicas(),
      _Pane.rodape => _paneRodape(),
      _Pane.financeiro => _paneFinanceiro(),
      _Pane.publicar => _panePublicar(),
    };
  }

  Widget _buildFreeLimitedCatalogBanner(ColorScheme cs) {
    return _LojaConfigFreeLimitedPlanBanner(
      colorScheme: cs,
      onPlanos: () => Navigator.of(context).pushNamed('/planos'),
    );
  }

  Widget _buildBasicCatalogBanner(ColorScheme cs) {
    return _LojaConfigBasicPlanBanner(
      colorScheme: cs,
      onPlanos: () => Navigator.of(context).pushNamed('/planos'),
    );
  }

  Widget _buildFreeLimitedLockedPaneBody() {
    final cs = Theme.of(context).colorScheme;
    return _LojaConfigFreeLimitedLockedPaneBody(
      colorScheme: cs,
      onPlanos: () => Navigator.of(context).pushNamed('/planos'),
      onVoltarModulos: _goToHub,
    );
  }

  /// Agrega cores do draft atual por valor ARGB (mesma base da paleta e das sugestões nos editores).
  void _fillCatalogPaletteBucket(Map<int, Set<String>> bucket) {
    void put(Color c, String label) {
      bucket.putIfAbsent(c.value, () => <String>{}).add(label);
    }

    put(_cFundo, 'Fundo da página');
    put(_cCard, 'Fundo dos cards');
    put(_cTexto, 'Texto principal');
    put(_cPrimaria, 'Botão Comprar – fundo');
    put(_cBotaoTexto, 'Botão Comprar – texto');
    put(_cCabecalho, 'Fundo cabeçalho catálogo');
    put(_cCarrinhoCard, 'Carrinho – fundo do card');
    put(_cCarrinhoCampo, 'Carrinho – campos');
    put(_cCarrinhoTexto, 'Carrinho – texto dos campos');
    put(_cCarrinhoLabel, 'Carrinho – rótulos');
    put(_cCarrinhoTotal, 'Carrinho – total a pagar');
    put(_cTextSecondary, 'Texto secundário');
    put(_cCardTextPrimary, 'Nome do produto');
    put(_cCardTextSecondary, 'Texto card secundário');
    put(_cPriceHighlight, 'Preço (valor)');
    put(_cDanger, 'Cor de perigo');
    put(_cFieldHint, 'Campo hint');
    put(_cFieldBorder, 'Campo borda');
    put(_cDivider, 'Divisórias');
    put(_cButtonSecondaryBg, 'Botão Ver – fundo');
    put(_cButtonSecondaryText, 'Botão Ver – texto');
    put(_cButtonSecondaryBorder, 'Botão Ver – borda');
    put(_cBadgeBackground, 'Badge – fundo');
    put(_cBadgeText, 'Badge – texto');
    put(_cIcon, 'Ícones');
    put(_cShadow, 'Sombras');
    put(_cHeaderText, 'Texto cabeçalho');
    put(_cHeaderIcon, 'Ícones cabeçalho');
    put(_cHeaderSearchBg, 'Busca – fundo');
    put(_cHeaderSearchText, 'Busca – texto');
    put(_cHeaderSearchHint, 'Busca – hint');
    put(_cFooterBackground, 'Rodapé – fundo');
    put(_cFooterText, 'Rodapé – texto');
    put(_cFooterTextSecondary, 'Rodapé – texto secundário');
    put(_cFooterIcon, 'Rodapé – ícones');
    put(_cFooterLink, 'Rodapé – links');
    put(_cFooterDivider, 'Rodapé – divisórias');
    put(_cDicasBackground, 'Dicas – fundo');
    put(_cDicasFooterBg, 'Dicas – rodapé fundo');
    put(_cDicasFooterText, 'Dicas – rodapé texto');
    put(_cDicasButtonBg, 'Dicas – botões');
    put(_cDicasButtonText, 'Dicas – texto botões');
    put(_cDicasTopicPrimary, 'Dicas – tópicos');
    put(_promoBarBg, 'Barra promo – fundo');
    put(_promoBarText, 'Barra promo – texto');
    put(_heroCardBg, 'Banner hero – card');
    put(_heroTitleColor, 'Banner hero – título');
    put(_heroSubtitleColor, 'Banner hero – subtítulo');
    put(_heroButtonBg, 'Banner hero – botão fundo');
    put(_heroButtonTextColor, 'Banner hero – botão texto');
  }

  /// Hash das cores da paleta — invalida cache de sugestões / card “Paleta da Loja”.
  int _computeCatalogPaletteHash() {
    return Object.hashAll([
      _cFundo.value,
      _cCard.value,
      _cTexto.value,
      _cPrimaria.value,
      _cBotaoTexto.value,
      _cCabecalho.value,
      _cCarrinhoCard.value,
      _cCarrinhoCampo.value,
      _cCarrinhoTexto.value,
      _cCarrinhoLabel.value,
      _cCarrinhoTotal.value,
      _cTextSecondary.value,
      _cCardTextPrimary.value,
      _cCardTextSecondary.value,
      _cPriceHighlight.value,
      _cDanger.value,
      _cFieldHint.value,
      _cFieldBorder.value,
      _cDivider.value,
      _cButtonSecondaryBg.value,
      _cButtonSecondaryText.value,
      _cButtonSecondaryBorder.value,
      _cBadgeBackground.value,
      _cBadgeText.value,
      _cIcon.value,
      _cShadow.value,
      _cHeaderText.value,
      _cHeaderIcon.value,
      _cHeaderSearchBg.value,
      _cHeaderSearchText.value,
      _cHeaderSearchHint.value,
      _cFooterBackground.value,
      _cFooterText.value,
      _cFooterTextSecondary.value,
      _cFooterIcon.value,
      _cFooterLink.value,
      _cFooterDivider.value,
      _cDicasBackground.value,
      _cDicasFooterBg.value,
      _cDicasFooterText.value,
      _cDicasButtonBg.value,
      _cDicasButtonText.value,
      _cDicasTopicPrimary.value,
      _promoBarBg.value,
      _promoBarText.value,
      _heroCardBg.value,
      _heroTitleColor.value,
      _heroSubtitleColor.value,
      _heroButtonBg.value,
      _heroButtonTextColor.value,
    ]);
  }

  void _ensureCatalogPaletteCaches() {
    final h = _computeCatalogPaletteHash();
    if (_catalogPaletteContentHash == h &&
        _cachedPaletteSuggestions != null &&
        _cachedPaletteOverview != null) {
      return;
    }
    _catalogPaletteContentHash = h;
    _cachedPaletteSuggestions = _buildCatalogColorPaletteSuggestions();
    _cachedPaletteOverview = _buildCatalogPaletteOverviewEntries();
  }

  /// Agrupamento só visual para sugestões (editor). Ordem de avaliação importa.
  String _groupKeyForCatalogOrigins(Set<String> origins) {
    bool any(bool Function(String o) fn) => origins.any(fn);

    if (any((o) {
      final l = o.toLowerCase();
      return (l.contains('comprar') && l.contains('fundo')) ||
          l.contains('botão ver') ||
          (l.contains('hero') && l.contains('botão')) ||
          l.contains('dicas – botões');
    })) {
      return 'principal';
    }
    if (any((o) {
      final l = o.toLowerCase();
      return l.contains('preço') ||
          l.contains('total a pagar') ||
          l.contains('barra promo') ||
          l.contains('badge') ||
          l.contains('dicas – tópicos');
    })) {
      return 'destaque';
    }
    if (any((o) {
      final l = o.toLowerCase();
      return l.contains('texto') ||
          l.contains('nome do produto') ||
          l.contains('hint') ||
          l.contains('rótulos');
    })) {
      return 'texto';
    }
    if (any((o) {
      final l = o.toLowerCase();
      return l.contains('fundo') ||
          l.contains('cards') ||
          l.contains('cabeçalho') ||
          l.contains('carrinho – fundo') ||
          l.contains('banner hero – card') ||
          l.contains('rodapé – fundo') ||
          l.contains('dicas – fundo');
    })) {
      return 'fundo';
    }
    return 'outro';
  }

  CatalogColorSuggestion _catalogSuggestionFromBucketEntry(int k, Map<int, Set<String>> bucket) {
    final origins = bucket[k]!.toList()..sort();
    return CatalogColorSuggestion(
      color: Color(k),
      originLabel: origins.join(' · '),
      group: _groupKeyForCatalogOrigins(origins.toSet()),
    );
  }

  /// Cores atuais da loja (draft) para sugestões de reutilização — só UX, não altera schema.
  List<CatalogColorSuggestion> _catalogColorPaletteSuggestions() {
    _ensureCatalogPaletteCaches();
    return _cachedPaletteSuggestions!;
  }

  List<CatalogColorSuggestion> _buildCatalogColorPaletteSuggestions() {
    final bucket = <int, Set<String>>{};
    _fillCatalogPaletteBucket(bucket);
    final list = bucket.entries
        .map((e) => _catalogSuggestionFromBucketEntry(e.key, bucket))
        .toList();
    list.sort((a, b) => a.originLabel.compareTo(b.originLabel));
    return list;
  }

  /// Paleta resumida para o card no topo: ordem útil + até [maxItems] cores distintas.
  List<CatalogColorSuggestion> _catalogPaletteOverviewEntries({int maxItems = 20}) {
    _ensureCatalogPaletteCaches();
    return _cachedPaletteOverview!.take(maxItems).toList();
  }

  List<CatalogColorSuggestion> _buildCatalogPaletteOverviewEntries() {
    const maxItems = 20;
    final bucket = <int, Set<String>>{};
    _fillCatalogPaletteBucket(bucket);
    CatalogColorSuggestion build(int k) => _catalogSuggestionFromBucketEntry(k, bucket);

    final seen = <int>{};
    final out = <CatalogColorSuggestion>[];

    void pick(Color c) {
      final k = c.value;
      if (!bucket.containsKey(k) || seen.contains(k)) return;
      seen.add(k);
      out.add(build(k));
    }

    // Identidade e fluxos principais primeiro
    pick(_cPrimaria);
    pick(_cBotaoTexto);
    pick(_cFundo);
    pick(_cCard);
    pick(_cTexto);
    pick(_cTextSecondary);
    pick(_cPriceHighlight);
    pick(_cCabecalho);
    pick(_cHeaderText);
    pick(_cCarrinhoCard);
    pick(_cCarrinhoTotal);
    pick(_cCarrinhoLabel);
    pick(_cFooterBackground);
    pick(_cFooterText);
    pick(_promoBarBg);
    pick(_promoBarText);
    pick(_heroCardBg);
    pick(_heroButtonBg);
    pick(_heroTitleColor);
    pick(_cCardTextPrimary);
    pick(_cDanger);

    final restKeys = bucket.keys.where((k) => !seen.contains(k)).toList()
      ..sort((a, b) {
        final sa = bucket[a]!.join(' · ');
        final sb = bucket[b]!.join(' · ');
        return sa.compareTo(sb);
      });
    for (final k in restKeys) {
      if (out.length >= maxItems) break;
      seen.add(k);
      out.add(build(k));
    }
    return out;
  }

  /// Temas e Cores: lista de sugestões calculada uma vez; chips só no bottom sheet (tela mais leve).
  Widget _catalogColorFieldTema({
    required String label,
    String? description,
    required Color color,
    required ValueChanged<Color> onChanged,
    required List<CatalogColorSuggestion> suggestions,
  }) {
    return CatalogColorFieldEditor(
      label: label,
      description: description,
      color: color,
      suggestions: suggestions,
      suggestionsLayout: CatalogColorSuggestionsLayout.bottomSheet,
      onColorChanged: (c) {
        onChanged(c);
        _salvarRascunho(validar: false);
      },
    );
  }

  /// Painel principal: atalho Fretes & Cupons + grid de módulos (cada um abre tela dedicada no mesmo [State]).
  Widget _buildLojaConfigHub(bool isWide) {
    final items = _lojaConfigNavItems();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Map<String, dynamic>? currentFull;
    if (_resolvedLojaId != null) {
      try {
        currentFull = _buildConfigMap(storeId: _activeStoreId());
      } catch (_) {
        currentFull = null;
      }
    }

    final hubSalvar = _coletarProblemasSalvar();
    final hubPubAvisos = hubSalvar.isEmpty ? _listaAvisosPublicarNomeLogo() : <String>[];
    final fretesDirty =
        currentFull != null && _hubFretesShortcutHasPendingChanges(currentFull);
    final fretesHub = _hubCardStateFretes(fretesDirty);

    var countError = 0;
    var countPending = 0;
    var countOk = 0;
    var countNeutral = 0;
    void tally(_HubModuleSignal s) {
      switch (s) {
        case _HubModuleSignal.error:
          countError++;
        case _HubModuleSignal.pending:
          countPending++;
        case _HubModuleSignal.ok:
          countOk++;
        case _HubModuleSignal.neutral:
          countNeutral++;
      }
    }

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final pane = item['pane'] as _Pane;
      final dirty =
          currentFull != null && _hubModuleHasPendingChanges(pane, currentFull);
      final signal = _hubCardStateForPane(pane, dirty, hubSalvar, hubPubAvisos).signal;
      tally(signal);
    }
    tally(fretesHub.signal);

    final queryRaw = _hubSearchCtrl.text.trim();
    final queryFolded = queryRaw.isEmpty ? '' : _hubFoldForSearch(queryRaw);

    final hubRows = <({bool fretes, Map<String, dynamic>? item, _HubModuleSignal signal, int origIndex})>[];
    final fretesMatches = _hubFilterAcceptsSignal(_hubModuleFilter, fretesHub.signal) &&
        _hubSearchMatchesFretes(queryFolded);
    if (fretesMatches) {
      hubRows.add((
        fretes: true,
        item: null,
        signal: fretesHub.signal,
        origIndex: -1,
      ));
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final pane = item['pane'] as _Pane;
      final dirty =
          currentFull != null && _hubModuleHasPendingChanges(pane, currentFull);
      final signal = _hubCardStateForPane(pane, dirty, hubSalvar, hubPubAvisos).signal;
      if (!_hubFilterAcceptsSignal(_hubModuleFilter, signal)) continue;
      if (!_hubSearchMatchesModule(item, queryFolded)) continue;
      hubRows.add((
        fretes: false,
        item: item,
        signal: signal,
        origIndex: i,
      ));
    }

    hubRows.sort((a, b) {
      final pa = _hubSignalPriority(a.signal);
      final pb = _hubSignalPriority(b.signal);
      if (pa != pb) return pa.compareTo(pb);
      return a.origIndex.compareTo(b.origIndex);
    });

    final countAll = items.length + 1;
    final hubGridEmpty = hubRows.isEmpty;
    final anyModuleRow = hubRows.any((r) => !r.fretes);

    List<Widget> hubDynamicBody() {
      if (hubGridEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
            child: Center(
              child: Text(
                queryRaw.isNotEmpty
                    ? 'Nenhum módulo corresponde à busca e ao filtro atual.'
                    : 'Nenhum módulo com este status.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withOpacity(0.9),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ];
      }

      final out = <Widget>[];
      var showedAreasTitle = false;
      var idx = 0;
      while (idx < hubRows.length) {
        final row = hubRows[idx];
        if (row.fretes) {
          out.add(
            _HubFretesShortcutCard(
              host: this,
              cs: cs,
              signal: fretesHub.signal,
              tooltip: fretesHub.tooltip,
            ),
          );
          out.add(const SizedBox(height: 18));
          idx++;
          continue;
        }
        if (!showedAreasTitle) {
          out.add(
            Text(
              'Áreas da loja',
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                letterSpacing: -0.1,
              ),
            ),
          );
          out.add(const SizedBox(height: 12));
          showedAreasTitle = true;
        }
        var j = idx;
        while (j < hubRows.length && !hubRows[j].fretes) {
          j++;
        }
        final batch = hubRows.sublist(idx, j);
        out.add(
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cross = w >= 1100 ? 3 : (w >= 560 ? 2 : 1);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cross,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: cross == 1 ? 2.2 : 1.42,
                children: [
                  for (final r in batch)
                    _HubModuleCardWidget(
                      host: this,
                      item: r.item!,
                      cs: cs,
                      dirty: currentFull != null &&
                          _hubModuleHasPendingChanges(r.item!['pane'] as _Pane, currentFull),
                      hubSalvar: hubSalvar,
                      hubPubAvisos: hubPubAvisos,
                    ),
                ],
              );
            },
          ),
        );
        idx = j;
      }

      if (!anyModuleRow) {
        out.add(
          Text(
            'Áreas da loja',
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              letterSpacing: -0.1,
            ),
          ),
        );
        out.add(const SizedBox(height: 12));
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Center(
              child: Text(
                queryRaw.isNotEmpty
                    ? 'Nenhuma área da loja corresponde à busca e ao filtro atual.'
                    : 'Nenhuma área da loja corresponde a este filtro.',
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withOpacity(0.88),
                  height: 1.4,
                ),
              ),
            ),
          ),
        );
      }

      return out;
    }

    return _LojaConfigHubShell(
      isWide: isWide,
      cs: cs,
      tt: tt,
      searchField: _HubSearchFieldWidget(host: this, cs: cs, tt: tt),
      filterStrip: _HubFilterStripWidget(
        host: this,
        cs: cs,
        tt: tt,
        countAll: countAll,
        countError: countError,
        countPending: countPending,
        countOk: countOk,
        countNeutral: countNeutral,
        showFirstErrorShortcut: countError > 0,
      ),
      moduleSections: hubDynamicBody(),
    );
  }

  // ============== HELPERS TEMA (modo escuro: texto visível nos campos) ==============

  /// Estilo do texto digitado nos campos – sempre contrasta com o fundo do tema.
  TextStyle _fieldTextStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(color: cs.onSurface, fontSize: 16);
  }

  /// InputDecoration com cores do tema para labels, hint e fundo legíveis no modo escuro.
  InputDecoration _inputDecoration(
    BuildContext context, {
    required String labelText,
    String? helperText,
    int? helperMaxLines,
    String? errorText,
    Widget? prefixIcon,
    InputBorder? errorBorder,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: labelText,
      helperText: helperText,
      helperMaxLines: helperMaxLines,
      errorText: errorText,
      prefixIcon: prefixIcon,
      isDense: true,
      filled: true,
      fillColor: cs.surface,
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
      hintStyle: TextStyle(color: cs.onSurfaceVariant),
      helperStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      errorStyle: TextStyle(color: cs.error),
      border: const OutlineInputBorder(),
      errorBorder: errorBorder ??
          OutlineInputBorder(
            borderSide: BorderSide(color: cs.error, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // ============== PANES ==============

  Widget _panePublicar() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_salvando)
          const LinearProgressIndicator(),

        // ✨ Campanhas e Roleta
        _Section(
          title: 'Sorteios e Promoções',
          child: Column(
            children: [
              // Toggle Campanha
              Container(
                decoration: BoxDecoration(
                  color: _campanhaAtiva
                      ? Colors.purple.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _campanhaAtiva
                        ? Colors.purple.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: SwitchListTile(
                  value: _campanhaAtiva,
                  onChanged: _salvando ? null : _toggleCampanhaAtiva,
                  title: Row(
                    children: [
                      Icon(
                        Icons.campaign,
                        color: _campanhaAtiva ? Colors.purple : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Campanha de Sorteio',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _campanhaAtiva
                                  ? 'Ativa: ${_campanhaAtivaNome ?? "Campanha"}'
                                  : 'Nenhuma campanha ativa',
                              style: TextStyle(
                                fontSize: 12,
                                color: _campanhaAtiva
                                    ? Colors.purple.shade700
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Toggle Roleta
              Container(
                decoration: BoxDecoration(
                  color: _roletaAtiva
                      ? Colors.amber.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _roletaAtiva
                        ? Colors.amber.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: SwitchListTile(
                  value: _roletaAtiva,
                  onChanged: _salvando ? null : _toggleRoletaAtiva,
                  title: Row(
                    children: [
                      Icon(
                        Icons.casino,
                        color: _roletaAtiva ? Colors.amber.shade700 : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Roleta da Sorte',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _roletaAtiva
                                  ? 'Ativa - clientes giram após compra'
                                  : 'Desativada',
                              style: TextStyle(
                                fontSize: 12,
                                color: _roletaAtiva
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Configure campanhas e prêmios da roleta em Sorteios e Campanhas no menu principal.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _Section(
          title: 'Publicar Catálogo',
          child: Column(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  minimumSize: const Size(double.infinity, 56),
                ),
                onPressed: _salvando ? null : _publicarTudo,
                icon: const Icon(Icons.publish, size: 28),
                label: const Text(
                  'PUBLICAR CATÁLOGO (TORNAR VISÍVEL)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.purple.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Clique aqui para publicar suas alterações e torná-las visíveis no catálogo web!',
                        style: TextStyle(
                          color: Colors.purple.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Como funciona?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '? Salvar rascunho grava localmente e em lojas/{store_id}/draft_config/config.\n'
                  '? Publicar copia o rascunho para lojas/{store_id}/config/config e também espelha no doc raiz.\n'
                  '? O Catálogo Web (LIVE) lê os dados publicados (config/config).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _paneIdentidade() => _PaneIdentidadeWidget(host: this);

  Widget _paneMidias() => _PaneMidiasWidget(host: this);

  // ============== PANE: TEMA ==============
  Widget _paneTema() {
    return _PaneTemaWidget(key: _paneTemaKey, host: this);
  }

  // ============== PANE: LAYOUT & CARDS ==============
  /// Acordeão / par responsivo: [loja_config_part_pane_wrappers.dart].
  Widget _paneLayout() => _PaneLayoutWidget(host: this);

  void _layoutSetStateAndSave(void Function() mutate) {
    setState(mutate);
    _salvarRascunho(validar: false);
  }

  void _layoutSetStateOnly(void Function() mutate) {
    setState(mutate);
  }

  void _layoutOnCatSelectedFromStoreChanged(String? v) {
    setState(() {
      _catSelectedFromStore = v;
      if (v != null) {
        _catImgCategoriaCtrl.text = v;
      }
    });
  }

  void _layoutSaveCategoryImagePressed() {
    setState(() {
      _upsertCategoryImageConfig();
    });
    _salvarRascunho(validar: false);
  }

  void _layoutRemoveCategoryImageByNameKey(String key) {
    final norm = _normalizeCategoryKey(key);
    setState(() {
      _categoryImagesByName.remove(key);
      _categoryImagesByName.remove(norm);
      _categoryImagesByName.remove('name:$norm');
    });
    _salvarRascunho(validar: false);
  }

  void _layoutRemoveCategoryImageById(String id) {
    setState(() => _categoryImagesById.remove(id));
    _salvarRascunho(validar: false);
  }

  void _layoutSetCardBorderRadius(double v) {
    setState(() => _cardBorderRadius = v);
  }

  Widget _buildLayoutPreviewRow({
    required int cols,
    required double borderRadius,
    required bool showShadow,
  }) {
    cols = cols.clamp(1, 6);
    return Row(
      children: List.generate(cols, (i) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == cols - 1 ? 0 : 8),
            height: 64,
            decoration: BoxDecoration(
              color: _cCard,
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: showShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Center(
              child: Text(
                'Card',
                style: TextStyle(
                  color: _cTexto.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ============== PANE: MENU & PÁGINAS ==============
  Widget _paneMenu() => _PaneMenuWidget(host: this);

  // ============== PANE: DICAS E INFORMAÇÕES ==============
  static const List<MapEntry<String, String>> _dicaTipos = [
    MapEntry('garantias', 'Garantias'),
    MapEntry('cuidados', 'Cuidados com o produto'),
    MapEntry('qualidade', 'Informações de qualidade'),
    MapEntry('informacoes', 'Informações gerais'),
    MapEntry('outros', 'Outras informações'),
  ];

  Widget _paneDicas() => _PaneDicasWidget(host: this);

  void _dicasRemoveAt(int index) {
    setState(() {
      _dicas.removeAt(index);
      _salvarRascunho(validar: false);
    });
  }

  Future<void> _adicionarDica(BuildContext context) async {
    await _showDicaDialog(context, null);
  }

  Future<void> _editarDica(BuildContext context, int index) async {
    if (index < 0 || index >= _dicas.length) return;
    await _showDicaDialog(context, _dicas[index], index: index);
  }

  Future<void> _showDicaDialog(BuildContext context, Map<String, dynamic>? initial, {int? index}) async {
    final tituloCtrl = TextEditingController(text: initial?['titulo']?.toString() ?? '');
    final conteudoCtrl = TextEditingController(text: initial?['conteudo']?.toString() ?? '');
    final bannerUrlCtrl = TextEditingController(text: initial?['bannerUrl'] ?? initial?['banner_url'] ?? '');
    final ordemCtrl = TextEditingController(
      text: '${(initial?['ordem'] is int) ? (initial!['ordem'] as int) : (int.tryParse('${initial?['ordem']}') ?? 0)}',
    );
    var tipo = (initial?['tipo'] ?? 'informacoes').toString().trim();
    if (tipo.isEmpty) tipo = 'informacoes';
    var ativo = (initial?['ativo'] as bool?) ?? true;

    final updated = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(index != null ? 'Editar dica' : 'Adicionar dica'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: tituloCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Título',
                        hintText: 'Ex: Garantia de 90 dias',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: tipo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: _dicaTipos
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => tipo = v ?? 'informacoes'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: conteudoCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Conteúdo / texto',
                        hintText: 'Texto que o cliente verá ao abrir a dica',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bannerUrlCtrl,
                            decoration: const InputDecoration(
                              labelText: 'URL do banner (opcional)',
                              hintText: 'Link ou importe da galeria',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final url = await _pickAndUploadDicaBanner();
                            if (url != null && ctx.mounted) {
                              setDialogState(() => bannerUrlCtrl.text = url);
                            }
                          },
                          icon: const Icon(Icons.photo_library, size: 18),
                          label: const Text('Galeria'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ex.: 562×180 (mobile) ou 1280×200 (desktop)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ordemCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Ordem',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Ativo'),
                            value: ativo,
                            onChanged: (v) => setDialogState(() => ativo = v),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final id = index != null && initial != null && (initial['id'] ?? '').toString().isNotEmpty
                        ? (initial['id']!).toString()
                        : DateTime.now().millisecondsSinceEpoch.toString();
                    Navigator.pop(ctx, {
                      'id': id,
                      'titulo': tituloCtrl.text.trim(),
                      'tipo': tipo,
                      'conteudo': conteudoCtrl.text.trim(),
                      'bannerUrl': bannerUrlCtrl.text.trim().isEmpty ? null : bannerUrlCtrl.text.trim(),
                      'ordem': int.tryParse(ordemCtrl.text.trim()) ?? 0,
                      'ativo': ativo,
                    });
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated != null && mounted) {
      setState(() {
        if (index != null) {
          _dicas[index] = updated;
        } else {
          _dicas.add(updated);
        }
        _salvarRascunho(validar: false);
      });
    }
  }

  // ============== PANE: TAXAS FINANCEIRAS ==============
  Widget _paneFinanceiro() {
    return _Section(
      title: 'Taxas para Relatórios Financeiros e Financeiro & Metas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneMutedIntroText(
            'Configure as taxas usadas nos cálculos de lucro e custos nos relatórios. '
            'Os valores padrão são mantidos; altere apenas se necessário para sua loja.',
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _taxaCartaoCtrl,
                    onChanged: (_) => _scheduleAutoSave(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Taxa de Cartão (%)',
                      helperText: 'Aplicada sobre pagamentos em cartão (padrão: 5%)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.credit_card_outlined),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taxaMEICtrl,
                    onChanged: (_) => _scheduleAutoSave(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Taxa MEI (%)',
                      helperText: 'Imposto simplificado sobre o total (padrão: 3,5%)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description_outlined),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _custosFixosCtrl,
                    onChanged: (_) => _scheduleAutoSave(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Custos Fixos (%)',
                      helperText: 'Luz, internet, aluguel etc. sobre o total (padrão: 10%)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.home_work_outlined),
                      suffixText: '%',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _custoEmbalagemCtrl,
                    onChanged: (_) => _scheduleAutoSave(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Custo de Embalagem por Item (R\$)',
                      helperText: 'Valor fixo por item vendido (padrão: R\$ 3,00)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      prefixText: 'R\$ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Essas taxas são usadas nos cálculos de lucro líquido e custos '
                    'nas telas Relatórios Financeiros e Financeiro & Metas. '
                    'Salve as alterações para aplicá-las.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paneRodape() => _PaneRodapeWidget(host: this);

  // =================== MÍDIAS: UPLOAD BÁSICO ===================

  Future<void> _trocarLogo({required bool desktop}) async {
    String loja;
    try {
      loja = _activeStoreId();
    } catch (_) {
      _snack('Nenhuma loja ativa definida.', isError: true);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.single;
    final fileName = f.name.isNotEmpty ? f.name : 'logo.png';
    final ext = _extFromName(fileName);

    final storagePath =
        'lojas/$loja/midias/${desktop ? 'logo_desktop' : 'logo_mobile'}.$ext';

    setState(() => _salvando = true);

    try {
      UploadResult up;

      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) {
          throw StateError(
              'No web, FilePicker deve retornar bytes (withData: true).');
        }

        up = await _uploader.enqueueBytes(
          UploadBytesRequest(
            bytes: bytes,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      } else {
        up = await _uploader.enqueue(
          UploadRequest(
            platformFile: f,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      }

      setState(() {
        if (desktop) {
          _logoUrlDesktop = up.downloadUrl;
          _logoDesktopAlterado = true;
        } else {
          _logoUrlMobile = up.downloadUrl;
          _logoMobileAlterado = true;
        }
      });

      await _salvarRascunho(validar: false);
      _snack('Logo enviada com sucesso!');
    } catch (e) {
      _snack('Erro ao enviar logo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _removerLogo({required bool desktop}) async {
    await _syncAndValidateLojaAtiva();

    final urlAtual = desktop ? _logoUrlDesktop : _logoUrlMobile;

    setState(() {
      if (desktop) {
        _logoUrlDesktop = null;
        _logoDesktopAlterado = true;
      } else {
        _logoUrlMobile = null;
        _logoMobileAlterado = true;
      }
    });

    try {
      if (urlAtual != null && urlAtual.contains('firebasestorage.googleapis.com')) {
        final ref = FirebaseStorage.instance.refFromURL(urlAtual);
        await ref.delete();
      }
    } catch (_) {}

    await _salvarRascunho(validar: false);
    _snack('Logo removida.');
  }

  Future<void> _adicionarBanners({required bool desktop}) async {
    String loja;
    try {
      loja = _activeStoreId();
    } catch (_) {
      _snack('Nenhuma loja ativa definida.', isError: true);
      return;
    }

    final currentTotal = _bannersDesktop.length + _bannersMobile.length;
    final guard = LimitsGuard();
    final canAdd = await guard.canAddBanner(loja, currentTotalBanners: currentTotal);
    if (!canAdd) {
      final max = await guard.maxBanners(null);
      _snack('Limite de $max banners atingido. Remova algum ou faça upgrade.', isError: true);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    final maxBanners = await guard.maxBanners(null);
    final slotsLeft = maxBanners - currentTotal;
    final filesToUpload = slotsLeft <= 0
        ? <dynamic>[]
        : (result.files.length <= slotsLeft ? result.files : result.files.take(slotsLeft).toList());
    if (filesToUpload.isEmpty) {
      _snack('Limite de $maxBanners banners atingido.', isError: true);
      return;
    }
    if (filesToUpload.length < result.files.length) {
      _snack('Limite de $maxBanners banners: adicionando ${filesToUpload.length} de ${result.files.length}.', isError: false);
    }

    setState(() => _salvando = true);

    try {
      final uploadedUrls = <String>[];

      for (final f in filesToUpload) {
        final fileName = f.name.isNotEmpty ? f.name : 'banner.png';
        final ext = _extFromName(fileName);

        final ts = DateTime.now().millisecondsSinceEpoch;
        final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

        final storagePath =
            'lojas/$loja/midias/banners/${desktop ? 'desktop' : 'mobile'}/$ts-$safeName';

        UploadResult up;

        if (kIsWeb) {
          final bytes = f.bytes;
          if (bytes == null) continue;

          up = await _uploader.enqueueBytes(
            UploadBytesRequest(
              bytes: bytes,
              storagePath: storagePath,
              metadata: SettableMetadata(contentType: 'image/$ext'),
            ),
          );
        } else {
          up = await _uploader.enqueue(
            UploadRequest(
              platformFile: f,
              storagePath: storagePath,
              metadata: SettableMetadata(contentType: 'image/$ext'),
            ),
          );
        }

        uploadedUrls.add(up.downloadUrl);
      }

      setState(() {
        if (desktop) {
          _bannersDesktop.addAll(uploadedUrls);
          _bannersDesktopAlterados = true;
        } else {
          _bannersMobile.addAll(uploadedUrls);
          _bannersMobileAlterados = true;
        }
      });

      await _salvarRascunho(validar: false);
      _snack('Banners enviados: ${uploadedUrls.length}');
    } catch (e) {
      _snack('Erro ao enviar banners: $e', isError: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Importa imagem da galeria para layout minimalista (hero, categorias); retorna URL ou null.
  Future<String?> _pickAndUploadLayoutImage(String subpath) async {
    String loja;
    try {
      loja = _activeStoreId();
    } catch (_) {
      _snack('Nenhuma loja ativa definida.', isError: true);
      return null;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    try {
      final fileName = f.name.isNotEmpty ? f.name : 'image.png';
      final ext = _extFromName(fileName);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = 'lojas/$loja/midias/layout_minimal/$subpath-$ts-$safeName';
      UploadResult up;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return null;
        up = await _uploader.enqueueBytes(
          UploadBytesRequest(
            bytes: bytes,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      } else {
        up = await _uploader.enqueue(
          UploadRequest(
            platformFile: f,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      }
      _snack('Imagem importada.');
      return up.downloadUrl;
    } catch (e) {
      _snack('Erro ao importar imagem: $e', isError: true);
      return null;
    }
  }

  /// Importa imagem da galeria para banner de dica; retorna URL ou null.
  Future<String?> _pickAndUploadDicaBanner() async {
    String loja;
    try {
      loja = _activeStoreId();
    } catch (_) {
      _snack('Nenhuma loja ativa definida.', isError: true);
      return null;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    try {
      final fileName = f.name.isNotEmpty ? f.name : 'banner.png';
      final ext = _extFromName(fileName);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = 'lojas/$loja/midias/dicas/$ts-$safeName';
      UploadResult up;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return null;
        up = await _uploader.enqueueBytes(
          UploadBytesRequest(
            bytes: bytes,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      } else {
        up = await _uploader.enqueue(
          UploadRequest(
            platformFile: f,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      }
      _snack('Banner importado.');
      return up.downloadUrl;
    } catch (e) {
      _snack('Erro ao importar banner: $e', isError: true);
      return null;
    }
  }

  /// Importa imagem da galeria para o banner da página "Sobre a loja".
  Future<String?> _pickAndUploadSobreLojaBanner() async {
    String loja;
    try {
      loja = _activeStoreId();
    } catch (_) {
      _snack('Nenhuma loja ativa definida.', isError: true);
      return null;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    try {
      final fileName = f.name.isNotEmpty ? f.name : 'sobre-banner.png';
      final ext = _extFromName(fileName);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = 'lojas/$loja/midias/sobre_loja/$ts-$safeName';
      UploadResult up;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return null;
        up = await _uploader.enqueueBytes(
          UploadBytesRequest(
            bytes: bytes,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      } else {
        up = await _uploader.enqueue(
          UploadRequest(
            platformFile: f,
            storagePath: storagePath,
            metadata: SettableMetadata(contentType: 'image/$ext'),
          ),
        );
      }
      _snack('Banner da página Sobre importado.');
      return up.downloadUrl;
    } catch (e) {
      _snack('Erro ao importar banner da página Sobre: $e', isError: true);
      return null;
    }
  }

  Future<void> _removerBanner({required bool desktop, required String url}) async {
    await _syncAndValidateLojaAtiva();

    setState(() {
      if (desktop) {
        _bannersDesktop.remove(url);
        _bannersDesktopAlterados = true;
      } else {
        _bannersMobile.remove(url);
        _bannersMobileAlterados = true;
      }
    });

    try {
      if (url.contains('firebasestorage.googleapis.com')) {
        final ref = FirebaseStorage.instance.refFromURL(url);
        await ref.delete();
      }
    } catch (_) {}

    await _salvarRascunho(validar: false);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _uploader.dispose();
    _focusNomeLoja.dispose();
    _focusWaVendedor.dispose();
    _focusPedidoBaseUrl.dispose();
    _focusSacWhatsapp.dispose();
    _focusWhatsappRodape.dispose();
    _nomeCtrl.dispose();
    _slugCtrl.dispose();
    _linkCurtoCtrl.dispose();
    _subdominioMascaraCtrl.dispose();
    _subdominioDominioBaseCtrl.dispose();
    _waCtrl.dispose();
    _pedidoBaseCtrl.dispose();
    _catalogDomainOpSub?.cancel();
    _dominioCatalogoCtrl.dispose();
    _dLogoH.dispose();
    _dLogoW.dispose();
    _mLogoH.dispose();
    _mLogoW.dispose();
    _dBanH.dispose();
    _dBanW.dispose();
    _mBanH.dispose();
    _mBanW.dispose();
    _promoBarTextCtrl.dispose();
    _promoBarLinkCtrl.dispose();
    _minimalSearchPlaceholderCtrl.dispose();
    _heroBannerTitleCtrl.dispose();
    _heroBannerSubtitleCtrl.dispose();
    _heroBannerButtonTextCtrl.dispose();
    _heroBannerButtonLinkCtrl.dispose();
    _heroBannerImageCtrl.dispose();
    _heroBannerMobileImageCtrl.dispose();
    _heroBannerHeightCtrl.dispose();
    _heroBannerCardRadiusCtrl.dispose();
    _heroBannerOverlayCtrl.dispose();
    _heroBannerTitleSizeCtrl.dispose();
    _heroBannerSubtitleSizeCtrl.dispose();
    _heroBannerButtonSizeCtrl.dispose();
    _heroBannerButtonRadiusCtrl.dispose();
    _catImgModaCtrl.dispose();
    _catImgCalcadosCtrl.dispose();
    _catImgBolsasCtrl.dispose();
    _catImgCategoriaCtrl.dispose();
    _catImgCategoriaIdCtrl.dispose();
    _catImgUrlCtrl.dispose();
    _minimalBestSellersTitleCtrl.dispose();
    _minimalBestSellersCountCtrl.dispose();
    _melhorEnvioTokenCtrl.dispose();
    _correiosUserCtrl.dispose();
    _correiosSenhaCtrl.dispose();
    _frenetTokenCtrl.dispose();
    _freteNomeCtrl.dispose();
    _freteValorCtrl.dispose();
    _cupomNomeCtrl.dispose();
    _cupomValorCtrl.dispose();
    _quemSomosTituloCtrl.dispose();
    _quemSomosTextoCtrl.dispose();
    _sobreLojaTituloCtrl.dispose();
    _sobreLojaSubtituloCtrl.dispose();
    _sobreLojaBannerUrlCtrl.dispose();
    _sobreLojaIntroCtrl.dispose();
    _sobreLojaMissaoCtrl.dispose();
    _sobreLojaVisaoCtrl.dispose();
    _sobreLojaValoresCtrl.dispose();
    _sobreLojaDestaquesCtrl.dispose();
    _sobreLojaEnderecoCtrl.dispose();
    _sobreLojaHorarioCtrl.dispose();
    _sobreLojaEmailCtrl.dispose();
    _sacWhatsappCtrl.dispose();
    _sacEmailCtrl.dispose();
    _taxaCartaoCtrl.dispose();
    _taxaMEICtrl.dispose();
    _custosFixosCtrl.dispose();
    _custoEmbalagemCtrl.dispose();
    _instagramCtrl.dispose();
    _facebookCtrl.dispose();
    _tiktokCtrl.dispose();
    _telegramCtrl.dispose();
    _kwaiCtrl.dispose();
    _linkedinCtrl.dispose();
    _emailRodapeCtrl.dispose();
    _whatsappRodapeCtrl.dispose();
    _hubSearchCtrl.dispose();
    _sobreCtrl.dispose();
    _trocasCtrl.dispose();
    _loginCtrl.dispose();
    _razaoCtrl.dispose();
    _cnpjCtrl.dispose();
    super.dispose();
  }
}
