// M3.8 S2-R4 — barra de pesquisa global da Home.

import 'package:flutter/material.dart';

import '../core/app_module_definition.dart';
import '../core/home_module_registry.dart';
import '../core/home_module_search.dart';
import '../design_system/mp_tokens.dart';

class HomeGlobalSearchBar extends StatefulWidget {
  const HomeGlobalSearchBar({
    super.key,
    required this.access,
    required this.onOpenModule,
  });

  final HomeModuleAccessContext access;
  final void Function(AppModuleDefinition module, {required bool planLocked})
      onOpenModule;

  @override
  State<HomeGlobalSearchBar> createState() => _HomeGlobalSearchBarState();
}

class _HomeGlobalSearchBarState extends State<HomeGlobalSearchBar> {
  final _ctrl = TextEditingController();
  List<AppModuleDefinition> _results = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {
      _results = HomeModuleSearch.search(v, access: widget.access);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'O que deseja abrir?',
            prefixIcon: const Icon(Icons.search, color: MpColors.inkMuted),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _ctrl.clear();
                      _onChanged('');
                    },
                  ),
            filled: true,
            fillColor: MpColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MpRadius.lg),
              borderSide: const BorderSide(color: MpColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MpRadius.lg),
              borderSide: const BorderSide(color: MpColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MpRadius.lg),
              borderSide:
                  const BorderSide(color: MpColors.primary, width: 1.4),
            ),
          ),
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: MpSpacing.sm),
          Material(
            color: MpColors.surface,
            elevation: 2,
            shadowColor: MpColors.ink.withOpacity(0.08),
            borderRadius: BorderRadius.circular(MpRadius.md),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _results.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: MpColors.border),
              itemBuilder: (context, i) {
                final m = _results[i];
                final locked =
                    HomeModuleRegistry.isPlanLocked(m, widget.access);
                return ListTile(
                  dense: true,
                  leading: Icon(m.icon, color: m.effectiveAccent),
                  title: Text(m.title, style: MpType.body),
                  subtitle: Text(
                    '${m.category.title}${m.subtitle != null ? ' · ${m.subtitle}' : ''}',
                    style: MpType.caption,
                  ),
                  trailing: locked
                      ? const Icon(Icons.lock_outline,
                          size: 16, color: MpColors.warning)
                      : null,
                  onTap: () {
                    widget.onOpenModule(m, planLocked: locked);
                    _ctrl.clear();
                    _onChanged('');
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
