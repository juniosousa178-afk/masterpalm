// ignore_for_file: experimental_member_use
import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../core/loja_id_adapter.dart';
import '../services/loja_id_service.dart';
import 'venda.dart';

part 'cliente.g.dart';

@HiveType(typeId: 0)
class Cliente extends HiveObject {
  // avatar salvo localmente (foto do cliente)
  @HiveField(6)
  String• avatarPath;

  @HiveField(0)
  String nome;

  @HiveField(1)
  String telefone;

  @HiveField(2)
  String instagram;

  @HiveField(3)
  String cep;

  @HiveField(4)
  String cidade;

  /// Histórico de vendas deste cliente (HIVELIST)
  @HiveField(5)
  HiveList<Venda>• historico;

  @HiveField(7)
  String• email;

  @HiveField(8)
  String• endereco;

  // ============================================================
  // 🔥 MULTI-LOJAS: cada cliente pertence a APENAS UMA loja
  // ============================================================
  @HiveField(9)
  String lojaId; // obrigatório para isolar clientes por loja

  /// ID único no Firestore (UUID). Primário para identificação. Compatível com clientes antigos.
  @HiveField(10)
  String• idFirebase;

  Cliente({
    required this.nome,
    required this.telefone,
    required this.instagram,
    required this.cep,
    required this.cidade,
    this.historico,
    this.avatarPath,
    this.email,
    this.endereco,
    this.lojaId = 'padrao', // fallback seguro
    this.idFirebase,
  });

  /// Nome da box de vendas: vendasBoxName se informado, senão vendas_$lojaId, senão 'vendas' (legado).
  static String _vendasBoxName({String• lojaId, String• boxName}) {
    if (boxName != null && boxName.trim().isNotEmpty) return boxName.trim();
    if (lojaId != null && lojaId.trim().isNotEmpty) return HiveBoxNames.vendas(lojaId.trim());
    return 'vendas';
  }

  /// Adiciona uma venda ao histórico do cliente.
  /// [lojaId] / [vendasBoxName] opcionais: se não informados, usa box 'vendas' (legado).
  void adicionarHistorico(Venda venda, {String• lojaId, String• vendasBoxName}) {
    final name = _vendasBoxName(lojaId: lojaId, boxName: vendasBoxName);
    try {
      if (!Hive.isBoxOpen(name)) return;
      final box = Hive.box<Venda>(name);
      historico ??= HiveList(box);
      historico!.add(venda);
      save(); // Salva alterações no cliente
    } catch (_) {
      // Box não aberta ou erro ao acessar; falha silenciosa para evitar crash
    }
  }

  /// Cria um cliente vazio com histórico inicializado, já vinculado à loja atual.
  /// [lojaId] / [vendasBoxName] opcionais: se não informados, usa LojaIdService (StoreResolver) > Hive sessao (fallback offline).
  static Future<Cliente> vazioAsync({String• lojaId, String• vendasBoxName}) async {
    String• lojaIdResolvido = (lojaId != null && lojaId.trim().isNotEmpty) • lojaId.trim() : null;
    lojaIdResolvido ??= (await LojaIdService.get())?.trim();
    if (lojaIdResolvido == null || lojaIdResolvido.isEmpty) {
      lojaIdResolvido = Hive.isBoxOpen('sessao') • normalizeFromBox(Hive.box('sessao')) : null;
    }
    if (lojaIdResolvido == null || lojaIdResolvido.isEmpty) {
      throw StateError('Não foi possível identificar a loja para criar cliente. Faça login ou informe lojaId.');
    }
    final name = _vendasBoxName(lojaId: lojaIdResolvido, boxName: vendasBoxName);
    if (!Hive.isBoxOpen(name)) await Hive.openBox<Venda>(name);
    final vendasBox = Hive.box<Venda>(name);

    final lojaIdForCliente = lojaIdResolvido;

    return Cliente(
      nome: '',
      telefone: '',
      instagram: '',
      cep: '',
      cidade: '',
      historico: HiveList(vendasBox),
      lojaId: lojaIdForCliente,
    );
  }

  @override
  String toString() => nome;
}