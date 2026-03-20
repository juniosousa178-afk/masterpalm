// lib/screens/backup_screen_web.dart
// Versão web do BackupScreen: exporta dados como JSON para download.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../core/hive_box_names.dart';
import '../models/cliente.dart';
import '../models/fornecedor.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/venda_item.dart';
import '../services/loja_id_service.dart';
import '../services/notificacao_service.dart';
import '../src/file_saver.dart' as file_saver;

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenWebState();
}

class _BackupScreenWebState extends State<BackupScreen> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color successColor = Color(0xFF22C55E);
  static const Color surfaceColor = Color(0xFFF8FAFC);

  String _storeId = '';
  bool _isLoading = false;
  bool _storeIdLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreId();
  }

  /// ✅ Multi-loja: LojaIdService.get() primeiro (StoreResolver), Hive apenas fallback offline.
  /// Alinhado ao APK (backup_screen_mobile) para evitar store_id de outra conta no IndexedDB.
  Future<void> _loadStoreId() async {
    try {
      String• storeId = (await LojaIdService.get())?.trim();
      if (storeId == null || storeId.isEmpty) {
        try {
          if (Hive.isBoxOpen('sessao')) {
            storeId = Hive.box('sessao').get('store_id')?.toString().trim();
          }
          if ((storeId == null || storeId.isEmpty) && Hive.isBoxOpen('config')) {
            storeId = Hive.box('config').get('store_id')?.toString().trim();
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _storeId = storeId ?• '';
          _storeIdLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _storeId = '';
          _storeIdLoading = false;
        });
      }
    }
  }

  void _mostrarSnackBar(String mensagem, IconData icone, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icone, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(mensagem, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static Map<String, dynamic> _clienteToMap(Cliente c) => {
        'nome': c.nome,
        'telefone': c.telefone,
        'instagram': c.instagram,
        'cep': c.cep,
        'cidade': c.cidade,
        'email': c.email,
        'endereco': c.endereco,
        'lojaId': c.lojaId,
        'idFirebase': c.idFirebase,
      };

  static Map<String, dynamic> _vendaItemToMap(VendaItem i) => {
        'produtoNome': i.produtoNome,
        'quantidade': i.quantidade,
        'precoUnitario': i.precoUnitario,
        'tamanho': i.tamanho,
        'cor': i.cor,
      };

  static Map<String, dynamic> _vendaToMap(Venda v) => {
        'preco': v.preco,
        'produtosDescricao': v.produtosDescricao,
        'quantidade': v.quantidade,
        'clienteNome': v.clienteNome,
        'total': v.total,
        'formasPagamento': v.formasPagamento,
        'data': v.data.toIso8601String(),
        'tamanho': v.tamanho,
        'desconto': v.desconto,
        'frete': v.frete,
        'vendedor': v.vendedor,
        'observacao': v.observacao,
        'lojaId': v.lojaId,
        'idFirebase': v.idFirebase,
        'clienteId': v.clienteId,
        'itens': (v.itens ?• []).map(_vendaItemToMap).toList(),
      };

  static Map<String, dynamic> _fornecedorToMap(Fornecedor f) => {
        'nome': f.nome,
        'telefone': f.telefone,
        'email': f.email,
        'dataCadastro': f.dataCadastro.toIso8601String(),
        'instagram': f.instagram,
        'whatsapp': f.whatsapp,
        'lojaId': f.lojaId,
      };

  static Map<String, dynamic> _produtoToMap(Produto p) => {
        'nome': p.nome,
        'custoReal': p.custoReal,
        'frete': p.frete,
        'gastosFixos': p.gastosFixos,
        'gastosVariaveis': p.gastosVariaveis,
        'precoSugerido': p.precoSugerido,
        'precoFinal': p.precoFinal,
        'quantidade': p.quantidade,
        'precoUnitario': p.precoUnitario,
        'categoria': p.categoria,
        'dataEntrada': p.dataEntrada.toIso8601String(),
        'descricao': p.descricao,
        'imagens': p.imagens,
        'publicadoNoCatalogo': p.publicadoNoCatalogo,
        'slug': p.slug,
        'subcategoria': p.subcategoria,
        'ativoNoRascunho': p.ativoNoRascunho,
        'idFirebase': p.idFirebase,
        'lojaId': p.lojaId,
        'codigoBarras': p.codigoBarras,
      };

  Future<void> _exportarBackupWeb() async {
    if (_storeId.isEmpty) {
      _mostrarSnackBar('Selecione uma loja para exportar o backup.', Icons.warning_amber_rounded, Colors.orange);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final clientesBox = Hive.isBoxOpen(HiveBoxNames.clientes(_storeId))
          • Hive.box<Cliente>(HiveBoxNames.clientes(_storeId))
          : await Hive.openBox<Cliente>(HiveBoxNames.clientes(_storeId));
      final produtosBox = Hive.isBoxOpen(HiveBoxNames.produtos(_storeId))
          • Hive.box<Produto>(HiveBoxNames.produtos(_storeId))
          : await Hive.openBox<Produto>(HiveBoxNames.produtos(_storeId));
      final vendasBox = Hive.isBoxOpen(HiveBoxNames.vendas(_storeId))
          • Hive.box<Venda>(HiveBoxNames.vendas(_storeId))
          : await Hive.openBox<Venda>(HiveBoxNames.vendas(_storeId));
      final fornecedoresBox = Hive.isBoxOpen(HiveBoxNames.fornecedores(_storeId))
          • Hive.box<Fornecedor>(HiveBoxNames.fornecedores(_storeId))
          : await Hive.openBox<Fornecedor>(HiveBoxNames.fornecedores(_storeId));

      final data = {
        'exportadoEm': DateTime.now().toIso8601String(),
        'storeId': _storeId,
        'clientes': clientesBox.values.map(_clienteToMap).toList(),
        'produtos': produtosBox.values.map(_produtoToMap).toList(),
        'vendas': vendasBox.values.map(_vendaToMap).toList(),
        'fornecedores': fornecedoresBox.values.map(_fornecedorToMap).toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final fileName = 'backup_${_storeId}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

      await file_saver.saveFile(bytes, fileName);

      await NotificacaoService.enviarNotificacao(
        titulo: 'Backup Exportado',
        corpo: 'Arquivo baixado com sucesso!',
      );

      if (mounted) {
        _mostrarSnackBar('Backup exportado e baixado!', Icons.check_circle_outline, successColor);
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnackBar('Erro ao exportar: $e', Icons.error_outline, Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: const Text('Backup da Loja'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.download, size: 64, color: primaryColor),
              ),
              const SizedBox(height: 24),
              const Text(
                'Exportar dados da loja',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _storeIdLoading
                  • const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Loja: ${_storeId.isEmpty • '(nenhuma)' : _storeId}',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
              const SizedBox(height: 16),
              const Text(
                'O arquivo será baixado em JSON com clientes, produtos, vendas e fornecedores. '
                'Na versão web não é possível restaurar backup local — use o app Android para restauração completa.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: (_isLoading || _storeIdLoading || _storeId.isEmpty)
                    • null
                    : _exportarBackupWeb,
                icon: _isLoading • const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download),
                label: Text(_isLoading • 'Exportando...' : 'Exportar backup'),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
