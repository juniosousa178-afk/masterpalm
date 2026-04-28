import 'package:flutter/material.dart';

import 'package:master_palm/web/platform_stub.dart' if (dart.library.html) 'package:master_palm/web/platform_web.dart' as web_plat;

/// Link de catálogo inválido (`/loja` sem slug, `minha-loja`, query vazia, etc.).
/// Não confundir com [CatalogDomainBootstrapErrorApp] (domínio próprio sem mapeamento).
class InvalidPublicLojaPathApp extends StatelessWidget {
  const InvalidPublicLojaPathApp({
    super.key,
    required this.uri,
    this.buildId = '',
  });

  final Uri uri;
  final String buildId;

  @override
  Widget build(BuildContext context) {
    final diag = uri.queryParameters['diag'] == '1';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Link de loja inválido'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            diag
                ? 'O endereço do catálogo não é válido (falta o identificador da loja ou foi usado um link reservado de exemplo).\n\n'
                    'buildId=$buildId\n'
                    'host=${uri.host}\n'
                    'path=${uri.path}\n'
                    'query=${uri.query}\n'
                    'userAgent=${web_plat.Web.userAgent()}\n'
                : 'O endereço do catálogo não é válido. Peça o link completo da loja (incluindo o nome após /loja/).',
            style: const TextStyle(height: 1.4),
          ),
        ),
      ),
    );
  }
}
