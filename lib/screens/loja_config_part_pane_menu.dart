// Painel "Menu do catálogo & páginas internas" — UI densa; lógica permanece no State via [host].

part of 'loja_config_screen.dart';

class _PaneMenuWidget extends StatelessWidget {
  const _PaneMenuWidget({required this.host});

  final _LojaConfigScreenState host;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Menu do catálogo & páginas internas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneMutedIntroText(
            'Configure aqui os itens que irão aparecer no menu lateral do catálogo web: '
            'categorias, entrar/cadastro, contato, SAC e a página "Quem somos".',
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Mostrar "Categorias" no menu'),
                  subtitle: const Text(
                    'Lista de produtos por categoria (filtro visual).',
                  ),
                  value: host._menuShowCategorias,
                  onChanged: host._menuSetShowCategorias,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Mostrar botão "Entrar / Cadastro"'),
                  subtitle: const Text(
                    'No futuro poderá abrir a tela de cadastro/login.',
                  ),
                  value: host._menuShowEntrar,
                  onChanged: host._menuSetShowEntrar,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Mostrar atalho "Contato rápido"'),
                  subtitle: const Text(
                    'Usa o WhatsApp configurado na identidade da loja.',
                  ),
                  value: host._menuShowContato,
                  onChanged: host._menuSetShowContato,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                      'Mostrar "SAC – Elogios, sugestões e críticas"'),
                  value: host._menuShowSac,
                  onChanged: host._menuSetShowSac,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Mostrar página "Quem somos"'),
                  value: host._menuShowQuemSomos,
                  onChanged: host._menuSetShowQuemSomos,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Mostrar "Dicas e informações" no menu'),
                  subtitle: const Text(
                    'Cuidados, garantias, qualidade – configurável na seção "Dicas e informações".',
                  ),
                  value: host._menuShowDicas,
                  onChanged: host._menuSetShowDicas,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title:
                      const Text('Exibir "Avaliações de clientes" no catálogo'),
                  subtitle: const Text(
                    'Mostra seção de depoimentos por loja no catálogo web.',
                  ),
                  value: host._exibirAvaliacoesCatalogo,
                  onChanged: host._menuSetExibirAvaliacoesCatalogo,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: DropdownButtonFormField<CatalogAvaliacoesOrdem>(
                    value: host._catalogAvaliacoesOrdem,
                    decoration: const InputDecoration(
                      labelText: 'Ordem dos depoimentos (carrossel)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: CatalogAvaliacoesOrdem.values
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e.labelConfig),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      host._menuSetCatalogAvaliacoesOrdem(v);
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                      'No celular, mostrar menu em cards na tela inicial'),
                  subtitle: const Text(
                    'Quando ativo, o catálogo mobile mostra um grid de atalhos.',
                  ),
                  value: host._showMobileMenuGrid,
                  onChanged: host._menuSetShowMobileMenuGrid,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Página "Quem somos"',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._quemSomosTituloCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._quemSomosTextoCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Texto de apresentação da loja',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText:
                          'Esse texto aparecerá quando o cliente clicar em "Quem somos".',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Página "Sobre a loja" no catálogo',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'O botão "Sobre a loja" no rodapé do catálogo abre esta página. '
                    'Use URL completa (https://...) para o banner — ex.: imagem no Firebase Storage.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  host._buildSobreLojaPreview(context),
                  const SizedBox(height: 12),
                  TextField(
                    controller: host._sobreLojaTituloCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Título da página',
                      hintText: 'Ex.: Nossa história',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaSubtituloCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Subtítulo / slogan',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ImageFieldWithGallery(
                    label: 'Banner',
                    controller: host._sobreLojaBannerUrlCtrl,
                    onChanged: host._scheduleAutoSave,
                    onPickImage: host._pickAndUploadSobreLojaBanner,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaIntroCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'História e apresentação',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText:
                          'Parágrafos separados por linha em branco ficam bem na página.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaMissaoCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Missão',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaVisaoCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Visão',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaValoresCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Valores',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaDestaquesCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Destaques (um por linha)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText: 'Ex.: Entrega para todo o Brasil',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaEnderecoCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Endereço (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaHorarioCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Horário de atendimento',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sobreLojaEmailCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail de exibição (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar razão social e CNPJ na página'),
                    subtitle: Text(
                      'Usa os dados do bloco Rodapé (razão e CNPJ).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: host._sobreLojaMostrarLegais,
                    onChanged: host._menuSetSobreLojaMostrarLegais,
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: host._sobreCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    decoration: const InputDecoration(
                      labelText: 'Site ou página externa (opcional)',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                      helperText:
                          'Se preenchido, aparece o botão "Visitar site" na página Sobre.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SAC – Elogios, sugestões e críticas',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sacWhatsappCtrl,
                    focusNode: host._focusSacWhatsapp,
                    onChanged: (_) {
                      host._limparErroCampo('sac_whatsapp');
                      host._scheduleAutoSave();
                    },
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9\s\-+()]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'WhatsApp do SAC (opcional)',
                      helperText:
                          'Ex: 5533999999999 - Se vazio, será usado o mesmo WhatsApp do vendedor.',
                      errorText: host._camposComErro.contains('sac_whatsapp')
                          ? 'Use 10 a 15 dígitos'
                          : null,
                      border: const OutlineInputBorder(),
                      errorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                            color: _LojaConfigScreenState._errorColor,
                            width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      prefixIcon: const Icon(Icons.chat),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: host._sacEmailCtrl,
                    onChanged: (_) => host._scheduleAutoSave(),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail do SAC (opcional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const _PaneMutedIntroText(
                    'Esses dados serão usados no menu do catálogo para o cliente enviar '
                    'elogios, sugestões e reclamações.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
