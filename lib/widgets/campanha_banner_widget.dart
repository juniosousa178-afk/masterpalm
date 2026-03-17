// lib/widgets/campanha_banner_widget.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math' as math;

import '../core/logger.dart';
import '../core/safe_cast.dart';

/// Widget de banner para exibir campanhas ativas no topo do cat�logo
class CampanhaBannerWidget extends StatefulWidget {
  final String lojaId;

  const CampanhaBannerWidget({
    super.key,
    required this.lojaId,
  });

  @override
  State<CampanhaBannerWidget> createState() => _CampanhaBannerWidgetState();
}

class _CampanhaBannerWidgetState extends State<CampanhaBannerWidget> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final PageController _pageController = PageController();

  List<Map<String, dynamic>> _campanhas = [];
  bool _loading = true;
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _carregarCampanhas();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _carregarCampanhas() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // Validar lojaId
      if (widget.lojaId.trim().isEmpty) {
        logW('?? [BANNER] lojaId vazio! N�o � poss�vel carregar campanhas.');
        if (mounted) setState(() => _loading = false);
        return;
      }

      logD('?? [BANNER] Carregando campanhas para loja: ${widget.lojaId}');

      // Estrat�gia: Buscar campanhas com limite (banner exibe poucas; reduz custo Firestore)
      // (evita problemas de �ndice composto do Firestore)
      final snapshot = await _db
          .collection('lojas')
          .doc(widget.lojaId)
          .collection('campanhas_sorteio')
          .limit(30)
          .get();

      logD('?? [BANNER] Total de campanhas: ${snapshot.docs.length}');

      final now = DateTime.now();
      final campanhasAtivas = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = asMap(doc.data());
        data['id'] = doc.id;

        // Verificar se est� ativa (campo booleano ou status string)
        final isAtiva = asBool(data['ativa'], defaultValue: false) ||
                        asString(data['status']) == 'aberta' ||
                        asString(data['status']) == 'ativa';

        if (!isAtiva) {
          logD('   ?? ${doc.id}: n�o est� ativa');
          continue;
        }

        // Verificar per�odo (Timestamp, DateTime, String, int)
        final dataInicio = asDateTime(data['dataInicio']);
        final dataFim = asDateTime(data['dataFim']);

        final dentroDoInicio = dataInicio == null ||
                               dataInicio.isBefore(now) ||
                               dataInicio.isAtSameMomentAs(now);
        final dentroDoFim = dataFim == null || dataFim.isAfter(now);

        logD('   ?? ${doc.id}: ativa=$isAtiva, inicio=$dataInicio, fim=$dataFim');
        logD('      dentroDoInicio=$dentroDoInicio, dentroDoFim=$dentroDoFim');

        if (dentroDoInicio && dentroDoFim) {
          campanhasAtivas.add(asMapDeep(data));
          logD('   ? Campanha ativa: ${data['nome'] ?? doc.id}');
        }
      }

      // Ordenar por dataFim (campanhas que terminam primeiro aparecem primeiro)
      campanhasAtivas.sort((a, b) {
        final dataFimA = asDateTime(a['dataFim']) ?? DateTime(2099);
        final dataFimB = asDateTime(b['dataFim']) ?? DateTime(2099);
        return dataFimA.compareTo(dataFimB);
      });

      logD('?? [BANNER] Campanhas ativas para exibir: ${campanhasAtivas.length}');

      if (!mounted) return;
      setState(() {
        _campanhas = campanhasAtivas;
        _loading = false;
      });

      if (!mounted) return;
      if (_campanhas.length > 1) {
        _startAutoScroll();
      }
    } catch (e, st) {
      logE('? [BANNER] Erro ao carregar campanhas (type=${e.runtimeType})', error: e, st: st);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final nextPage = (_currentPage + 1) % _campanhas.length;

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_campanhas.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 140,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemCount: _campanhas.length,
            itemBuilder: (context, index) {
              final campanha = _campanhas[index];
              return _buildCampanhaBanner(campanha);
            },
          ),

          // Indicadores de p�gina
          if (_campanhas.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _campanhas.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withValues(alpha:0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCampanhaBanner(Map<String, dynamic> campanha) {
    final nome = asString(campanha['nome']) ?? 'Campanha Especial';
    final descricao = asString(campanha['descricao']) ?? 'Participe e concorra a pr�mios!';
    final valorMinimo = asNum(campanha['valorMinimo'])?.toDouble() ?? 0.0;
    final dataFim = asDateTime(campanha['dataFim']);

    // Calcula dias restantes
    final diasRestantes = dataFim != null
        ? dataFim.difference(DateTime.now()).inDays
        : 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.shade600,
            Colors.purple.shade400,
            Colors.pink.shade400,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha:0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Padr�o de fundo
          Positioned.fill(
            child: CustomPaint(
              painter: _StarsPainter(),
            ),
          ),

          // Conte�do
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // �cone
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    color: Colors.amber,
                    size: 40,
                  ),
                ),

                const SizedBox(width: 16),

                // Texto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        descricao,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (valorMinimo > 0) ...[
                            Icon(
                              Icons.shopping_cart,
                              color: Colors.amber.shade200,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'M�n: R\$ ${valorMinimo.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (diasRestantes > 0) ...[
                            const SizedBox(width: 12),
                            Icon(
                              Icons.access_time,
                              color: Colors.amber.shade200,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$diasRestantes ${diasRestantes == 1 ? 'dia' : 'dias'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Seta
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter para desenhar estrelas de fundo
class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha:0.1)
      ..style = PaintingStyle.fill;

    // Desenha algumas estrelas aleat�rias
    final stars = [
      Offset(size.width * 0.2, size.height * 0.3),
      Offset(size.width * 0.5, size.height * 0.2),
      Offset(size.width * 0.8, size.height * 0.6),
      Offset(size.width * 0.7, size.height * 0.8),
      Offset(size.width * 0.3, size.height * 0.7),
    ];

    for (final star in stars) {
      _drawStar(canvas, star, 8, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    const angleStep = 3.14159 / 5; // 36 graus

    for (int i = 0; i < 10; i++) {
      final angle = i * angleStep - 3.14159 / 2;
      final radius = i.isEven ? size : size / 2;
      final x = center.dx + radius * (angle.cos());
      final y = center.dy + radius * (angle.sin());

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Extens�o para cos/sin usando dart:math
extension on double {
  double cos() => math.cos(this);
  double sin() => math.sin(this);
}

