// Painel Dicas: lista, edição e remoção com callbacks no State (part da mesma library).

part of 'loja_config_screen.dart';

class _PaneDicasWidget extends StatelessWidget {
  const _PaneDicasWidget({required this.host});

  final _LojaConfigScreenState host;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Dicas, cuidados, garantias e qualidade',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneMutedIntroText(
            'Estas dicas aparecem no menu do catálogo e numa página dedicada. '
            'O cliente pode ver cuidados com o produto, garantias, informações de qualidade etc. '
            'Use o botão "Adicionar dica" e, em cada dica, opcionalmente um banner.',
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: host._dicas.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final d = host._dicas[index];
              final titulo = (d['titulo'] ?? '').toString().trim();
              final tipo = (d['tipo'] ?? 'informacoes').toString();
              final tipoLabel = _LojaConfigScreenState._dicaTipos
                      .where((e) => e.key == tipo)
                      .map((e) => e.value)
                      .firstOrNull ??
                  tipo;
              final bannerUrl =
                  (d['bannerUrl'] ?? d['banner_url'] ?? '').toString().trim();
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: _LojaConfigScreenState._primaryColor
                          .withOpacity(0.3)),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  leading: bannerUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: Image(
                              image: mpImageProvider(bannerUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported,
                                color: _LojaConfigScreenState._primaryColor,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _LojaConfigScreenState._primaryColor
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.lightbulb_outline,
                            color: _LojaConfigScreenState._primaryColor,
                          ),
                        ),
                  title: Text(
                    titulo.isEmpty ? '(Sem título)' : titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    tipoLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => host._editarDica(context, index),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: _LojaConfigScreenState._errorColor,
                        ),
                        onPressed: () => host._dicasRemoveAt(index),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => host._adicionarDica(context),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar dica'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _LojaConfigScreenState._primaryColor,
              side: const BorderSide(color: _LojaConfigScreenState._primaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
