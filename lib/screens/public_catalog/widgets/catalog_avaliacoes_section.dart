import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../models/catalog_avaliacao.dart';
import '../../../models/catalog_avaliacoes_ordem.dart';
import '../../../services/catalog_avaliacao_fotos_input.dart';
import '../../../services/catalog_avaliacoes_service.dart';
import '../../../services/subscription_service.dart';
import '../../../services/user_profile_resolver.dart';
import 'catalog_avaliacoes_carousel.dart';

class CatalogAvaliacoesSection extends StatefulWidget {
  final String lojaId;
  final Color cardColor;
  final Color textColor;
  final Color accentColor;
  /// Ordem de exibição (configuração da loja no Firestore).
  final CatalogAvaliacoesOrdem ordem;

  const CatalogAvaliacoesSection({
    super.key,
    required this.lojaId,
    required this.cardColor,
    required this.textColor,
    required this.accentColor,
    this.ordem = CatalogAvaliacoesOrdem.maisRecentes,
  });

  @override
  State<CatalogAvaliacoesSection> createState() => _CatalogAvaliacoesSectionState();
}

class _CatalogAvaliacoesSectionState extends State<CatalogAvaliacoesSection> {
  final _nomeCtrl = TextEditingController();
  final _comentarioCtrl = TextEditingController();
  final _fotosCtrl = TextEditingController();
  final List<String> _fotosUrlsGaleria = [];
  int _estrelas = 5;
  bool _enviando = false;
  bool _uploadandoGaleria = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub =
        FirebaseAuth.instance.authStateChanges().listen((_) => _preencherNomeSeVazio());
    _preencherNomeSeVazio();
  }

  /// Preenche "Seu nome" com perfil Firestore (nome/name) ou displayName do Auth.
  /// Só aplica se o campo ainda estiver vazio quando a resolução terminar.
  Future<void> _preencherNomeSeVazio() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    String nome = '';
    try {
      final isRoot = SubscriptionService.isRoot;
      final profile =
          await UserProfileResolver.resolveCurrentUserProfile(isRoot: isRoot);
      if (profile != null) {
        nome = (profile.raw['nome'] ?? profile.raw['name'] ?? '')
            .toString()
            .trim();
      }
    } catch (_) {
      // fallback abaixo
    }
    if (nome.isEmpty) {
      nome = (user.displayName ?? '').trim();
    }
    if (!mounted || _nomeCtrl.text.trim().isNotEmpty || nome.isEmpty) return;
    setState(() => _nomeCtrl.text = nome);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _nomeCtrl.dispose();
    _comentarioCtrl.dispose();
    _fotosCtrl.dispose();
    super.dispose();
  }

  int _fotosCountAtual() {
    final texto =
        CatalogAvaliacaoFotosInput.parseUrlsFromFormText(_fotosCtrl.text);
    return _fotosUrlsGaleria.length + texto.length;
  }

  Future<void> _importarGaleria() async {
    const maxF = CatalogAvaliacaoFotosInput.maxFotosPorAvaliacao;
    final restante = maxF - _fotosCountAtual();
    if (restante <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No maximo $maxF fotos por avaliacao.')),
      );
      return;
    }
    setState(() => _uploadandoGaleria = true);
    try {
      final r = await CatalogAvaliacaoFotosInput.pickGalleryAndUploadUrls(
        lojaId: widget.lojaId,
        remainingSlots: restante,
      );
      if (!mounted) return;
      if (r.pickedCount == 0) return;
      if (r.urls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nenhuma foto foi enviada. Verifique tamanho (ate 4 MB) e conexao.',
            ),
          ),
        );
        return;
      }
      setState(() => _fotosUrlsGaleria.addAll(r.urls));
    } finally {
      if (mounted) setState(() => _uploadandoGaleria = false);
    }
  }

  Future<void> _enviar() async {
    final nome = _nomeCtrl.text.trim();
    final comentario = _comentarioCtrl.text.trim();
    if (nome.isEmpty || comentario.isEmpty || _enviando) return;

    const maxF = CatalogAvaliacaoFotosInput.maxFotosPorAvaliacao;
    final fotos = [
      ..._fotosUrlsGaleria,
      ...CatalogAvaliacaoFotosInput.parseUrlsFromFormText(_fotosCtrl.text),
    ];
    if (fotos.length > maxF) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No maximo $maxF fotos por avaliacao.')),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
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
      _fotosUrlsGaleria.clear();
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
          const SizedBox(height: 12),
          StreamBuilder<List<CatalogAvaliacao>>(
            stream: CatalogAvaliacoesService.watchByLoja(widget.lojaId),
            builder: (context, snap) {
              final lid = widget.lojaId;
              final bruto = snap.hasError
                  ? const <CatalogAvaliacao>[]
                  : (snap.data ?? const <CatalogAvaliacao>[]);
              // Com ao menos uma avaliacao real (Firestore), nunca mistura com exemplos.
              final reais =
                  bruto.where((a) => !a.isMock).toList(growable: false);
              final paraCarrossel = reais.isNotEmpty
                  ? reais
                  : CatalogAvaliacoesService.exemplosParaCarrossel(lid);
              final avaliacoes = CatalogAvaliacoesService.aplicarOrdem(
                paraCarrossel,
                widget.ordem,
              );
              return CatalogAvaliacoesCarousel(
                items: avaliacoes,
                cardColor: widget.cardColor,
                textColor: widget.textColor,
                accentColor: widget.accentColor,
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
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(
                    'Fotos (opcional): URLs separadas por virgula',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: (_uploadandoGaleria || _enviando)
                        ? null
                        : _importarGaleria,
                    icon: _uploadandoGaleria
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accentColor,
                            ),
                          )
                        : Icon(
                            Icons.photo_library_outlined,
                            color: widget.accentColor,
                          ),
                    label: Text(
                      _uploadandoGaleria
                          ? 'Enviando fotos...'
                          : 'Importar da galeria',
                      style: TextStyle(color: widget.textColor),
                    ),
                  ),
                ),
                if (_fotosUrlsGaleria.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Fotos da galeria (${_fotosUrlsGaleria.length}/${CatalogAvaliacaoFotosInput.maxFotosPorAvaliacao})',
                    style: TextStyle(
                      color: widget.textColor.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _fotosUrlsGaleria.length; i++)
                        _GaleriaThumb(
                          url: _fotosUrlsGaleria[i],
                          borderColor: widget.textColor.withValues(alpha: 0.2),
                          onRemove: () =>
                              setState(() => _fotosUrlsGaleria.removeAt(i)),
                        ),
                    ],
                  ),
                ],
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

class _GaleriaThumb extends StatelessWidget {
  final String url;
  final Color borderColor;
  final VoidCallback onRemove;

  const _GaleriaThumb({
    required this.url,
    required this.borderColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            url,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.black12,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, size: 28),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.black87,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
