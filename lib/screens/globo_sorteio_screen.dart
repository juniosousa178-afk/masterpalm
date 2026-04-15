// lib/screens/globo_sorteio_screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/logger.dart';
import '../services/globo_sorteio_params_resolver.dart';
import '../services/numero_sorte_service.dart';

/// Wrapper que resolve lojaId/campanhaId antes de abrir a tela (ETAPA 18).
/// Em release, se resolver retornar null mostra erro amigável; em debug usa fallback com logW.
class GloboSorteioScreenWrapper extends StatefulWidget {
  const GloboSorteioScreenWrapper({super.key});

  @override
  State<GloboSorteioScreenWrapper> createState() => _GloboSorteioScreenWrapperState();
}

class _GloboSorteioScreenWrapperState extends State<GloboSorteioScreenWrapper> {
  bool _resolving = true;
  GloboSorteioParams? _params;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final uri = Uri.base;
    final params = await GloboSorteioParamsResolver.resolve(uri: uri, isWeb: kIsWeb);
    if (!mounted) return;
    if (params != null) {
      setState(() {
        _params = params;
        _resolving = false;
      });
      return;
    }
    if (kDebugMode) {
      logW('[ROUTER] Globo Sorteio: resolver retornou null; usando fallback debug-only (placeholders)', tag: 'GLOBO_SORTEIO');
      setState(() {
        _params = const GloboSorteioParams(lojaId: 'masterpalm', campanhaId: 'xxx', source: 'fallback-debug');
        _resolving = false;
      });
      return;
    }
    setState(() => _resolving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_params == null && !kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Globo de Sorteio')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sorteio indisponível. Contate o suporte.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }
    return GloboSorteioScreen(
      lojaId: _params!.lojaId,
      campanhaId: _params!.campanhaId,
    );
  }
}

class GloboSorteioScreen extends StatefulWidget {
  final String lojaId;
  final String campanhaId;

  const GloboSorteioScreen({
    super.key,
    required this.lojaId,
    required this.campanhaId,
  });

  @override
  State<GloboSorteioScreen> createState() => _GloboSorteioScreenState();
}

class _GloboSorteioScreenState extends State<GloboSorteioScreen> {
  final Random _rand = Random();

  // Números existentes na campanha (todos os clientes)
  final List<String> _todosNumeros = [];
  Set<String> _numerosSet = {};

  bool _carregandoNumeros = true;
  String? _erroCarregar;

  // Estado do sorteio
  int _rodada = 1; // 1, 2, 3 => sem número existente | 4 => número existente
  bool _sorteioFinalizado = false;

  // Número alvo da rodada (5 dígitos)
  String? _numeroAlvo;
  int _digitoIndex = 0; // 0..4
  final List<int?> _digitosVisiveis = List<int?>.filled(5, null);

  // Roleta / animação
  double _roletaAngle = 0.0;
  int _digitoAtualNaRoleta = 0;
  bool _girando = false;
  Timer? _timerDigit;

  @override
  void initState() {
    super.initState();
    _carregarNumerosDaCampanha();
  }

  @override
  void dispose() {
    _timerDigit?.cancel();
    super.dispose();
  }

  // ============================================================
  // CARREGAR NÚMEROS EXISTENTES DA CAMPANHA
  // ============================================================

  Future<void> _carregarNumerosDaCampanha() async {
    setState(() {
      _carregandoNumeros = true;
      _erroCarregar = null;
    });

    try {
      // Mesmo critério do Histórico (orderBy dataParticipacao) para contagem e sorteio baterem
      final participantes = await NumeroSorteService.getParticipantesParaSorteio(
        widget.lojaId,
        widget.campanhaId,
      );

      _todosNumeros.clear();

      for (final p in participantes) {
        final numero = p['numeroSorte'] as String?;
        if (numero != null && numero.length == 5) {
          _todosNumeros.add(numero);
        }
      }

      _numerosSet = _todosNumeros.toSet();

      setState(() {
        _carregandoNumeros = false;
      });
    } catch (e) {
      setState(() {
        _carregandoNumeros = false;
        _erroCarregar = 'Erro ao carregar números da campanha: $e';
      });
    }
  }

  // ============================================================
  // GERADORES DE NÚMEROS
  // ============================================================

  String _gerarNumeroAleatorio5Digitos() {
    final n = 10000 + _rand.nextInt(90000); // 10000..99999
    return n.toString();
  }

  /// Para rodadas 1, 2 e 3, garante número que NÃO existe.
  String _gerarNumeroQueNaoExiste() {
    if (_numerosSet.length >= 90000) {
      // caso teórico: todos ocupados
      return _gerarNumeroAleatorio5Digitos();
    }

    while (true) {
      final s = _gerarNumeroAleatorio5Digitos();
      if (!_numerosSet.contains(s)) return s;
    }
  }

  /// Para a rodada 4, seleciona um número EXISTENTE de forma aleatória.
  String _escolherNumeroExistente() {
    if (_todosNumeros.isEmpty) {
      throw Exception(
        'Nenhum número foi gerado ainda para esta campanha.\n'
        'Gere vendas com números antes de sortear.',
      );
    }
    // Embaralhar para garantir escolha aleatória (não o primeiro da lista)
    final copia = List<String>.from(_todosNumeros)..shuffle(_rand);
    return copia.first;
  }

  // ============================================================
  // LÓGICA DE SORTEIO DE DÍGITO
  // ============================================================

  Future<void> _onPressSortearDigito() async {
    if (_carregandoNumeros || _girando || _sorteioFinalizado) return;

    if (_rodada > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sorteio já finalizado.'),
        ),
      );
      return;
    }

    // Se estamos começando um novo número (primeiro dígito)
    if (_digitoIndex == 0 && _numeroAlvo == null) {
      try {
        if (_rodada <= 3) {
          // 1º, 2º e 3º resultados: número que NÃO existe.
          _numeroAlvo = _gerarNumeroQueNaoExiste();
        } else {
          // 4º resultado: número que EXISTE.
          _numeroAlvo = _escolherNumeroExistente();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
          ),
        );
        return;
      }
    }

    if (_numeroAlvo == null) return;

    final targetDigit =
        int.parse(_numeroAlvo![_digitoIndex]); // dígito que deve cair

    _iniciarAnimacaoDigit(targetDigit);
  }

  // Converte o ângulo da roleta para o dígito que está "no cursor" (topo)
  int _digitFromAngle(double angle) {
    const twoPi = 2 * pi;
    double normalize(double a) => (a % twoPi + twoPi) % twoPi;

    const sweep = twoPi / 10; // 10 segmentos
    final diff = normalize(-angle); // distância a partir de 0

    int i = (diff / sweep).floor() % 10;
    return i;
  }

  void _iniciarAnimacaoDigit(int targetDigit) {
    _timerDigit?.cancel();

    setState(() {
      _girando = true;
    });

    // Sons: adicione audioplayers, declare assets/sounds/giro.mp3 e chame
    // AudioPlayer().play(AssetSource('sounds/giro.mp3'));
    // _playSpinSound();

    int ticks = 0;
    const totalTicks = 40; // mais ticks = giro mais suave
    const stepDuration = Duration(milliseconds: 45);

    const twoPi = 2 * pi;
    const sweep = twoPi / 10;

    double normalize(double a) => (a % twoPi + twoPi) % twoPi;

    final startAngle = _roletaAngle;

    // Queremos que, ao final, o segmento do targetDigit fique centrado no topo
    final targetBase = -(targetDigit * sweep + sweep / 2); // alinhamento final desejado (mod 2p)
    final currentMod = normalize(startAngle);
    final targetMod = normalize(targetBase);
    double deltaToTarget = targetMod - currentMod;
    if (deltaToTarget < 0) deltaToTarget += twoPi;

    const spins = 3; // voltas completas antes de parar
    final endAngle = startAngle + spins * twoPi + deltaToTarget;
    final angleStep = (endAngle - startAngle) / totalTicks;

    _timerDigit = Timer.periodic(stepDuration, (timer) {
      ticks++;

      setState(() {
        _roletaAngle += angleStep;
        _digitoAtualNaRoleta = _digitFromAngle(_roletaAngle);
      });

      if (ticks >= totalTicks) {
        timer.cancel();

        setState(() {
          _roletaAngle = endAngle;
          _digitoAtualNaRoleta = targetDigit;
          _digitosVisiveis[_digitoIndex] = targetDigit;
          _girando = false;
          _digitoIndex++;
        });

        // Sons: adicione audioplayers, declare assets/sounds/parada.mp3 e chame
        // AudioPlayer().play(AssetSource('sounds/parada.mp3'));
        // _playStopSound();

        if (_digitoIndex >= 5) {
          _onNumeroCompleto();
        }
      }
    });
  }

  Future<void> _onNumeroCompleto() async {
    final numero = _numeroAlvo!;
    final rodadaAtual = _rodada;

    if (rodadaAtual <= 3) {
      // Garantimos que ele NÃO existe, então só mostramos "quase lá".
      await _mostrarDialogResultado(
        titulo: 'Tentativa $rodadaAtual',
        mensagem: 'Quase lá!\n\n'
            'Número $numero não foi premiado.\n\n'
            'Continue girando!',
        vencedor: null,
        isVencedorFinal: false,
      );
    } else {
      // Rodada 4: número existente. Busca o vencedor real (mesma lista do Histórico).
      final participantes = await NumeroSorteService.getParticipantesParaSorteio(
        widget.lojaId,
        widget.campanhaId,
      );

      // Buscar o(s) participante(s) com esse número (aleatório entre múltiplos, se houver)
      final candidatos = participantes.where((p) => p['numeroSorte'] == numero).toList();
      candidatos.shuffle(_rand);
      final vencedorEncontrado = candidatos.isNotEmpty ? candidatos.first : null;

      if (vencedorEncontrado != null) {
        // Marcar como sorteado
        await NumeroSorteService.marcarComoSorteado(
          lojaId: widget.lojaId,
          campanhaId: widget.campanhaId,
          participanteId: vencedorEncontrado['id'] as String,
        );

        // Salvar no histórico de sorteios
        await _salvarHistoricoSorteio(vencedorEncontrado);

        await _mostrarDialogResultado(
          titulo: 'TEMOS UM VENCEDOR!',
          mensagem: 'Número: $numero\n\n'
              'Cliente: ${vencedorEncontrado['clienteNome'] ?? 'Desconhecido'}\n'
              'Email: ${vencedorEncontrado['clienteEmail'] ?? '-'}\n'
              'Telefone: ${vencedorEncontrado['clienteTelefone'] ?? '-'}\n'
              'Valor da compra: R\$ ${(vencedorEncontrado['valorPedido'] as num?)?.toStringAsFixed(2) ?? '-'}',
          vencedor: vencedorEncontrado,
          isVencedorFinal: true,
        );
      } else {
        await _mostrarDialogResultado(
          titulo: 'Resultado Final',
          mensagem: 'Número $numero não foi encontrado.\n'
              'Verifique se os números da campanha foram gerados corretamente.',
          vencedor: null,
          isVencedorFinal: false,
        );
      }

      setState(() {
        _sorteioFinalizado = true;
      });
    }

    // Prepara para próxima rodada ou finaliza
    setState(() {
      _rodada++;
      _numeroAlvo = null;
      _digitoIndex = 0;
      for (int i = 0; i < _digitosVisiveis.length; i++) {
        _digitosVisiveis[i] = null;
      }
    });
  }

  Future<void> _mostrarDialogResultado({
    required String titulo,
    required String mensagem,
    Map<String, dynamic>? vencedor,
    bool isVencedorFinal = false,
  }) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Row(
          children: [
            if (isVencedorFinal)
              const Text('🎯 ', style: TextStyle(fontSize: 24)),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mensagem,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            if (isVencedorFinal && vencedor != null) ...[
              const SizedBox(height: 20),
              // Botão WhatsApp
              if (vencedor['clienteTelefone'] != null &&
                  vencedor['clienteTelefone'].toString().isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _abrirWhatsAppVencedor(vencedor),
                    icon: const Icon(Icons.message, color: Colors.white),
                    label: const Text(
                      'Enviar WhatsApp',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              isVencedorFinal ? 'Fechar' : 'Continuar',
              style: const TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre WhatsApp com mensagem de parabéns para o vencedor
  Future<void> _abrirWhatsAppVencedor(Map<String, dynamic> vencedor) async {
    final telefone = vencedor['clienteTelefone']?.toString() ?? '';
    final nome = vencedor['clienteNome']?.toString() ?? 'Cliente';
    final numero = vencedor['numeroSorte']?.toString() ?? '';

    // Limpar telefone - manter apenas números
    String telefoneLimpo = telefone.replaceAll(RegExp(r'[^\d]'), '');

    // Adicionar código do país se não tiver
    if (!telefoneLimpo.startsWith('55') && telefoneLimpo.length <= 11) {
      telefoneLimpo = '55$telefoneLimpo';
    }

    final mensagem = '''
🎉 *PARABÉNS, ${nome.split(' ').first}!* 🎉

Você foi o GRANDE VENCEDOR do nosso sorteio!

🏆 *Número premiado:* $numero

Entre em contato conosco para retirar seu prêmio!

✨ Obrigado por participar!
''';

    final url = 'https://wa.me/$telefoneLimpo?text=${Uri.encodeComponent(mensagem)}';

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível abrir o WhatsApp'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, st) {
      logE('Erro ao abrir WhatsApp (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Salva o resultado do sorteio no histórico
  Future<void> _salvarHistoricoSorteio(Map<String, dynamic> vencedor) async {
    try {
      await FirebaseFirestore.instance
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .doc(widget.campanhaId)
          .collection('historico_sorteios')
          .add({
        'numero': vencedor['numeroSorte'],
        'nomeCliente': vencedor['clienteNome'],
        'emailCliente': vencedor['clienteEmail'],
        'telefoneCliente': vencedor['clienteTelefone'],
        'valorPedido': vencedor['valorPedido'],
        'pedidoId': vencedor['pedidoId'],
        'participanteId': vencedor['id'],
        'data': FieldValue.serverTimestamp(),
      });
      logD('? Histórico de sorteio salvo');
    } catch (e, st) {
      logE('? Erro ao salvar histórico (type=${e.runtimeType})', error: e, st: st);
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 6,
        shadowColor: Colors.greenAccent.withOpacity(0.4),
        title: const Text('Roleta do Sorteio'),
      ),
      body: _carregandoNumeros
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : _erroCarregar != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _erroCarregar!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 16),

                        // Info de participantes
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.greenAccent.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people,
                                color: Colors.greenAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_todosNumeros.length} participantes',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Texto de status igual em todas as 4 rodadas (evita parecer combinado).
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _sorteioFinalizado
                                ? 'Sorteio finalizado!\nO vencedor foi revelado.'
                                : _todosNumeros.isEmpty
                                    ? 'Nenhum participante cadastrado ainda.\nAguarde vendas com números da sorte.'
                                    : 'Gire a roleta para revelar o número!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Roleta
                        _buildRoleta(),

                        const SizedBox(height: 32),

                        // Número parcial / completo
                        _buildNumeroParcial(),

                        const SizedBox(height: 32),

                        // Botão de sortear dígito com mesmo texto e cor em todas as 4 rodadas.
                        ElevatedButton(
                          onPressed: (_sorteioFinalizado || _girando || _todosNumeros.isEmpty)
                              ? null
                              : _onPressSortearDigito,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sorteioFinalizado || _todosNumeros.isEmpty
                                ? Colors.grey
                                : Colors.greenAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 8,
                            shadowColor: Colors.greenAccent.withOpacity(0.7),
                          ),
                          child: Text(
                            _todosNumeros.isEmpty
                                ? 'Sem participantes'
                                : _sorteioFinalizado
                                    ? 'Sorteio encerrado'
                                    : _girando
                                        ? 'Girando...'
                                        : _digitoIndex == 0
                                            ? 'Girar Roleta'
                                            : 'Próximo dígito',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  // ---------------------- ROLETA VISUAL ----------------------

  Widget _buildRoleta() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFF151720),
            Color(0xFF05060A),
          ],
          center: Alignment(0, -0.2),
          radius: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withOpacity(0.35),
            blurRadius: 25,
            spreadRadius: 1,
          ),
        ],
      ),
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Disco da roleta girando
            Transform.rotate(
              angle: _roletaAngle,
              child: CustomPaint(
                size: const Size(260, 260),
                painter: _RoletaCassinoPainter(),
              ),
            ),

            // "Cursor" fixo: círculo central com número atual.
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0B0E15),
                    Color(0xFF151B2C),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.greenAccent, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withOpacity(0.6),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                _digitoAtualNaRoleta.toString(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
            ),

            // Pequeno indicador discreto no topo (não é seta, é só um marcador).
            Positioned(
              top: 12,
              child: Container(
                width: 24,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.8),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumeroParcial() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final d = _digitosVisiveis[i];
        final ativo = i == _digitoIndex && !_sorteioFinalizado;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(10),
          width: 48,
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF10121A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: ativo ? Colors.greenAccent : Colors.white24,
              width: 2,
            ),
            boxShadow: ativo
                ? [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.6),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          alignment: Alignment.center,
          child: Text(
            d?.toString() ?? '-',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: d == null ? Colors.white30 : Colors.white,
            ),
          ),
        );
      }),
    );
  }
}

// ============================================================
// PAINTER DA ROLETA - ESTILO CASSINO
// ============================================================

class _RoletaCassinoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    const double sweep = 2 * pi / 10; // 10 segmentos (0..9)

    final outerRect = Rect.fromCircle(center: center, radius: radius);

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < 10; i++) {
      // Cores estilo cassino: 0 verde, demais alternando vermelho/preto
      Color baseColor;
      if (i == 0) {
        baseColor = Colors.greenAccent.shade400;
      } else {
        final isEven = i % 2 == 0;
        baseColor = isEven
            ? Colors.red.shade600
            : const Color(0xFF1A1C24); // "preto" da roleta
      }

      // Camada base
      final paintBase = Paint()
        ..style = PaintingStyle.fill
        ..color = baseColor;

      final startAngle = -pi / 2 + i * sweep;
      canvas.drawArc(outerRect, startAngle, sweep, true, paintBase);

      // Highlight interno para dar sensação 3D
      final innerRect = Rect.fromCircle(
        center: center,
        radius: radius * 0.82,
      );
      final paintHighlight = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withOpacity(0.04);
      canvas.drawArc(innerRect, startAngle, sweep, true, paintHighlight);

      // Linha divisória
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withOpacity(0.6);
      canvas.drawArc(outerRect, startAngle, sweep, true, borderPaint);

      // Desenha o número no segmento
      final angleForText = startAngle + sweep / 2;
      final textOffset = Offset(
        center.dx + (radius * 0.68) * cos(angleForText),
        center.dy + (radius * 0.68) * sin(angleForText),
      );

      textPainter.text = TextSpan(
        text: i.toString(),
        style: TextStyle(
          color: i == 0 ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      );
      textPainter.layout();
      canvas.save();
      canvas.translate(
        textOffset.dx - textPainter.width / 2,
        textOffset.dy - textPainter.height / 2,
      );
      textPainter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // Contorno externo
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Colors.amberAccent;
    canvas.drawCircle(center, radius, borderPaint);

    // Anel interno dourado para dar mais cara de cassino
    final innerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.amber.shade700;
    canvas.drawCircle(center, radius * 0.75, innerRingPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

