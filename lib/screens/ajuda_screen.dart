import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/master_config_service.dart';
import '../themes/app_colors.dart';

class AjudaScreen extends StatelessWidget {
  const AjudaScreen({super.key});

  Future<void> _abrirWhatsApp(String telefone) async {
    final tel = telefone.replaceAll(RegExp(r'[^\d]'), '');
    if (tel.isEmpty) return;
    // Garante c?digo do Brasil se n?o tiver
    final numero = tel.startsWith('55') • tel : '55$tel';
    const mensagem = 'Ol?! Tenho uma d?vida sobre o sistema e gostaria de ajuda.';
    final uri = Uri.parse(
      'https://wa.me/$numero?text=${Uri.encodeComponent(mensagem)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark • cs.primary : AppColors.primary;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: isDark • cs.primary : AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Ajuda'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildSuporteCard(context, primaryColor, cs),
          const SizedBox(height: 24),
          _buildCardPrecificacao(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardEstoque(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardVendas(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardFinanceiro(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardClientes(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardFornecedores(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardCatalogo(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardPedidos(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardMetas(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardRelatorios(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardCampanhasSorteios(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardFretesCupons(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardPagamentos(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardCanaisMeta(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardVendedores(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardMarketplace(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardNotasFiscais(context, primaryColor, cs),
          const SizedBox(height: 16),
          _buildCardFerramentas(context, primaryColor, cs),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSuporteCard(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return FutureBuilder<String>(
      future: MasterConfigService.getSupportPhone(),
      builder: (context, snap) {
        final phone = (snap.data ?• '').trim();
        if (phone.isEmpty) return const SizedBox.shrink();

        return Card(
          elevation: 0,
          color: const Color(0xFF25D366).withValues(alpha:0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: const Color(0xFF25D366).withValues(alpha:0.4),
            ),
          ),
          child: InkWell(
            onTap: () => _abrirWhatsApp(phone),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha:0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat,
                      color: Color(0xFF25D366),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'D?vidas• Fale conosco pelo WhatsApp',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phone,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF25D366),
                          ),
                        ),
                        Text(
                          'Toque para abrir WhatsApp com mensagem pronta',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: cs.onSurfaceVariant,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color primaryColor, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: primaryColor.withValues(alpha:0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: primaryColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Como usar o sistema',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Aqui voc• encontra explica??es detalhadas de cada tela e como s?o feitos os c?lculos. '
              'Role para baixo e toque nos cards para expandir.',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAjudaCard({
    required BuildContext context,
    required String titulo,
    required IconData icone,
    required Color cor,
    required ColorScheme cs,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cor.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, color: cor, size: 24),
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          'Toque para expandir',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        children: children,
      ),
    );
  }

  Widget _buildCardPrecificacao(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Precifica??o',
      icone: Icons.calculate,
      cor: Colors.green,
      cs: cs,
      children: [
        _buildParagrafo(
          'A tela de Precifica??o permite calcular o pre?o de venda sugerido para seus produtos com base no custo e nas taxas operacionais.',
        ),
        _buildSubtitulo('Como adicionar produtos:'),
        _buildItemLista('Importar Excel: planilha com colunas Nome (A), Custo (B), Quantidade (C). Custo em reais (ex: 22,50).'),
        _buildItemLista('Adicionar manualmente: informe nome, custo (ex: 10,90) e quantidade.'),
        _buildSubtitulo('F?rmula do pre?o sugerido:'),
        _buildFormula(
          '1. Custo por item = Custo + Frete/(n• produtos)\n'
          '2. Total de custos = Custo por item • (1 + Gastos Fixos%/100 + MEI%/100) + Embalagem\n'
          '3. Pre?o sem taxa = Total de custos • (Markup/100)\n'
          '4. Pre?o final = Pre?o sem taxa • (1 + Taxa cart?o%/100)',
        ),
        _buildSubtitulo('Exemplo pr?tico:'),
        _buildParagrafo(
          'Produto com custo R\$ 20,00, Markup 150%, Gastos Fixos 10%, MEI 3,5%, '
          'Embalagem R\$ 3, Frete R\$ 0, Taxa cart?o 5%. '
          'Total custos • R\$ 27,70. Pre?o sem taxa = R\$ 41,55. Pre?o final • R\$ 43,63.',
        ),
        _buildSubtitulo('Pre?o Pretendido:'),
        _buildParagrafo(
          'Voc• pode informar um pre?o desejado para cada produto. Se preenchido, ele substitui o pre?o sugerido na hora de confirmar.',
        ),
      ],
    );
  }

  Widget _buildCardEstoque(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Estoque',
      icone: Icons.inventory_2,
      cor: primaryColor,
      cs: cs,
      children: [
        _buildParagrafo(
          'O Estoque gerencia todos os produtos da loja: cadastro, quantidade, custo e pre?o de venda.',
        ),
        _buildSubtitulo('Funcionalidades:'),
        _buildItemLista('Cadastrar produtos: nome, custo, pre?o, quantidade em estoque.'),
        _buildItemLista('Editar e excluir produtos.'),
        _buildItemLista('Buscar produtos por nome.'),
        _buildItemLista('Ao registrar uma venda, o estoque • baixado automaticamente.'),
        _buildSubtitulo('Dicas:'),
        _buildParagrafo(
          'Use a Precifica??o para calcular pre?os em lote e depois confirme para atualizar o estoque. '
          'Mantenha custos e quantidades atualizados para relat?rios precisos.',
        ),
      ],
    );
  }

  Widget _buildCardVendas(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Vendas',
      icone: Icons.point_of_sale,
      cor: Colors.green,
      cs: cs,
      children: [
        _buildParagrafo(
          'Na tela de Vendas voc• registra as vendas da loja: adiciona produtos, define cliente e formas de pagamento.',
        ),
        _buildSubtitulo('Fluxo de uma venda:'),
        _buildItemLista('Nova venda: selecione produtos e quantidades.'),
        _buildItemLista('Informe o cliente (obrigat?rio para finalizar).'),
        _buildItemLista('Divida o pagamento: Dinheiro, Pix, Cart?o separadamente.'),
        _buildItemLista('Finalize: estoque • baixado e a venda entra no relat?rio financeiro.'),
        _buildSubtitulo('Editar venda:'),
        _buildParagrafo(
          'Voc• pode editar vendas j• registradas: alterar cliente, produtos e formas de pagamento. '
          'O estoque • ajustado automaticamente (devolve itens antigos e baixa novos).',
        ),
      ],
    );
  }

  Widget _buildCardFinanceiro(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Financeiro & Metas',
      icone: Icons.trending_up,
      cor: Colors.blue,
      cs: cs,
      children: [
        _buildParagrafo(
          'O relat?rio financeiro mostra vendas, recebimentos e metas em cards separados por forma de pagamento.',
        ),
        _buildSubtitulo('O que voc• v?:'),
        _buildItemLista('Dinheiro: total em vendas pagas em dinheiro.'),
        _buildItemLista('Pix: total em vendas pagas via Pix.'),
        _buildItemLista('Cart?o: total em vendas pagas com cart?o.'),
        _buildItemLista('Per?odo: filtre por data para an?lises espec?ficas.'),
        _buildSubtitulo('Metas:'),
        _buildParagrafo(
          'Configure metas de vendas e acompanhe o progresso. ?til para planejamento e comiss?es.',
        ),
      ],
    );
  }

  Widget _buildCardClientes(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Clientes',
      icone: Icons.people,
      cor: Colors.indigo,
      cs: cs,
      children: [
        _buildParagrafo(
          'Cadastro de clientes para associar ?s vendas. O nome do cliente • obrigat?rio ao finalizar uma venda.',
        ),
        _buildSubtitulo('Dados do cliente:'),
        _buildItemLista('Nome, telefone, e-mail (opcionais).'),
        _buildItemLista('Hist?rico de compras vinculado ao cliente.'),
        _buildParagrafo(
          'Clientes cadastrados facilitam o atendimento e permitem an?lises de recorr?ncia.',
        ),
      ],
    );
  }

  Widget _buildCardFornecedores(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Fornecedores',
      icone: Icons.local_shipping,
      cor: Colors.orange,
      cs: cs,
      children: [
        _buildParagrafo(
          'Cadastre fornecedores para organizar suas compras e vincular produtos • origem.',
        ),
        _buildSubtitulo('Uso:'),
        _buildItemLista('Nome, contato e observa??es.'),
        _buildItemLista('Refer?ncia para controle de compras e precifica??o.'),
      ],
    );
  }

  Widget _buildCardCatalogo(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Cat?logo / Loja',
      icone: Icons.storefront,
      cor: Colors.green,
      cs: cs,
      children: [
        _buildParagrafo(
          'Visualize sua loja como o cliente v?: produtos, categorias e layout do cat?logo p?blico.',
        ),
        _buildSubtitulo('Configura??es do Cat?logo:'),
        _buildItemLista('Defina categorias, imagens e ordem dos itens no menu.'),
        _buildItemLista('Personalize cores, logo e textos da loja.'),
        _buildParagrafo(
          'As altera??es no estoque refletem automaticamente no cat?logo.',
        ),
      ],
    );
  }

  Widget _buildCardPedidos(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Pedidos',
      icone: Icons.shopping_cart,
      cor: Colors.teal,
      cs: cs,
      children: [
        _buildParagrafo(
          'Pedidos vindos do cat?logo web ou canais de venda (WhatsApp, Instagram).',
        ),
        _buildSubtitulo('Fluxo:'),
        _buildItemLista('Cliente faz pedido pelo site ou link.'),
        _buildItemLista('Pedido aparece em Pedidos pendentes.'),
        _buildItemLista('Converta em venda ou gerencie status (confirmado, enviado etc.).'),
      ],
    );
  }

  Widget _buildCardMetas(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Metas e Comiss?es',
      icone: Icons.emoji_events,
      cor: Colors.amber,
      cs: cs,
      children: [
        _buildParagrafo(
          'Configure metas de vendas e comiss?es para vendedores. Acompanhe o desempenho em tempo real.',
        ),
        _buildSubtitulo('Como funciona:'),
        _buildItemLista('Defina meta em valor (ex: R\$ 5.000/m?s).'),
        _buildItemLista('Comiss?o: percentual sobre as vendas do vendedor.'),
        _buildItemLista('Relat?rio mostra quanto cada um vendeu e quanto deve receber.'),
      ],
    );
  }

  Widget _buildCardRelatorios(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Relat?rios Financeiros',
      icone: Icons.bar_chart,
      cor: Colors.blue,
      cs: cs,
      children: [
        _buildParagrafo(
          'O relat?rio financeiro consolida todas as vendas por per?odo e forma de pagamento. '
          'Admin e programador veem tudo; vendedores veem apenas suas pr?prias vendas.',
        ),
        _buildSubtitulo('C?lculos:'),
        _buildItemLista('Total vendas = soma do valor de cada venda no per?odo filtrado.'),
        _buildItemLista('Dinheiro: soma das vendas com pagamento em dinheiro.'),
        _buildItemLista('Pix: soma das vendas pagas via Pix.'),
        _buildItemLista('Cart?o: soma das vendas pagas com cart?o (cr?dito/d?bito).'),
        _buildSubtitulo('L?quido (recebido):'),
        _buildParagrafo(
          'O valor l?quido considera descontos de taxa de cart?o e MEI, quando configurados. '
          'Ex: venda R\$ 100 em cart?o com taxa 5% • l?quido • R\$ 95.',
        ),
        _buildSubtitulo('Filtros:'),
        _buildItemLista('Per?odo: dia, semana, m?s ou intervalo personalizado.'),
        _buildItemLista('Vendedor: filtre por vendedor ou veja o geral.'),
      ],
    );
  }

  Widget _buildCardCampanhasSorteios(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Campanhas e Sorteios',
      icone: Icons.card_giftcard,
      cor: Colors.purple,
      cs: cs,
      children: [
        _buildParagrafo(
          'Crie campanhas promocionais com sorteios para engajar clientes. '
          'Clientes compram e ganham n?meros para participar do sorteio.',
        ),
        _buildSubtitulo('Como funciona:'),
        _buildItemLista('Crie uma campanha: defina nome, data de in?cio e fim.'),
        _buildItemLista('Configure regras: ex: a cada R\$ 50 em compra = 1 n?mero.'),
        _buildItemLista('Clientes que compram no per?odo participam automaticamente.'),
        _buildItemLista('Realize o sorteio na data definida (roleta ou sorteio manual).'),
        _buildSubtitulo('Roleta da Sorte:'),
        _buildParagrafo(
          'Ferramenta separada das campanhas. O cliente gira a roleta ap?s a compra e pode ganhar pr?mios instant?neos (cupom de desconto, frete gr?tis ou "tente novamente").',
        ),
        _buildItemLista('Configurar: em Campanhas e Sorteios, abra a aba Roleta. Ative, defina o valor m?nimo da compra para liberar o giro e cadastre os pr?mios (label, tipo e valor).'),
        _buildItemLista('Funcionamento: ao finalizar compra acima do valor m?nimo, o cliente v• o bot?o "Girar roleta", gira uma vez e recebe o pr?mio (ou n?o). Uma rota??o por compra.'),
        _buildItemLista('Cupom ganho: s• pode ser usado na pr?xima compra e possui validade. Ap?s usado ou vencido, n?o • mais aceito.'),
        _buildSubtitulo('Dica:'),
        _buildParagrafo(
          'Use campanhas para datas especiais, promo??es de fim de ano ou fideliza??o de clientes. Use a roleta para premia??o imediata e engajamento p?s-compra.',
        ),
      ],
    );
  }

  Widget _buildCardFretesCupons(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Fretes e Cupons',
      icone: Icons.local_shipping,
      cor: Colors.teal,
      cs: cs,
      children: [
        _buildParagrafo(
          'Configure op??es de frete e cupons de desconto para o cat?logo web.',
        ),
        _buildSubtitulo('Fretes:'),
        _buildItemLista('Manual: defina op??es fixas (Retirada, Entrega local, Combinar).'),
        _buildItemLista('Integra??es: Melhor Envio, Frenet, Correios, SuperFrete (por CEP).'),
        _buildItemLista('Embalagens: peso e dimens?es para c?lculo autom?tico.'),
        _buildSubtitulo('Cupons:'),
        _buildItemLista('Crie cupons com c?digo (ex: PROMO10) e valor ou percentual de desconto.'),
        _buildItemLista('Data de validade e uso ?nico ou m?ltiplo.'),
        _buildItemLista('O cliente insere o cupom no checkout para obter o desconto.'),
      ],
    );
  }

  Widget _buildCardPagamentos(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Configurar Pagamentos',
      icone: Icons.payments,
      cor: Colors.green,
      cs: cs,
      children: [
        _buildParagrafo(
          'Configure as formas de pagamento aceitas pela loja: Pix, cart?o e Mercado Pago.',
        ),
        _buildSubtitulo('Op??es:'),
        _buildItemLista('Pix: chave Pix para pagamento manual (cliente transfere e confirma).'),
        _buildItemLista('Cart?o: integra??o com Mercado Pago para cobran?a autom?tica.'),
        _buildItemLista('Configura??es Master: token de acesso do Mercado Pago (admin).'),
        _buildParagrafo(
          'Sem Mercado Pago configurado, o checkout aceita apenas Pix e pagamento manual.',
        ),
      ],
    );
  }

  Widget _buildCardCanaisMeta(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Canais Meta (WhatsApp, Instagram, Messenger)',
      icone: Icons.chat,
      cor: const Color(0xFF25D366),
      cs: cs,
      children: [
        _buildParagrafo(
          'Conecte sua loja aos canais de atendimento: WhatsApp, Instagram e Messenger. '
          'Clientes podem iniciar conversas e pedidos direto pelo app.',
        ),
        _buildSubtitulo('O que configurar:'),
        _buildItemLista('N?mero de WhatsApp Business para atendimento.'),
        _buildItemLista('Link do Instagram e perfil da loja.'),
        _buildItemLista('Integra??o com Meta Business para mensagens unificadas.'),
        _buildParagrafo(
          'Facilita vendas por redes sociais: o cliente clica e j• abre o chat com a mensagem pronta.',
        ),
      ],
    );
  }

  Widget _buildCardVendedores(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Vendedores',
      icone: Icons.badge,
      cor: Colors.indigo,
      cs: cs,
      children: [
        _buildParagrafo(
          'Cadastre vendedores da loja e defina permiss?es. Cada venda pode ser vinculada a um vendedor para controle de comiss?es.',
        ),
        _buildSubtitulo('Funcionalidades:'),
        _buildItemLista('Cadastro: nome, e-mail, permiss?es (estoque, vendas, clientes, etc.).'),
        _buildItemLista('Vendas: ao registrar, escolha o vendedor respons?vel.'),
        _buildItemLista('Relat?rio: veja vendas por vendedor para c?lculo de comiss?o.'),
        _buildParagrafo(
          'Admin e programador veem todos os vendedores; vendedores veem apenas o pr?prio desempenho.',
        ),
      ],
    );
  }

  Widget _buildCardMarketplace(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Marketplace / ERP',
      icone: Icons.store_mall_directory,
      cor: Colors.deepOrange,
      cs: cs,
      children: [
        _buildParagrafo(
          'Integre sua loja com marketplaces externos ou ERPs para sincronizar produtos, estoque e pedidos.',
        ),
        _buildSubtitulo('Para que serve:'),
        _buildItemLista('Vender em mais de um canal (site + marketplace).'),
        _buildItemLista('Manter estoque e pre?os sincronizados automaticamente.'),
        _buildItemLista('Centralizar pedidos em um ?nico painel.'),
        _buildParagrafo(
          'Configure as credenciais e mapeamento de dados conforme a plataforma escolhida.',
        ),
      ],
    );
  }

  Widget _buildCardNotasFiscais(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Notas Fiscais',
      icone: Icons.receipt_long,
      cor: Colors.brown,
      cs: cs,
      children: [
        _buildParagrafo(
          'Gerencie a emiss?o de notas fiscais das vendas. '
          'Necess?rio para regularidade fiscal e envio a clientes.',
        ),
        _buildSubtitulo('Uso:'),
        _buildItemLista('Visualize vendas que precisam de NF-e.'),
        _buildItemLista('Integre com sistema de emiss?o (conforme disponibilidade).'),
        _buildItemLista('Mantenha hist?rico para consulta e auditoria.'),
      ],
    );
  }

  Widget _buildCardFerramentas(
      BuildContext context, Color primaryColor, ColorScheme cs) {
    return _buildAjudaCard(
      context: context,
      titulo: 'Ferramentas do Sistema (Menu Dados)',
      icone: Icons.build,
      cor: primaryColor,
      cs: cs,
      children: [
        _buildSubtitulo('Sincronizar Firestore:'),
        _buildParagrafo(
          'Envia os dados da loja (produtos, vendas, clientes) do aplicativo para o Firebase Firestore. '
          'Use quando fizer altera??es no app e quiser que o cat?logo web e outros dispositivos recebam essas atualiza??es. '
          'Sincroniza em tempo real com a nuvem.',
        ),
        _buildSubtitulo('Backup da Loja:'),
        _buildParagrafo(
          'Cria uma c?pia de seguran?a dos dados da loja no dispositivo. '
          'Guarde o arquivo em local seguro para restaurar em caso de troca de celular ou perda de dados. '
          'Recomendado fazer backup peri?dico.',
        ),
        _buildSubtitulo('Consolidar Loja:'),
        _buildParagrafo(
          'Une dados de m?ltiplas lojas em uma ?nica. '
          '?til quando voc• tem mais de uma loja (ex: matriz e filial) e quer centralizar estoque, vendas e clientes em um s• lugar.',
        ),
        _buildSubtitulo('Planos:'),
        _buildParagrafo(
          'Visualize e gerencie o plano de assinatura da sua loja. '
          'Diferentes planos liberam recursos como integra??es, quantidade de produtos e canais de venda. '
          'Renova??o e pagamento s?o feitos conforme o plano ativo.',
        ),
        _buildSubtitulo('Importar do Firestore:'),
        _buildParagrafo(
          'Busca dados que est?o no Firebase Firestore e traz para o aplicativo. '
          'Use quando trocar de celular, reinstalar o app ou quiser recuperar dados que foram salvos na nuvem. '
          'Complementa o Backup: Backup salva localmente; Importar busca da nuvem.',
        ),
      ],
    );
  }

  Widget _buildParagrafo(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
    );
  }

  Widget _buildSubtitulo(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildItemLista(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildFormula(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha:0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.6,
        ),
      ),
    );
  }
}

