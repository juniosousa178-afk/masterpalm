// lib/widgets/roleta_web_widget_v3.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/logger.dart';
import 'package:uuid/uuid.dart';

/// Widget da Roleta V3 - 100% Sincronizado com RoletaSorteConfigScreen
/// - Lê de lojas/{lojaId}/config/roleta_sorte
/// - Implementa sistema de frequência (a cada X vendas, 1 sai premiada)
/// - Implementa controle de quantidade máxima por prêmio
/// - Sorteia prêmios de forma inteligente
class RoletaWebWidgetV3 extends StatefulWidget {
  final String lojaId;
  final double totalCarrinho;
  final String? clienteEmail;
  final VoidCallback? onCupomGerado;
  final Function(String codigo, double desconto)? onCupomGeradoComDados;
  final Function(String codigo, double desconto, String? descricao)? onPremioGanho;

  const RoletaWebWidgetV3({
    super.key,
    required this.lojaId,
    required this.totalCarrinho,
    this.clienteEmail,
    this.onCupomGerado,
    this.onCupomGeradoComDados,
    this.onPremioGanho,
  });

  @override
  State<RoletaWebWidgetV3> createState() => _RoletaWebWidgetV3State();
}

class _RoletaWebWidgetV3State extends State<RoletaWebWidgetV3>
    with SingleTickerProviderStateMixin {
  bool _carregando = true;
  bool _girando = false;
  bool _ativa = false;

  double _valorMinimo = 0;
  int _frequenciaPremio = 10; // A cada X vendas
  int _vendasDesdePremio = 0; // Contador atual
  // ignore: unused_field - usado para estatísticas futuras
  int _totalVendas = 0; // Total histórico

  List<Map<String, dynamic>> _premios = [];

  late AnimationController _controller;
  double _anguloFinal = 0;
  // ignore: unused_field - índice do prêmio para referência futura
  int _premioIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _carregarConfig();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    logD('🎰 [ROLETA-V3] Carregando config para loja: ${widget.lojaId}');

    try {
      final doc = await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('config')
          .doc('roleta_sorte')
          .get();

      if (!doc.exists || doc.data() == null) {
        logW('⚠️ [ROLETA-V3] Config não encontrada');
        if (!mounted) return;
        setState(() => _carregando = false);
        return;
      }

      final data = doc.data()!;
      logD('✅ [ROLETA-V3] Config carregada: ${data.keys}');

      if (!mounted) return;
      setState(() {
        _ativa = data['ativa'] == true;
        _valorMinimo = (data['valorMinimo'] as num?)?.toDouble() ?? 0.0;
        _frequenciaPremio = data['frequenciaPremio'] as int? ?? 10;
        _vendasDesdePremio = data['vendasDesdePremio'] as int? ?? 0;
        _totalVendas = data['totalVendas'] as int? ?? 0;

        // Carregar prêmios (lista completa para o desenho da roleta; índices devem bater com o sorteio)
        final premiosRaw = data['premios'] as List?;
        if (premiosRaw != null) {
          _premios = premiosRaw
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
        }

        _carregando = false;
      });

      logD('   Ativa: $_ativa');
      logD('   Valor mínimo: R\$ $_valorMinimo');
      logD('   Frequência: $_frequenciaPremio vendas');
      logD('   Vendas desde prêmio: $_vendasDesdePremio');
      logD('   Prêmios ativos: ${_premios.length}');
    } catch (e, st) {
      logE('❌ [ROLETA-V3] Erro ao carregar config (type=${e.runtimeType})', error: e, st: st);
      if (!mounted) return;
      setState(() => _carregando = false);
    }
  }

  bool get _podeGirar {
    if (!_ativa) return false;
    if (widget.totalCarrinho < _valorMinimo) return false;
    if (_premios.isEmpty) return false;
    if (!_premios.any((p) => p['ativo'] == true)) return false;
    return true;
  }

  Future<void> _girarRoleta() async {
    if (!_podeGirar) {
      _mostrarMensagem(
        'Valor mínimo não atingido',
        'Adicione mais R\$ ${(_valorMinimo - widget.totalCarrinho).toStringAsFixed(2)} '
        'ao carrinho para girar a roleta!',
        Colors.orange,
      );
      return;
    }

    setState(() {
      _girando = true;
    });

    // ✅ TRANSAÇÃO ATÔMICA: ler, validar ganho, atualizar (evita corrida multi-usuário)
    final resultado = await _executarGiroRoletaTransacao();
    if (resultado == null) {
      if (mounted) setState(() => _girando = false);
      return;
    }

    final ganhou = resultado.$1;
    final premioIndex = resultado.$2;
    final premiosParaRoleta = resultado.$3;

    if (premiosParaRoleta.isEmpty) {
      if (mounted) setState(() => _girando = false);
      return;
    }

    setState(() {
      _premios = premiosParaRoleta;
      _premioIndex = premioIndex;
    });

    // ✅ Calcular ângulo para parar EXATAMENTE no prêmio sorteado (cupom, brinde, tente novamente, etc.)
    // Fatia i no _RoletaPainter: startAngle = i * anguloPorFatia - pi/2 (topo = -pi/2).
    // Centro da fatia premioIndex: (premioIndex + 0.5) * anguloPorFatia - pi/2.
    // Transform.rotate(angle R) gira no sentido horário: ponto θ vai para θ - R. Queremos centro no topo:
    // (premioIndex + 0.5) * anguloPorFatia - pi/2 - R = -pi/2  =>  R = (premioIndex + 0.5) * anguloPorFatia
    final numFatias = premiosParaRoleta.length;
    final anguloPorFatia = 2 * pi / numFatias;
    final anguloParaCentroPremio = (premioIndex + 0.5) * anguloPorFatia;
    final giros = 4 + Random().nextDouble() * 2;

    setState(() {
      _anguloFinal = (giros * 2 * pi) + anguloParaCentroPremio;
    });

    await _controller.forward(from: 0);

    final premio = premiosParaRoleta[premioIndex];
    final tipoPremio = premio['tipo'] ?? '';

    setState(() => _girando = false);

    // ✅ PROCESSAR RESULTADO (contadores já atualizados na transação)
    if (ganhou && tipoPremio != 'nenhum') {
      _processarPremio(premio);
    } else {
      _mostrarSemPremio();
    }

    widget.onCupomGerado?.call();
  }

  /// Executa giro da roleta em transação atômica (evita dois usuários ganharem simultaneamente).
  /// Retorna (ganhou, premioIndex, listaCompletaPremios) ou null se erro.
  Future<(bool, int, List<Map<String, dynamic>>)?> _executarGiroRoletaTransacao() async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('config')
          .doc('roleta_sorte');

      return await FirebaseFirestore.instance.runTransaction<(bool, int, List<Map<String, dynamic>>)>((transaction) async {
        final snap = await transaction.get(docRef);
        if (!snap.exists || snap.data() == null) return (false, 0, <Map<String, dynamic>>[]);

        final data = snap.data()!;
        int vendasDesdePremio = (data['vendasDesdePremio'] as num?)?.toInt() ?? 0;
        final frequenciaPremio = (data['frequenciaPremio'] as int?) ?? 10;
        final premiosRaw = data['premios'] as List?;
        if (premiosRaw == null || premiosRaw.isEmpty) return (false, 0, <Map<String, dynamic>>[]);

        final premios = premiosRaw.map((p) => Map<String, dynamic>.from(p as Map)).toList();
        final premiosAtivos = premios.where((p) => p['ativo'] == true).toList();
        if (premiosAtivos.isEmpty) return (false, 0, <Map<String, dynamic>>[]);

        final ganhou = vendasDesdePremio >= frequenciaPremio - 1;

        int premioIndex;
        if (ganhou) {
          final disponiveis = <int>[];
          for (var i = 0; i < premios.length; i++) {
            if (premios[i]['ativo'] != true) continue;
            final tipo = premios[i]['tipo'] ?? '';
            if (tipo == 'nenhum') continue;
            final qtdMax = (premios[i]['quantidadeMaxima'] as num?)?.toInt() ?? 0;
            final qtdUsada = (premios[i]['quantidadeUsada'] as num?)?.toInt() ?? 0;
            if (qtdMax == 0 || qtdUsada < qtdMax) {
              disponiveis.add(i);
            }
          }
          premioIndex = disponiveis.isNotEmpty ? disponiveis.first : 0;
          premios[premioIndex]['quantidadeUsada'] = ((premios[premioIndex]['quantidadeUsada'] as num?)?.toInt() ?? 0) + 1;
        } else {
          premioIndex = 0;
          for (var i = 0; i < premios.length; i++) {
            if ((premios[i]['tipo'] ?? '') == 'nenhum') {
              premioIndex = i;
              break;
            }
          }
        }

        final novaVendasDesdePremio = ganhou ? 0 : vendasDesdePremio + 1;
        final totalVendas = ((data['totalVendas'] as num?)?.toInt() ?? 0) + 1;

        transaction.update(docRef, {
          'totalVendas': totalVendas,
          'vendasDesdePremio': novaVendasDesdePremio,
          'premios': premios,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() {
            _totalVendas = totalVendas;
            _vendasDesdePremio = novaVendasDesdePremio;
            _premios = premios;
          });
        }

        return (ganhou, premioIndex, List<Map<String, dynamic>>.from(premios));
      });
    } catch (e, st) {
      logE('❌ [ROLETA-V3] Erro na transação (type=${e.runtimeType})', error: e, st: st);
      if (mounted) {
        _mostrarMensagem('Erro', 'Não foi possível girar a roleta. Tente novamente.', Colors.red);
      }
      return null;
    }
  }

  /// ✅ PROCESSA O PRÊMIO GANHO
  void _processarPremio(Map<String, dynamic> premio) {
    final tipo = premio['tipo'] ?? '';
    final label = premio['label'] ?? '';
    final valor = (premio['valor'] as num?)?.toDouble() ?? 0.0;
    final diasValidade = premio['diasValidade'] as int? ?? 30;
    final dataExpiracao = DateTime.now().add(Duration(days: diasValidade));

    logD('🎉 [ROLETA-V3] Prêmio ganho: $label (tipo: $tipo, validade: $diasValidade dias)');

    if (tipo == 'frete_gratis') {
      // ✅ Frete grátis: aplica na compra ATUAL
      _mostrarPremioEspecial(
        titulo: '🎉 FRETE GRÁTIS!',
        mensagem: 'Parabéns! Você ganhou frete grátis NESTA COMPRA!\n\nFinalize a compra para garantir seu prêmio.',
        cor: const Color(0xFF4CAF50),
        dataExpiracao: null, // Não tem validade, é para uso imediato
      );
      widget.onPremioGanho?.call('FRETE_GRATIS', 100.0, 'Frete Grátis');
      widget.onCupomGeradoComDados?.call('FRETE_GRATIS', 100.0);
    } else if (tipo == 'brinde') {
      // ✅ Brinde: entregue na compra ATUAL
      _mostrarPremioEspecial(
        titulo: '🎁 VOCÊ GANHOU!',
        mensagem: 'Parabéns! Você ganhou:\n\n$label\n\nSerá entregue junto com seu pedido!',
        cor: const Color(0xFFFF6B6B),
        dataExpiracao: null, // Brinde não tem validade
      );
      widget.onPremioGanho?.call('BRINDE', 0.0, label);
      widget.onCupomGeradoComDados?.call('BRINDE', 0.0);
    } else if (tipo == 'desconto') {
      // ✅ Desconto: cupom para PRÓXIMA compra com validade
      final codigo = _gerarCodigoCupom();
      _mostrarPremioEspecial(
        titulo: '🎉 CUPOM DE DESCONTO!',
        mensagem: 'Parabéns! Você ganhou $label!\n\nCódigo: $codigo\n\nVálido para sua PRÓXIMA compra até ${_formatarData(dataExpiracao)}',
        cor: const Color(0xFF9C27B0),
        dataExpiracao: dataExpiracao,
        codigoCupom: codigo,
      );
      widget.onPremioGanho?.call(codigo, valor, label);
      widget.onCupomGeradoComDados?.call(codigo, valor);

      // ✅ Cupom só terá validade após finalização e confirmação da compra.
      // Salvamento no perfil ocorre em CatalogoVendaService.registrarVendaCatalogo.
    }
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  void _mostrarSemPremio() {
    _mostrarPremioEspecial(
      titulo: '😔 Não foi dessa vez!',
      mensagem: 'Infelizmente você não ganhou nenhum prêmio desta vez.\n\nMas não desista, volte sempre!',
      cor: const Color(0xFFFF9800),
    );
  }

  /// Código único para evitar colisão com milhares de usuários simultâneos
  String _gerarCodigoCupom() {
    final uuid = const Uuid().v4().replaceAll('-', '').substring(0, 8).toUpperCase();
    return uuid;
  }

  void _mostrarPremioEspecial({
    required String titulo,
    required String mensagem,
    required Color cor,
    DateTime? dataExpiracao,
    String? codigoCupom,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cor.withValues(alpha:0.8), cor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha:0.3),
                      blurRadius: 15,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.emoji_events,
                  size: 60,
                  color: cor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                mensagem,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (codigoCupom != null && codigoCupom.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha:0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, color: Colors.white.withValues(alpha:0.95), size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Este cupom será salvo no seu perfil e tem validade de uso único. Consulte a seção de cupons no perfil para utilizá-lo na sua próxima compra.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: cor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'ENTENDI!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  void _mostrarMensagem(String titulo, String mensagem, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(mensagem),
          ],
        ),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_ativa || _premios.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha:0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
                Color(0xFF0F1729),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha:0.3),
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Título (FittedBox evita overflow em telas estreitas)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFE31E24),
                          Color(0xFFFF6B6B),
                          Color(0xFFE31E24),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE31E24).withValues(alpha:0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 28),
                        SizedBox(width: 12),
                        Text(
                          'GIRE E GANHE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 28),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Roleta com seta fixa (tamanho reduzido)
              SizedBox(
                height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Roleta girando
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (_, child) {
                        final value = Curves.easeOut.transform(_controller.value);
                        final angulo = value * _anguloFinal;
                        return Transform.rotate(angle: angulo, child: child);
                      },
                      child: CustomPaint(
                        painter: _RoletaPainter(_premios),
                        child: const SizedBox(width: 240, height: 240),
                      ),
                    ),
                    // Seta fixa no topo
                    Positioned(
                      top: -5,
                      child: CustomPaint(
                        painter: _SetaPainter(),
                        child: const SizedBox(width: 50, height: 50),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Botão girar
              SizedBox(
                width: double.infinity,
                height: 65,
                child: ElevatedButton(
                  onPressed: _girando || !_podeGirar ? null : _girarRoleta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _girando || !_podeGirar
                        ? Colors.grey.shade800
                        : const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                    elevation: 8,
                  ),
                  child: _girando
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white),
                            ),
                            SizedBox(width: 16),
                            Text(
                              'GIRANDO...',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'GIRAR A ROLETA!',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),

              // Info adicional
              if (!_podeGirar && widget.totalCarrinho > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart, color: Colors.orange, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Faltam R\$ ${(_valorMinimo - widget.totalCarrinho).toStringAsFixed(2)} para girar!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Painter da roleta
class _RoletaPainter extends CustomPainter {
  final List<Map<String, dynamic>> premios;

  _RoletaPainter(this.premios);

  @override
  void paint(Canvas canvas, Size size) {
    if (premios.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final anguloPorFatia = 2 * pi / premios.length;

    final coresBase = [
      const Color(0xFFE31E24),
      const Color(0xFFFFC107),
    ];

    // Desenhar fatias
    for (int i = 0; i < premios.length; i++) {
      final startAngle = i * anguloPorFatia - pi / 2;
      final sweepAngle = anguloPorFatia;
      final corBase = coresBase[i % coresBase.length];

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [corBase.withValues(alpha:0.9), corBase, corBase.withValues(alpha:0.8)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // Borda branca
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      // Texto do prêmio
      final label = premios[i]['label'] ?? '';
      final textAngle = startAngle + sweepAngle / 2;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(textAngle + pi / 2);

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: premios.length > 8 ? 11 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout(maxWidth: radius * 0.6);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -radius * 0.65));

      canvas.restore();
    }

    // Círculo central
    final centerPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF1A1A1A), Color(0xFF000000)],
      ).createShader(Rect.fromCircle(center: center, radius: 45))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 45, centerPaint);

    // Borda dourada do centro
    final centerBorderPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(center, 45, centerBorderPaint);

    // Letra "S" no centro
    final textPainterCenter = TextPainter(
      text: const TextSpan(
        text: 'S',
        style: TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 40,
          fontWeight: FontWeight.w900,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainterCenter.layout();
    textPainterCenter.paint(
      canvas,
      Offset(
        center.dx - textPainterCenter.width / 2,
        center.dy - textPainterCenter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter para a seta fixa
class _SetaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Seta com gradiente
    final arrowPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF0000), Color(0xFFCC0000)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(center.dx - 15, 0, 30, 32))
      ..style = PaintingStyle.fill;

    final arrowPath = Path()
      ..moveTo(center.dx, 0)
      ..lineTo(center.dx - 15, 30)
      ..lineTo(center.dx + 15, 30)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);

    // Borda da seta
    final arrowBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(arrowPath, arrowBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

