// lib/screens/onboarding_app_screen.dart
// Onboarding

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyOnboardingDone = 'onboarding_app_done';

/// Retorna true se o onboarding já foi exibido.
Future<bool> isOnboardingAppDone() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyOnboardingDone) ?• false;
}

/// Marca onboarding como concluído (chamar ao finalizar ou "Já conheço").
Future<void> setOnboardingAppDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyOnboardingDone, true);
}

/// Tela de onboarding (3 páginas). Ao concluir, marca flag e chama [onDone].
class OnboardingAppScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingAppScreen({super.key, required this.onDone});

  @override
  State<OnboardingAppScreen> createState() => _OnboardingAppScreenState();
}

class _OnboardingAppScreenState extends State<OnboardingAppScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<Map<String, dynamic>> _pages = [
    {
      'icon': Icons.inventory_2,
      'title': 'Cadastre seus produtos',
      'subtitle': 'Adicione fotos, preços e estoque. Tudo fica salvo na sua loja e sincroniza quando tiver internet.',
      'color': Color(0xFF6366F1),
    },
    {
      'icon': Icons.point_of_sale,
      'title': 'Registre suas vendas',
      'subtitle': 'Faça vendas rápido pelo celular. Histórico de clientes e vendas sempre separado por loja.',
      'color': Color(0xFF22C55E),
    },
    {
      'icon': Icons.analytics_outlined,
      'title': 'Acompanhe resultados',
      'subtitle': 'Veja vendas do dia, produtos em falta e metas. Relatórios e gráficos para decidir melhor.',
      'color': Color(0xFFF59E0B),
    },
  ];

  Future<void> _finish() async {
    await setOnboardingAppDone();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark • const Color(0xFF121212) : Colors.white;
    final onBg = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text('Já conheço', style: TextStyle(color: theme.colorScheme.primary)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final p = _pages[index];
                  final color = p['color'] as Color;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha:0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p['icon'] as IconData, size: 64, color: color),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          p['title'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: onBg,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p['subtitle'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            color: onBg.withValues(alpha:0.7),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final active = i == _currentPage;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active • 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active • theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha:0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    if (_currentPage < _pages.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_currentPage < _pages.length - 1 • 'Próximo' : 'Começar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

