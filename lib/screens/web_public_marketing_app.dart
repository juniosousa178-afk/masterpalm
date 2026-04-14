// Site público (mastepalm.com.br / gestao.mastepalm.com.br) — sem fluxo admin na raiz.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_urls.dart';

/// App mínima para a landing pública no mesmo build Web do Firebase.
class PublicMarketingWebApp extends StatefulWidget {
  const PublicMarketingWebApp({super.key});

  @override
  State<PublicMarketingWebApp> createState() => _PublicMarketingWebAppState();
}

class _PublicMarketingWebAppState extends State<PublicMarketingWebApp> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _kFeatures = GlobalKey();
  final GlobalKey _kDownload = GlobalKey();
  final GlobalKey _kPlans = GlobalKey();
  final GlobalKey _kFaq = GlobalKey();
  final GlobalKey _kContact = GlobalKey();

  static const Color _bg = Color(0xFF0F172A);
  static const Color _accent = Color(0xFF6366F1);

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Uri _apkUri() {
    final o = Uri.base;
    return Uri(
      scheme: o.scheme.isEmpty ? 'https' : o.scheme,
      host: o.host,
      path: '/downloads/masterpalm.apk',
    );
  }

  Future<void> _open(Uri u) async {
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MasterPalm',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _bg,
        ),
      ),
      home: Scaffold(
        body: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: _bg.withValues(alpha: 0.92),
              surfaceTintColor: Colors.transparent,
              title: Row(
                children: [
                  Icon(Icons.storefront_rounded, color: _accent, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'MasterPalm',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: OutlinedButton(
                    onPressed: () => _open(Uri.parse(AppUrls.appWebBase)),
                    child: const Text('AppWeb'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: FilledButton(
                    onPressed: () => _open(_apkUri()),
                    child: const Text('Baixar APK'),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _navChip('Funcionalidades', () => _scrollTo(_kFeatures)),
                              _navChip('Download', () => _scrollTo(_kDownload)),
                              _navChip('Recursos', () => _scrollTo(_kFeatures)),
                              _navChip('FAQ', () => _scrollTo(_kFaq)),
                              _navChip('Planos', () => _scrollTo(_kPlans)),
                              _navChip('Contato', () => _scrollTo(_kContact)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Controle total da sua loja: estoque, vendas, clientes e relatórios — no Android e na Web.',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'O MasterPalm é um sistema completo para gestão de loja, com catálogo online, pedidos, '
                          'multiusuários e operação mesmo com internet instável.',
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.white.withValues(alpha: 0.78),
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 36),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _open(_apkUri()),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('Baixar APK'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _open(Uri.parse(AppUrls.appWebBase)),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Acessar AppWeb'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 56),
                        _section(
                          context,
                          key: _kFeatures,
                          title: 'Funcionalidades',
                          body: const [
                            'Estoque, vendas, clientes e fornecedores',
                            'Catálogo online com pedidos e integrações',
                            'Relatórios, metas e gestão financeira',
                            'App Android + painel Web (AppWeb em app.mastepalm.com.br)',
                          ],
                        ),
                        const SizedBox(height: 40),
                        _section(
                          context,
                          key: _kDownload,
                          title: 'Download',
                          body: const [
                            'Instale o APK oficial para Android direto do site.',
                            'O AppWeb (navegador) é acessado pelo botão acima — domínio canônico do painel.',
                          ],
                          extra: FilledButton(
                            onPressed: () => _open(_apkUri()),
                            child: const Text('Obter APK'),
                          ),
                        ),
                        const SizedBox(height: 40),
                        _section(
                          context,
                          key: _kPlans,
                          title: 'Planos',
                          body: const [
                            'Planos Free, Básico, Intermediário e Pro — com trial e assinatura via Mercado Pago.',
                            'Valores e condições finais aparecem no checkout dentro do AppWeb.',
                          ],
                        ),
                        const SizedBox(height: 40),
                        _section(
                          context,
                          key: _kFaq,
                          title: 'FAQ',
                          body: const [
                            'Este endereço (site público) é só divulgação e download.',
                            'Para entrar na sua loja, use sempre o AppWeb no domínio app.mastepalm.com.br.',
                          ],
                        ),
                        const SizedBox(height: 40),
                        _section(
                          context,
                          key: _kContact,
                          title: 'Contato',
                          body: const [
                            'Dúvidas comerciais e suporte: use os canais indicados no AppWeb após o login.',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required GlobalKey key,
    required String title,
    required List<String> body,
    Widget? extra,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
        ),
        const SizedBox(height: 12),
        ...body.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: _accent.withValues(alpha: 0.9)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t,
                    style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (extra != null) ...[const SizedBox(height: 16), extra],
      ],
    );
  }
}
