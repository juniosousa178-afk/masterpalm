// lib/screens/dicas_ia_screen.dart
// Tela de chat com IA para dicas e ideias para a loja.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';

class DicasIaScreen extends StatefulWidget {
  const DicasIaScreen({super.key});

  @override
  State<DicasIaScreen> createState() => _DicasIaScreenState();
}

class _DicasIaScreenState extends State<DicasIaScreen> {
  final TextEditingController _mensagemCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, String>> _historico = [];
  bool _enviando = false;
  int _cooldownRestante = 0;
  Timer? _cooldownTimer;
  String _preferirModelo = 'gemini';
  int _usoPerguntas = 0;

  void _iniciarCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownRestante = 10);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _cooldownRestante = (_cooldownRestante - 1).clamp(0, 10);
      });
      if (_cooldownRestante <= 0) _cooldownTimer?.cancel();
    });
  }

  Future<void> _atualizarUso() async {
    final lojaId = await LojaIdService.get();
    final uso = await IaUsoLimiteService.getUsoAtual(lojaId);
    if (mounted) setState(() => _usoPerguntas = uso[TipoUsoIa.perguntas] ?? 0);
  }

  @override
  void initState() {
    super.initState();
    AiLojaService.getPreferirModelo().then((v) {
      if (mounted) setState(() => _preferirModelo = v);
    });
    _atualizarUso();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _mensagemCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _mensagemCtrl.text.trim();
    if (texto.isEmpty || _enviando || _cooldownRestante > 0) return;
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)), backgroundColor: Colors.orange.shade700),
        );
      }
      return;
    }
    _mensagemCtrl.clear();
    setState(() {
      _historico.add({'role': 'user', 'content': texto});
      _enviando = true;
    });
    _scrollarFim();
    try {
      final resposta = await AiLojaService.chatDicas(
        mensagem: texto,
        historico: _historico.length > 1
            ? _historico.sublist(0, _historico.length - 1)
            : null,
      );
      if (mounted) {
        setState(() {
          _historico.add({'role': 'model', 'content': resposta});
          _enviando = false;
        });
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        _atualizarUso();
        _iniciarCooldown();
        _scrollarFim();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historico.add({
            'role': 'model',
            'content': 'Desculpe, não consegui responder agora.\n\n${AiLojaService.messageForUser(e)}',
          });
          _enviando = false;
        });
        _iniciarCooldown();
        _scrollarFim();
      }
    }
  }

  void _scrollarFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber),
            SizedBox(width: 8),
            Text('Dicas com IA'),
          ],
        ),
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Perguntas: $_usoPerguntas/15',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade300),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings),
            tooltip: 'Modelo de IA',
            onSelected: (v) async {
              await AiLojaService.setPreferirModelo(v);
              if (mounted) setState(() => _preferirModelo = v);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'gemini',
                child: Row(
                  children: [
                    if (_preferirModelo == 'gemini') const Icon(Icons.check, color: Colors.green, size: 20),
                    if (_preferirModelo == 'gemini') const SizedBox(width: 8),
                    const Text('Gemini (grátis) – Padrão'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _historico.isEmpty && !_enviando
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 64, color: Colors.amber.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'Pergunte dicas e ideias para sua loja',
                            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ex: "Como divulgar meu catálogo?", "Dicas para vender mais no Instagram", "Como organizar o estoque?"',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _historico.length + (_enviando ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _historico.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.amber.shade100,
                                child: Icon(Icons.auto_awesome, size: 20, color: Colors.amber.shade800),
                              ),
                              const SizedBox(width: 12),
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          ),
                        );
                      }
                      final msg = _historico[i];
                      final isUser = msg['role'] == 'user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isUser)
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.amber.shade100,
                                child: Icon(Icons.auto_awesome, size: 20, color: Colors.amber.shade800),
                              ),
                            if (!isUser) const SizedBox(width: 12),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? (theme.colorScheme.primaryContainer.withValues(alpha:0.6))
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      msg['content'] ?? '',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    if (!isUser) ...[
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                          tooltip: 'Copiar',
                                          icon: Icon(Icons.copy, size: 18, color: Colors.grey.shade600),
                                          onPressed: () {
                                            final t = msg['content'] ?? '';
                                            Clipboard.setData(ClipboardData(text: t));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Texto copiado'),
                                                behavior: SnackBarBehavior.floating,
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (isUser) const SizedBox(width: 12),
                            if (isUser)
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Icon(Icons.person, size: 20, color: theme.colorScheme.onPrimaryContainer),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mensagemCtrl,
                      decoration: InputDecoration(
                        hintText: 'Pergunte dicas para sua loja...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (_enviando || _cooldownRestante > 0) ? null : _enviar,
                    icon: _cooldownRestante > 0
                        ? Text('${_cooldownRestante}s', style: const TextStyle(fontSize: 12))
                        : const Icon(Icons.send),
                    tooltip: _cooldownRestante > 0 ? 'Aguarde ${_cooldownRestante}s' : 'Enviar',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

