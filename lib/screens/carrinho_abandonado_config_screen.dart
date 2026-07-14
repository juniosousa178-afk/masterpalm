// M3.8 S2-R3 — configuração do tempo de abandono de carrinho.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/mp_components.dart';
import '../design_system/mp_tokens.dart';
import '../services/carrinho_abandonado_settings_service.dart';
import '../services/carrinho_abandonado_service.dart';
import '../services/loja_id_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CarrinhoAbandonadoConfigScreen extends StatefulWidget {
  const CarrinhoAbandonadoConfigScreen({super.key, this.lojaId});

  final String? lojaId;

  @override
  State<CarrinhoAbandonadoConfigScreen> createState() =>
      _CarrinhoAbandonadoConfigScreenState();
}

class _CarrinhoAbandonadoConfigScreenState
    extends State<CarrinhoAbandonadoConfigScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _lojaId;
  int _selectedMinutes = CarrinhoAbandonadoTimeLimits.defaultMinutes;
  bool _custom = false;
  final _customCtrl = TextEditingController();
  String? _error;
  CarrinhoAbandonadoConfig? _cfgMeta;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    var id = (widget.lojaId ?? '').trim();
    if (id.isEmpty) {
      id = ((await LojaIdService.get()) ?? '').trim();
    }
    if (id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Loja não identificada.';
      });
      return;
    }
    try {
      final cfg = await CarrinhoAbandonadoSettingsService.load(id);
      final mins = cfg.minutosAbandono;
      final isPreset =
          CarrinhoAbandonadoTimeLimits.presetMinutes.contains(mins);
      setState(() {
        _lojaId = id;
        _selectedMinutes = mins;
        _custom = !isPreset;
        if (_custom) _customCtrl.text = mins.toString();
        _cfgMeta = cfg;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar: $e';
      });
    }
  }

  Duration get _duration => Duration(minutes: _effectiveMinutes);

  int get _effectiveMinutes {
    if (_custom) {
      return int.tryParse(_customCtrl.text.trim()) ?? _selectedMinutes;
    }
    return _selectedMinutes;
  }

  Future<void> _salvar() async {
    final lojaId = _lojaId;
    if (lojaId == null || lojaId.isEmpty) return;
    final mins = _effectiveMinutes;
    final err = CarrinhoAbandonadoSettingsService.validateMinutes(mins);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CarrinhoAbandonadoSettingsService.save(
        lojaId: lojaId,
        minutosAbandono: mins,
        atualizadoPor: FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.uid,
      );
      if (!mounted) return;
      final cfg = await CarrinhoAbandonadoSettingsService.load(lojaId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração salva.')),
      );
      setState(() {
        _selectedMinutes = mins;
        _cfgMeta = cfg;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Erro ao salvar: $e';
      });
    }
  }

  Future<void> _restaurar() async {
    final lojaId = _lojaId;
    if (lojaId == null || lojaId.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _custom = false;
      _selectedMinutes = CarrinhoAbandonadoTimeLimits.defaultMinutes;
      _customCtrl.clear();
    });
    try {
      await CarrinhoAbandonadoSettingsService.restoreDefault(lojaId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Padrão restaurado (24 horas).')),
      );
      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Erro ao restaurar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MpColors.background,
      appBar: AppBar(
        title: const Text('Carrinhos abandonados'),
        backgroundColor: MpColors.surface,
        foregroundColor: MpColors.ink,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(MpSpacing.lg),
              children: [
                MpCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quando considerar um carrinho abandonado?',
                        style: MpType.title.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: MpSpacing.sm),
                      Text(
                        'Tempo atual: ${CarrinhoAbandonadoSettingsService.formatarDuracaoAbandono(_duration)}',
                        style: MpType.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: MpSpacing.sm),
                      Text(
                        CarrinhoAbandonadoSettingsService.exemploTexto(_duration),
                        style: MpType.body.copyWith(color: MpColors.inkMuted),
                      ),
                      if (_cfgMeta?.atualizadoEm != null ||
                          (_cfgMeta?.atualizadoPor?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: MpSpacing.md),
                        Text(
                          [
                            if (_cfgMeta?.atualizadoEm != null)
                              'Última alteração: ${DateFormat('dd/MM/yyyy HH:mm').format(_cfgMeta!.atualizadoEm!)}',
                            if (_cfgMeta?.atualizadoPor?.isNotEmpty ?? false)
                              'Por: ${_cfgMeta!.atualizadoPor}',
                          ].join(' · '),
                          style: MpType.caption,
                        ),
                      ],
                      const SizedBox(height: MpSpacing.lg),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p
                              in CarrinhoAbandonadoTimeLimits.presetMinutes)
                            ChoiceChip(
                              label: Text(
                                CarrinhoAbandonadoSettingsService
                                    .formatarDuracaoAbandono(
                                  Duration(minutes: p),
                                ),
                              ),
                              selected: !_custom && _selectedMinutes == p,
                              onSelected: (_) => setState(() {
                                _custom = false;
                                _selectedMinutes = p;
                                _error = null;
                              }),
                            ),
                          ChoiceChip(
                            label: const Text('Personalizado'),
                            selected: _custom,
                            onSelected: (_) => setState(() {
                              _custom = true;
                              if (_customCtrl.text.isEmpty) {
                                _customCtrl.text = '$_selectedMinutes';
                              }
                              _error = null;
                            }),
                          ),
                        ],
                      ),
                      if (_custom) ...[
                        const SizedBox(height: MpSpacing.md),
                        TextField(
                          controller: _customCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Minutos',
                            helperText: 'Entre 15 minutos e 30 dias',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() => _error = null),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: MpSpacing.md),
                        Text(
                          _error!,
                          style: MpType.caption.copyWith(color: MpColors.danger),
                        ),
                      ],
                      const SizedBox(height: MpSpacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _restaurar,
                              child: const Text('Restaurar padrão'),
                            ),
                          ),
                          const SizedBox(width: MpSpacing.sm),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _salvar,
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Salvar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MpSpacing.md),
                MpCard(
                  child: Text(
                    'Status como recuperado, virou pedido ou virou venda não voltam '
                    'a abandonado só pela regra de tempo. O valor se aplica à '
                    'lista, contagem da Home e score de recuperação.',
                    style: MpType.caption,
                  ),
                ),
              ],
            ),
    );
  }
}
