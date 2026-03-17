// lib/screens/barcode_scanner_screen.dart
// Tela full-screen para leitura de código de barras pela câmera.
// Retorna o código lido via Navigator.pop(context, codigo) ou null se cancelar.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  /// Abre a tela de scan e retorna o código lido ou null.
  static Future<String?> scan(BuildContext context) async {
    if (kIsWeb) {
      // Web: mobile_scanner pode funcionar mas câmera pode falhar
      final result = await Navigator.of(context).push<String?>(
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      );
      return result;
    }
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    return result;
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _jaRetornou = false;

  void _onDetect(BarcodeCapture capture) {
    if (_jaRetornou) return;
    final list = capture.barcodes;
    if (list.isEmpty) return;
    final barcode = list.first;
    final raw = barcode.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    _jaRetornou = true;
    if (mounted) Navigator.of(context).pop(raw.trim());
  }

  void _abrirInputManual() async {
    if (_jaRetornou) return;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Inserir código manualmente'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Digite o código de barras (EAN, UPC...)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (code != null && code.isNotEmpty && mounted && !_jaRetornou) {
      _jaRetornou = true;
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ler código de barras'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          if (kIsWeb)
            TextButton.icon(
              onPressed: _abrirInputManual,
              icon: const Icon(Icons.keyboard, size: 20, color: Colors.white70),
              label: const Text('Inserir manual', style: TextStyle(color: Colors.white70)),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Câmera indisponível ou sem permissão.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    ),
                    if (kIsWeb) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Use "Inserir manual" na barra superior para digitar o código.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _abrirInputManual,
                        icon: const Icon(Icons.keyboard, color: Colors.white70),
                        label: const Text('Inserir manualmente', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: Container(
                width: 280,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Text(
                'Aponte a câmera para o código de barras',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
