// Assistente de IA na Ajuda: tutorial passo a passo por tela do MasterPalm.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_loja_service.dart';
import '../services/ia_uso_limite_service.dart';
import '../services/loja_id_service.dart';
import '../themes/app_colors.dart';

/// Opção exibida na lista; [nomeParaIa] é o contexto enviado ao backend.
class AjudaTelaTutorialOpcao {
  const AjudaTelaTutorialOpcao({
    required this.titulo,
    required this.nomeParaIa,
    required this.icon,
  });

  final String titulo;
  final String nomeParaIa;
  final IconData icon;
}

/// Telas alinhadas à Ajuda + áreas comuns do app (inclui extras fora dos cards).
List<AjudaTelaTutorialOpcao> get ajudaTutorialOpcoes => const [
      AjudaTelaTutorialOpcao(
        titulo: 'Precificação',
        nomeParaIa: 'Precificação (cálculo de preço de venda, markup, importação Excel)',
        icon: Icons.calculate,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Estoque',
        nomeParaIa: 'Estoque (cadastro de produtos, quantidade, custo e preço)',
        icon: Icons.inventory_2,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Vendas',
        nomeParaIa: 'Vendas (PDV, cliente, formas de pagamento, edição de venda)',
        icon: Icons.point_of_sale,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Financeiro e metas',
        nomeParaIa: 'Painel financeiro e metas (totais por forma de pagamento, período)',
        icon: Icons.trending_up,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Clientes',
        nomeParaIa: 'Clientes (cadastro e histórico)',
        icon: Icons.people,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Fornecedores',
        nomeParaIa: 'Fornecedores',
        icon: Icons.local_shipping,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Catálogo / loja',
        nomeParaIa: 'Catálogo e loja online (como o cliente vê, categorias, aparência)',
        icon: Icons.storefront,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Configuração do catálogo',
        nomeParaIa:
            'Configuração da loja e catálogo online no MasterPalm (hub de configuração com menu lateral por módulos). '
            'O tutorial deve ter duas partes claras: '
            '(1) VISÃO GERAL — para que serve o hub, fluxo recomendado (da identidade da loja até publicar no site), '
            'o que muda no catálogo público após salvar/publicar, e atalho para fretes quando existir. '
            '(2) POR MÓDULOS — explicar cada painel separadamente, com o mesmo nome do app: '
            'Identidade e Contato (nome, WhatsApp, dados básicos); '
            'Mídias e Banners (logo e banners desktop/mobile); '
            'Tema e Cores (cores do catálogo e checkout); '
            'Layout dos cards (colunas, sombras, bordas); '
            'Menu e Páginas (navegação do catálogo, SAC); '
            'Dicas e informações (cuidados, garantias); '
            'Rodapé e Links (redes, políticas); '
            'Taxas Financeiras (vínculo com relatórios/metas quando aplicável); '
            'Publicar catálogo (enviar alterações ao site). '
            'Deixe explícito que regras de frete e cupons de desconto são em outra tela (Fretes e cupons), não dentro destes módulos.',
        icon: Icons.tune,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Pedidos',
        nomeParaIa: 'Pedidos do catálogo e canais',
        icon: Icons.shopping_cart,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Metas e comissões',
        nomeParaIa: 'Metas e comissões de vendedores',
        icon: Icons.emoji_events,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Relatórios financeiros',
        nomeParaIa: 'Relatórios financeiros (filtros, líquido, por vendedor)',
        icon: Icons.bar_chart,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Campanhas e sorteios',
        nomeParaIa:
            'Campanhas e sorteios (campanhas com números da sorte, regras por valor de compra, data; e Roleta da sorte com prêmios e valor mínimo)',
        icon: Icons.card_giftcard,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Fretes e cupons',
        nomeParaIa: 'Fretes e cupons de desconto (checkout)',
        icon: Icons.local_shipping_outlined,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Configurar pagamentos',
        nomeParaIa: 'Configurar pagamentos (Pix, cartão, Mercado Pago)',
        icon: Icons.payments,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Canais Meta',
        nomeParaIa: 'Canais Meta (WhatsApp, Instagram, Messenger)',
        icon: Icons.chat,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Vendedores',
        nomeParaIa: 'Vendedores (cadastro, permissões, vínculo em vendas)',
        icon: Icons.badge,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Marketplace / ERP',
        nomeParaIa: 'Marketplace e integrações ERP',
        icon: Icons.store_mall_directory,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Notas fiscais',
        nomeParaIa: 'Notas fiscais',
        icon: Icons.receipt_long,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Ferramentas (menu Dados)',
        nomeParaIa:
            'Ferramentas do sistema: sincronizar Firestore, backup, consolidar loja, planos, importar Firestore',
        icon: Icons.build,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Contas a receber',
        nomeParaIa: 'Contas a receber (parcelas e recebimentos)',
        icon: Icons.account_balance_wallet,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Carrinhos abandonados',
        nomeParaIa: 'Carrinhos abandonados no catálogo',
        icon: Icons.remove_shopping_cart,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Movimentação de estoque',
        nomeParaIa: 'Histórico de movimentação de estoque',
        icon: Icons.swap_vert,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Subcategorias',
        nomeParaIa: 'Subcategorias de produtos',
        icon: Icons.category,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Dicas com IA',
        nomeParaIa: 'Tela Dicas com IA (chat de marketing e ideias para a loja)',
        icon: Icons.auto_awesome,
      ),
      AjudaTelaTutorialOpcao(
        titulo: 'Catálogo público (cliente)',
        nomeParaIa: 'Experiência do cliente no catálogo público (navegar, carrinho, checkout)',
        icon: Icons.public,
      ),
    ];

class AjudaIaTutorialScreen extends StatefulWidget {
  const AjudaIaTutorialScreen({super.key});

  @override
  State<AjudaIaTutorialScreen> createState() => _AjudaIaTutorialScreenState();
}

class _AjudaIaTutorialScreenState extends State<AjudaIaTutorialScreen> {
  final TextEditingController _perguntaCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<Map<String, String>> _historico = [];
  bool _enviando = false;
  int _cooldownRestante = 0;
  Timer? _cooldownTimer;
  int _usoPerguntas = 0;
  String? _telaNomeIa;
  String? _telaTitulo;
  bool _mostrarLista = true;

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
    _atualizarUso();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _perguntaCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _escolherTela(AjudaTelaTutorialOpcao op) async {
    setState(() {
      _telaNomeIa = op.nomeParaIa;
      _telaTitulo = op.titulo;
      _mostrarLista = false;
      _historico.clear();
      _enviando = true;
    });
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _mostrarLista = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      return;
    }
    try {
      final resposta = await AiLojaService.chatAjudaTutorial(
        nomeTela: op.nomeParaIa,
      );
      if (!mounted) return;
      setState(() {
        _historico.add({'role': 'model', 'content': resposta});
        _enviando = false;
      });
      IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
      _atualizarUso();
      _iniciarCooldown();
      _scrollFim();
    } catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _mostrarLista = true;
          _telaNomeIa = null;
          _telaTitulo = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AiLojaService.messageForUser(e))),
        );
      }
    }
  }

  Future<void> _enviarPergunta() async {
    final texto = _perguntaCtrl.text.trim();
    if (texto.isEmpty || _enviando || _cooldownRestante > 0 || _telaNomeIa == null) return;
    final lojaId = await LojaIdService.get();
    if (!await IaUsoLimiteService.canUse(lojaId, TipoUsoIa.perguntas)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(IaUsoLimiteService.messageLimitExcedido(TipoUsoIa.perguntas)),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      return;
    }
    _perguntaCtrl.clear();
    setState(() {
      _historico.add({'role': 'user', 'content': texto});
      _enviando = true;
    });
    _scrollFim();
    try {
      final resposta = await AiLojaService.chatAjudaTutorial(
        nomeTela: _telaNomeIa!,
        mensagem: texto,
        historico: _historico.length > 1 ? _historico.sublist(0, _historico.length - 1) : null,
      );
      if (mounted) {
        setState(() {
          _historico.add({'role': 'model', 'content': resposta});
          _enviando = false;
        });
        IaUsoLimiteService.recordUse(lojaId, TipoUsoIa.perguntas);
        _atualizarUso();
        _iniciarCooldown();
        _scrollFim();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historico.add({
            'role': 'model',
            'content': 'Não consegui responder agora.\n\n${AiLojaService.messageForUser(e)}',
          });
          _enviando = false;
        });
        _iniciarCooldown();
        _scrollFim();
      }
    }
  }

  void _trocarTela() {
    setState(() {
      _mostrarLista = true;
      _telaNomeIa = null;
      _telaTitulo = null;
      _historico.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? cs.primary : AppColors.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? cs.primary : AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Assistente de tutoriais'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Perguntas: $_usoPerguntas/${IaUsoLimiteService.limiteDe(TipoUsoIa.perguntas)}',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
              ),
            ),
          ),
        ],
      ),
      body: _mostrarLista ? _buildLista(primary, cs) : _buildChat(theme, primary, cs),
    );
  }

  Widget _buildLista(Color primary, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: primary.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: primary, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Escolha uma tela',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'A IA gera um resumo, passo a passo, exemplos e dicas. Depois você pode fazer perguntas sobre a mesma tela.',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...ajudaTutorialOpcoes.map((op) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _escolherTela(op),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(op.icon, color: primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          op.titulo,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildChat(ThemeData theme, Color primary, ColorScheme cs) {
    return Column(
      children: [
        Material(
          color: cs.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _telaTitulo ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Toque para escolher outra tela',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _trocarTela,
                  icon: const Icon(Icons.list_alt, size: 20),
                  label: const Text('Trocar'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _enviando && _historico.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: primary),
                      const SizedBox(height: 16),
                      Text(
                        'Gerando tutorial…',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _historico.length + (_enviando && _historico.isNotEmpty ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _historico.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: primary.withValues(alpha: 0.2),
                              child: Icon(Icons.smart_toy, size: 20, color: primary),
                            ),
                            const SizedBox(width: 12),
                            const SizedBox(
                              width: 22,
                              height: 22,
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
                          if (!isUser) ...[
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: primary.withValues(alpha: 0.2),
                              child: Icon(Icons.smart_toy, size: 20, color: primary),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? cs.primaryContainer.withValues(alpha: 0.65)
                                    : cs.surfaceContainerHighest,
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
                                        icon: Icon(Icons.copy, size: 18, color: cs.onSurfaceVariant),
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
                          if (isUser) ...[
                            const SizedBox(width: 12),
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.person, size: 20, color: cs.onPrimaryContainer),
                            ),
                          ],
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
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2)),
            ],
          ),
          child: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _perguntaCtrl,
                    decoration: InputDecoration(
                      hintText: 'Pergunte algo sobre esta tela…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviarPergunta(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: (_enviando || _cooldownRestante > 0) ? null : _enviarPergunta,
                  style: IconButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
                  icon: _cooldownRestante > 0
                      ? Text('${_cooldownRestante}s', style: const TextStyle(fontSize: 12))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
