import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../utils/image_helper.dart' as img_helper;
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/hive_box_names.dart';
import '../services/store_resolver_facade.dart';
import '../services/catalogo_config_service.dart';
import '../models/produto_catalogo.dart';
import '../models/catalogo_config.dart';
import '../models/cliente_web.dart';
import '../services/cliente_web_service.dart';
import 'package:master_palm/screens/cliente_login_screen.dart';
import 'cliente_perfil_screen.dart';

class CartItem {
  final ProdutoCatalogo produto;
  String? tamanho;
  String? cor;
  int quantidade;

  CartItem({
    required this.produto,
    this.tamanho,
    this.cor,
    this.quantidade = 1,
  });
}

/// LEGADO (FASE 4): Usa ClienteWebService (clientes_web). Catálogo admin (rota /catalogo).
/// Para catálogo público use PublicCatalogScreen + ClienteAuthService (clientes).
class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  Box<ProdutoCatalogo>? produtosBox;
  CatalogoConfig? config;

  String busca = '';
  final List<CartItem> _carrinho = [];

  // Cliente autenticado
  ClienteWeb? _clienteAutenticado;
  String? _lojaId;

  // Cupom aplicado
  CupomCliente? _cupomAplicado;

  @override
  void initState() {
    super.initState();
    _abrirBoxes();
    _carregarCliente();
  }

  Future<void> _abrirBoxes() async {
    // ✅ Usar StoreResolverFacade (mesma lógica da loja modelo): NUNCA Hive direto.
    // Hive sessao pode ter store_id de outro usuário (IndexedDB compartilhado no Web).
    _lojaId = await StoreResolverFacade.resolveForAdminApp();
    final lojaId = _lojaId?.trim().isNotEmpty == true ? _lojaId! : '';

    if (lojaId.isEmpty) {
      if (mounted) setState(() {});
      return; // Não abrir catálogo sem loja definida (evita fallback perigoso).
    }

    produtosBox = await Hive.openBox<ProdutoCatalogo>('catalogo_$lojaId');

    // ✅ Config da MESMA loja: Firestore lojas/{lojaId}/config_catalogo_live (per-store).
    final cfgLive = await CatalogoConfigService.loadLiveForLoja(lojaId);
    if (cfgLive != null) {
      config = cfgLive;
    } else {
      final boxLocal = await Hive.openBox<CatalogoConfig>(
        HiveBoxNames.configCatalogoLoja(lojaId),
      );
      if (boxLocal.isNotEmpty) {
        config = boxLocal.values.first;
      } else {
        config = CatalogoConfig(
          corFundo: '0xFF000000',
          corTexto: '0xFFFFFFFF',
          corBotao: '0xFF2196F3',
          fonte: 'Arial',
          tamanhoFonte: 14,
        );
      }
    }

    if (mounted) setState(() {});
  }

  /// Carrega cliente autenticado e verifica cupons disponíveis
  Future<void> _carregarCliente() async {
    if (_lojaId == null) return;

    try {
      final cliente = await ClienteWebService.getClienteAutenticado(_lojaId!);
      if (cliente != null && mounted) {
        setState(() {
          _clienteAutenticado = cliente;
        });

        // Verifica se tem cupom disponível e aplica automaticamente
        await _aplicarCupomAutomatico();
      }
    } catch (e) {
      debugPrint('Erro ao carregar cliente (type=${e.runtimeType})');
    }
  }

  /// Aplica cupom automaticamente se o cliente tiver cupom disponível
  Future<void> _aplicarCupomAutomatico() async {
    if (_clienteAutenticado == null || _lojaId == null) return;

    try {
      final cupom = await ClienteWebService.getCupomValido(
        lojaId: _lojaId!,
        clienteId: _clienteAutenticado!.id,
      );

      if (cupom != null && mounted) {
        setState(() {
          _cupomAplicado = cupom;
        });
        debugPrint('✅ Cupom aplicado automaticamente: ${cupom.codigo} (${cupom.desconto}% OFF)');
      }
    } catch (e) {
      debugPrint('Erro ao aplicar cupom (type=${e.runtimeType})');
    }
  }

  /// Abre tela de login/cadastro
  Future<void> _abrirLogin() async {
    if (_lojaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loja não configurada')),
      );
      return;
    }

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClienteLoginScreen(
          lojaId: _lojaId!,
          lojaNome: 'MasterPalm',
        ),
      ),
    );

    if (result is ClienteWeb) {
      setState(() {
        _clienteAutenticado = result;
      });
      await _aplicarCupomAutomatico();
    }
  }

  /// Abre tela de perfil do cliente
  Future<void> _abrirPerfil() async {
    if (_clienteAutenticado == null || _lojaId == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientePerfilScreen(
          lojaId: _lojaId!,
          cliente: _clienteAutenticado!,
        ),
      ),
    );

    // Se retornou true, significa que fez logout
    if (result == true) {
      setState(() {
        _clienteAutenticado = null;
        _cupomAplicado = null;
      });
    } else {
      // Recarregar cliente para atualizar cupons
      await _carregarCliente();
    }
  }

  Color corHex(String hex) {
    try {
      return Color(int.parse(hex));
    } catch (_) {
      return Colors.black;
    }
  }

  void _addCarrinho(ProdutoCatalogo produto, {String? tamanho, String? cor}) {
    final idx = _carrinho.indexWhere(
      (e) =>
          e.produto.key == produto.key &&
          (e.tamanho ?? '') == (tamanho ?? '') &&
          (e.cor ?? '') == (cor ?? ''),
    );
    if (idx >= 0) {
      if (_carrinho[idx].quantidade < produto.quantidade) {
        setState(() => _carrinho[idx].quantidade += 1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantidade máxima em estoque.')),
        );
      }
    } else {
      setState(() => _carrinho.add(
          CartItem(produto: produto, tamanho: tamanho, cor: cor, quantidade: 1)));
    }
  }

  double _totalCarrinho() {
    final subtotal = _carrinho.fold(
        0.0, (acc, e) => acc + (e.produto.precoFinal * e.quantidade));

    // Aplica cupom se houver
    if (_cupomAplicado != null) {
      final desconto = subtotal * (_cupomAplicado!.desconto / 100);
      return subtotal - desconto;
    }

    return subtotal;
  }

  /// Retorna o subtotal sem desconto
  double _subtotalCarrinho() {
    return _carrinho.fold(
        0.0, (acc, e) => acc + (e.produto.precoFinal * e.quantidade));
  }

  /// Retorna o valor do desconto aplicado
  double _descontoCarrinho() {
    if (_cupomAplicado == null) return 0.0;
    final subtotal = _subtotalCarrinho();
    return subtotal * (_cupomAplicado!.desconto / 100);
  }

  Future<void> _finalizarPedido() async {
    if (_carrinho.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carrinho vazio')),
      );
      return;
    }

    final form = GlobalKey<FormState>();
    final nomeCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    String pagamento = 'Pix';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar pedido'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(labelText: 'Nome completo'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone/WhatsApp',
                    helperText: 'Ex: 5533999999999',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o telefone'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: endCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Endereço completo'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o endereço'
                      : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: pagamento,
                  items: const [
                    DropdownMenuItem(value: 'Pix', child: Text('Pix')),
                    DropdownMenuItem(
                        value: 'Dinheiro', child: Text('Dinheiro')),
                    DropdownMenuItem(value: 'Cartão', child: Text('Cartão')),
                  ],
                  onChanged: (v) => pagamento = v ?? 'Pix',
                  decoration:
                      const InputDecoration(labelText: 'Forma de pagamento'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (form.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final total = _totalCarrinho();
    final data = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // monta mensagem
    final sb = StringBuffer();
    sb.writeln('🛍️ Novo Pedido do Catálogo');
    sb.writeln('Data: $data');
    sb.writeln('');
    sb.writeln('Itens:');
    for (final item in _carrinho) {
      final tam =
          (item.tamanho?.isNotEmpty ?? false) ? ' - Tamanho: ${item.tamanho}' : '';
      final corStr =
          (item.cor?.isNotEmpty ?? false) ? ' - Cor: ${item.cor}' : '';
      sb.writeln(
          '${item.quantidade}x ${item.produto.nome}$tam$corStr - R\$ ${item.produto.precoFinal.toStringAsFixed(2)}');
    }
    sb.writeln('');

    // Mostrar desconto do cupom se houver
    if (_cupomAplicado != null) {
      sb.writeln('Subtotal: R\$ ${_subtotalCarrinho().toStringAsFixed(2)}');
      sb.writeln('Cupom ${_cupomAplicado!.codigo} (${_cupomAplicado!.desconto}% OFF): - R\$ ${_descontoCarrinho().toStringAsFixed(2)}');
    }

    sb.writeln('Total: R\$ ${total.toStringAsFixed(2)}');
    sb.writeln('Pagamento: $pagamento');
    sb.writeln('');
    sb.writeln('Cliente: ${nomeCtrl.text}');
    sb.writeln('Telefone: ${telCtrl.text}');
    sb.writeln('Endereço: ${endCtrl.text}');

    // pega número salvo em Config (ou pede para configurar)
    final cfg = Hive.box('config');
   final numero = (cfg.get('whatsapp') ?? '') as String;
if (numero.isEmpty) {
  if (!mounted) return;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('WhatsApp não configurado'),
      content: const Text('Defina o número do vendedor nas configurações.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return;
}


    final msg = Uri.encodeComponent(sb.toString());
    final url = Uri.parse('https://wa.me/$numero?text=$msg');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);

      // Marcar cupom como usado se houver
      if (_cupomAplicado != null && _clienteAutenticado != null && _lojaId != null) {
        await ClienteWebService.usarCupom(
          lojaId: _lojaId!,
          clienteId: _clienteAutenticado!.id,
          codigo: _cupomAplicado!.codigo,
        );
        debugPrint('✅ Cupom ${_cupomAplicado!.codigo} marcado como usado');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abrindo WhatsApp...')),
      );
      setState(() {
        _carrinho.clear(); // limpa carrinho local após enviar
        _cupomAplicado = null; // limpa cupom aplicado
      });

      // Recarregar cliente para atualizar cupons
      await _carregarCliente();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  void _abrirCarrinho() {
    if (kDebugMode) {
      debugPrint(
        '[CART_WIDGET_REAL] OPEN_CARRINHO rota /catalogo → '
        'CatalogoScreen (modal legado; NÃO usa carrinho_sheet_web.dart)',
      );
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              top: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Seu carrinho',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_carrinho.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nenhum item no carrinho.'),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _carrinho.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = _carrinho[index];
                        final detalhes = <String>[];
                        if (item.tamanho?.isNotEmpty ?? false) {
                          detalhes.add('Tam: ${item.tamanho}');
                        }
                        if (item.cor?.isNotEmpty ?? false) {
                          detalhes.add('Cor: ${item.cor}');
                        }
                        final detalhesStr = detalhes.isNotEmpty ? ' (${detalhes.join(', ')})' : '';

                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.produto.nome}$detalhesStr\n'
                                'R\$ ${item.produto.precoFinal.toStringAsFixed(2)}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                if (item.quantidade > 1) {
                                  setModal(() => item.quantidade--);
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.remove_circle),
                            ),
                            Text('${item.quantidade}'),
                            IconButton(
                              onPressed: () {
                                if (item.quantidade < item.produto.quantidade) {
                                  setModal(() => item.quantidade++);
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.add_circle),
                            ),
                            IconButton(
                              onPressed: () {
                                setModal(() => _carrinho.removeAt(index));
                                setState(() {});
                              },
                              icon: const Icon(Icons.delete, color: Colors.red),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),

                // Cupom aplicado
                if (_cupomAplicado != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.card_giftcard, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cupom aplicado: ${_cupomAplicado!.codigo}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_cupomAplicado!.desconto}% de desconto',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Valores
                if (_cupomAplicado != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:'),
                      Text('R\$ ${_subtotalCarrinho().toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Desconto (${_cupomAplicado!.desconto}%):',
                        style: const TextStyle(color: Colors.green),
                      ),
                      Text(
                        '- R\$ ${_descontoCarrinho().toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                  const Divider(),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'R\$ ${_totalCarrinho().toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(FontAwesomeIcons.whatsapp,
                        color: Colors.white),
                    label: const Text('Finalizar pedido no WhatsApp'),
                    onPressed: _finalizarPedido,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Drawer (menu lateral) com opção de login/perfil
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  corHex(config?.corBotao ?? '0xFF2196F3'),
                  corHex(config?.corBotao ?? '0xFF2196F3').withOpacity(0.7),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(
                    _clienteAutenticado != null ? Icons.person : Icons.person_outline,
                    size: 35,
                    color: corHex(config?.corBotao ?? '0xFF2196F3'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _clienteAutenticado?.nome ?? 'Visitante',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_clienteAutenticado != null)
                  Text(
                    _clienteAutenticado!.email,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Minha Conta
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(_clienteAutenticado != null ? 'Meu Perfil' : 'Entrar / Cadastrar'),
            subtitle: _clienteAutenticado != null && _cupomAplicado != null
                ? Text(
                    'Cupom: ${_cupomAplicado!.desconto}% OFF',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  )
                : null,
            onTap: () {
              Navigator.pop(context);
              if (_clienteAutenticado != null) {
                _abrirPerfil();
              } else {
                _abrirLogin();
              }
            },
          ),

          const Divider(),

          // Informações
          if (_clienteAutenticado != null) ...[
            ListTile(
              leading: const Icon(Icons.card_giftcard),
              title: const Text('Meus Cupons'),
              trailing: _clienteAutenticado!.cuponsValidos.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_clienteAutenticado!.cuponsValidos.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                _abrirPerfil();
              },
            ),
            const Divider(),
          ],

          // Sobre
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Sobre'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: 'MasterPalm Catálogo',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2025 MasterPalm',
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (produtosBox == null || config == null) {
      final semLoja = _lojaId == null || _lojaId!.trim().isEmpty;
      return Scaffold(
        body: Center(
          child: semLoja
              ? const Text('Loja não definida. Selecione uma loja para acessar o catálogo.')
              : const CircularProgressIndicator(),
        ),
      );
    }

    final produtos = produtosBox!.values
        .where((p) => p.nome.toLowerCase().contains(busca.toLowerCase()))
        .toList();

    final tema = ThemeData(
      scaffoldBackgroundColor: corHex(config!.corFundo),
      textTheme: Theme.of(context).textTheme.apply(
            fontFamily: config!.fonte,
            bodyColor: corHex(config!.corTexto),
            displayColor: corHex(config!.corTexto),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: corHex(config!.corFundo),
        iconTheme: IconThemeData(color: corHex(config!.corTexto)),
        titleTextStyle: TextStyle(
          color: corHex(config!.corTexto),
          fontSize: 20,
          fontFamily: config!.fonte,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: corHex(config!.corBotao),
          foregroundColor: Colors.white,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: corHex(config!.corTexto)),
      ),
    );

    return Theme(
      data: tema,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo'),
          actions: [
            // Ícone de perfil
            if (_clienteAutenticado != null)
              IconButton(
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.person),
                    if (_cupomAplicado != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: _abrirPerfil,
                tooltip: _clienteAutenticado!.nome,
              ),

            // Carrinho
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: _abrirCarrinho,
                ),
                if (_carrinho.isNotEmpty)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_carrinho.fold<int>(0, (acc, e) => acc + e.quantidade)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        drawer: _buildDrawer(),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => setState(() => busca = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar produto...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: produtos.isEmpty
                  ? const Center(child: Text('Nenhum produto encontrado'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.66,
                      ),
                      itemCount: produtos.length,
                      itemBuilder: (context, index) {
                        final p = produtos[index];
                        String? tamanhoSelecionado =
                            (p.tamanhos.isNotEmpty) ? p.tamanhos.first : null;
                        String? corSelecionada;

                        // Se usa variações, pega as cores disponíveis para o tamanho selecionado
                        List<String> coresDisponiveis = [];
                        if (p.usaVariacoes && tamanhoSelecionado != null) {
                          coresDisponiveis = p.obterCoresPorTamanho(tamanhoSelecionado);
                          corSelecionada = coresDisponiveis.isNotEmpty ? coresDisponiveis.first : null;
                        } else if (p.cores.isNotEmpty) {
                          coresDisponiveis = p.cores;
                          corSelecionada = p.cores.first;
                        }

                        return StatefulBuilder(
                          builder: (context, setCard) {
                            return Card(
                              elevation: 4,
                              color: Colors.grey[900],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Imagem maior ocupando mais espaço no card
                                  Expanded(
                                    flex: 7,
                                    child: p.imagens.isNotEmpty
                                        ? img_helper.buildPlatformImage(
                                            p.imagens.first,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: Colors.grey[800],
                                              child: const Center(
                                                child: Icon(Icons.broken_image, size: 40),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: Colors.grey[800],
                                            child: const Center(
                                              child: Icon(Icons.image, size: 50),
                                            ),
                                          ),
                                  ),
                                  // Área de informações mais compacta
                                  Expanded(
                                    flex: 6,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // Nome e preço
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.nome,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'R\$ ${p.precoFinal.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          // Seletores de tamanho e cor
                                          Column(
                                            children: [
                                              // Seletor de tamanho compacto (se houver)
                                              if (p.tamanhos.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
                                                  child: DropdownButtonFormField<String>(
                                                    value: tamanhoSelecionado,
                                                    isDense: true,
                                                    items: p.tamanhos
                                                        .map((t) => DropdownMenuItem(
                                                            value: t,
                                                            child: Text(t,
                                                                style: const TextStyle(fontSize: 12))))
                                                        .toList(),
                                                    onChanged: (v) {
                                                      setCard(() {
                                                        tamanhoSelecionado = v;
                                                        // Atualiza cores disponíveis se usa variações
                                                        if (p.usaVariacoes && v != null) {
                                                          coresDisponiveis = p.obterCoresPorTamanho(v);
                                                          corSelecionada = coresDisponiveis.isNotEmpty
                                                              ? coresDisponiveis.first
                                                              : null;
                                                        }
                                                      });
                                                    },
                                                    decoration: const InputDecoration(
                                                      labelText: 'Tamanho',
                                                      filled: true,
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.symmetric(
                                                          horizontal: 8, vertical: 8),
                                                    ),
                                                  ),
                                                ),
                                              // Seletor de cor compacto (se houver)
                                              if (coresDisponiveis.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
                                                  child: DropdownButtonFormField<String>(
                                                    value: corSelecionada,
                                                    isDense: true,
                                                    items: coresDisponiveis
                                                        .map((c) => DropdownMenuItem(
                                                            value: c,
                                                            child: Row(
                                                              children: [
                                                                const Icon(Icons.palette,
                                                                    size: 14,
                                                                    color: Colors.pinkAccent),
                                                                const SizedBox(width: 4),
                                                                Text(c,
                                                                    style: const TextStyle(
                                                                        fontSize: 12)),
                                                              ],
                                                            )))
                                                        .toList(),
                                                    onChanged: (v) =>
                                                        setCard(() => corSelecionada = v),
                                                    decoration: const InputDecoration(
                                                      labelText: 'Cor',
                                                      filled: true,
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.symmetric(
                                                          horizontal: 8, vertical: 8),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          // Botão adicionar mais compacto e destacado
                                          SizedBox(
                                            width: double.infinity,
                                            height: 36,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                              ),
                                              onPressed: () => _addCarrinho(
                                                p,
                                                tamanho: tamanhoSelecionado,
                                                cor: corSelecionada,
                                              ),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.add_shopping_cart, size: 18),
                                                  SizedBox(width: 4),
                                                  Text('Adicionar',
                                                      style: TextStyle(fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

