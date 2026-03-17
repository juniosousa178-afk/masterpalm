import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../models/produto.dart';
import '../models/cliente.dart';
import '../models/venda.dart';
import '../models/fornecedor.dart';

class HiveMultiStore {
  static String? _lojaId;

  /// Chame sempre ao logar
  static Future<void> inicializar(String lojaId) async {
    if (lojaId.trim().isEmpty) {
      throw ArgumentError('lojaId não pode ser vazio em HiveMultiStore.inicializar');
    }
    _lojaId = lojaId;

    await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    await Hive.openBox<Cliente>(HiveBoxNames.clientes(lojaId));
    await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await Hive.openBox<Fornecedor>(HiveBoxNames.fornecedores(lojaId));
  }

  // GETTERS SEGUROS POR LOJA
  static Box<Produto> get produtos =>
      Hive.box<Produto>(HiveBoxNames.produtos(_lojaId ?? (throw StateError('HiveMultiStore não inicializado: chame inicializar(lojaId) após login'))));

  static Box<Cliente> get clientes =>
      Hive.box<Cliente>(HiveBoxNames.clientes(_lojaId ?? (throw StateError('HiveMultiStore não inicializado: chame inicializar(lojaId) após login'))));

  static Box<Venda> get vendas =>
      Hive.box<Venda>(HiveBoxNames.vendas(_lojaId ?? (throw StateError('HiveMultiStore não inicializado: chame inicializar(lojaId) após login'))));

  static Box<Fornecedor> get fornecedores =>
      Hive.box<Fornecedor>(HiveBoxNames.fornecedores(_lojaId ?? (throw StateError('HiveMultiStore não inicializado: chame inicializar(lojaId) após login'))));
}