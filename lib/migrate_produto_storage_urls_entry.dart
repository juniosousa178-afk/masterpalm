// Ponto de entrada para migração com Firebase real.
//
// Na Web: o runner (Firebase/Firestore) usa import ADIADO para não carregar durante o
// parse do entry — antes disso `webPluginRegistrar` ainda não está pronto (erro JS).
// [runApp] + dois frames + atraso reduz avisos no canal lifecycle.
//
//   fvm flutter run -t lib/migrate_produto_storage_urls_entry.dart -d chrome `
//     --dart-define=MP_MIGRATION_ALL_LOJAS=true
//
// Se no Chrome aparecer dart_sdk.js / Symbol(_privateNames): fechar o run, apagar SW em
// DevTools → Application → Service Workers (Unregister), fvm flutter clean, e tentar
// o mesmo comando com --release (compilador diferente do modo debug).
//
// Opções: test/migrate_produto_storage_urls_test.dart

import 'package:flutter/widgets.dart';
import 'package:master_palm/scripts/migrate_produto_storage_urls_runner.dart'
    deferred as migrate_runner;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _MigrateProdutoStorageUrlsApp());
}

class _MigrateProdutoStorageUrlsApp extends StatefulWidget {
  const _MigrateProdutoStorageUrlsApp();

  @override
  State<_MigrateProdutoStorageUrlsApp> createState() =>
      _MigrateProdutoStorageUrlsAppState();
}

class _MigrateProdutoStorageUrlsAppState
    extends State<_MigrateProdutoStorageUrlsApp> {
  String _status = 'A iniciar…';
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (mounted) _run();
        });
      });
    });
  }

  Future<void> _run() async {
    if (!mounted) return;
    setState(() {
      _status = 'A correr migração (consola do navegador: F12)…';
      _errorDetail = null;
    });
    try {
      await migrate_runner.loadLibrary();
      await migrate_runner.runMigrateProdutoStorageUrlsFromEnvironment();
      if (!mounted) return;
      setState(() => _status = 'Concluído. Podes fechar o separador.');
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Configuração inválida';
        _errorDetail = e.message;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _status = 'Erro — ver consola (F12)';
        _errorDetail = '$e';
      });
      debugPrint('Migração: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF000000),
                    ),
                  ),
                  if (_errorDetail != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorDetail!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFB00020),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
