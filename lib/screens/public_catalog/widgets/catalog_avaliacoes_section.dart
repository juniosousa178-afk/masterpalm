import 'package:flutter/material.dart';

import '../../../models/catalog_avaliacao.dart';
import '../../../services/catalog_avaliacao_fotos_input.dart';
import '../../../services/catalog_avaliacoes_service.dart';
import 'catalog_avaliacao_card.dart';

class CatalogAvaliacoesSection extends StatefulWidget {
  final String lojaId;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;

  const CatalogAvaliacoesSection({
    super.key,
    required this.lojaId,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
  });

  @override
  State<CatalogAvaliacoesSection> createState() => _CatalogAvaliacoesSectionState();
}

class _CatalogAvaliacoesSectionState extends State<CatalogAvaliacoesSection> {
  final _nomeCtrl = TextEditingController();
  final _comentarioCtrl = TextEditingController();
  final _fotosCtrl = TextEditingController();
  int _estrelas = 5;
  bool _enviando = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _comentarioCtrl.dispose();
    _fotosCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final nome = _nomeCtrl.text.trim();
    final comentario = _comentarioCtrl.text.trim();
    if (nome.isEmpty || comentario.isEmpty || _enviando) return;

    setState(() => _enviando = true);
    try {
      final fotos =
          CatalogAvaliacaoFotosInput.parseUrlsFromFormText(_fotosCtrl.text);
      await CatalogAvaliacoesService.enviarAvaliacao(
        lojaId: widget.lojaId,
        nomeCliente: nome,
        comentario: comentario,
        estrelas: _estrelas,
        fotos: fotos,
      );
      if (!mounted) return;
      _comentarioCtrl.clear();
      _fotosCtrl.clear();
      _estrelas = 5;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recebemos sua avaliacao. Ela aparecera no site apos aprovacao.',
          ),
        ),
      );
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel enviar agora.')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Avaliacoes de clientes',
            style: TextStyle(
              color: widget.textColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Depoimentos reais para trazer mais confianca na compra.',
            style: TextStyle(
              color: widget.textColor.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<CatalogAvaliacao>>(
            stream: CatalogAvaliacoesService.watchByLoja(widget.lojaId),
            builder: (context, snap) {
              final avaliacoes = snap.data ?? const <CatalogAvaliacao>[];
              if (avaliacoes.isEmpty) {
                return const SizedBox.shrink();
              }
              return SizedBox(
                height: 220,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: avaliacoes.length,
                  itemBuilder: (context, index) {
                    return CatalogAvaliacaoCard(
                      avaliacao: avaliacoes[index],
                      cardColor: widget.cardColor,
                      textColor: widget.textColor,
                      accentColor: widget.accentColor,
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.cardColor.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.textColor.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deixe sua avaliacao',
                  style: TextStyle(
                    color: widget.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nomeCtrl,
                  style: TextStyle(color: widget.textColor),
                  decoration: _inputDecoration('Seu nome'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _comentarioCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: TextStyle(color: widget.textColor),
                  decoration: _inputDecoration('Seu comentario'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fotosCtrl,
                  style: TextStyle(color: widget.textColor),
                  decoration: _inputDecoration(
                    'Fotos (opcional): URLs separadas por virgula — em breve upload direto',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Estrelas:',
                      style: TextStyle(color: widget.textColor),
                    ),
                    const SizedBox(width: 8),
                    ...List.generate(
                      5,
                      (i) => IconButton(
                        onPressed: () => setState(() => _estrelas = i + 1),
                        icon: Icon(
                          i < _estrelas
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: widget.accentColor,
                        ),
                        tooltip: '${i + 1} estrelas',
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _enviando ? null : _enviar,
                      icon: _enviando
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Enviar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: widget.textColor.withValues(alpha: 0.78)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.textColor.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: widget.accentColor.withValues(alpha: 0.9)),
      ),
    );
  }
}
