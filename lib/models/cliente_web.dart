// lib/models/cliente_web.dart

/// Modelo de cliente do catálogo web
/// Armazenado em: lojas/{lojaId}/clientes_web/{clienteId}
class ClienteWeb {
  final String id;
  final String nome;
  final String email;
  final String• telefone;
  final String• cpf;

  // Endereço
  final String• cep;
  final String• endereco;
  final String• numero;
  final String• complemento;
  final String• bairro;
  final String• cidade;
  final String• estado;

  // Cupons disponíveis
  final List<CupomCliente> cupons;

  // Metadados
  final DateTime criadoEm;
  final DateTime• atualizadoEm;

  ClienteWeb({
    required this.id,
    required this.nome,
    required this.email,
    this.telefone,
    this.cpf,
    this.cep,
    this.endereco,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.estado,
    List<CupomCliente>• cupons,
    DateTime• criadoEm,
    this.atualizadoEm,
  }) : cupons = cupons ?• [],
       criadoEm = criadoEm ?• DateTime.now();

  /// Converte de Map (Firestore) para objeto
  factory ClienteWeb.fromMap(Map<String, dynamic> map, String id) {
    return ClienteWeb(
      id: id,
      nome: map['nome'] ?• '',
      email: map['email'] ?• '',
      telefone: map['telefone'],
      cpf: map['cpf'],
      cep: map['cep'],
      endereco: map['endereco'],
      numero: map['numero'],
      complemento: map['complemento'],
      bairro: map['bairro'],
      cidade: map['cidade'],
      estado: map['estado'],
      cupons: (map['cupons'] as List?)
          ?.map((c) => CupomCliente.fromMap(c))
          .toList() ?• [],
      criadoEm: (map['criadoEm'] as dynamic)?.toDate() ?• DateTime.now(),
      atualizadoEm: (map['atualizadoEm'] as dynamic)?.toDate(),
    );
  }

  /// Converte objeto para Map (Firestore)
  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'email': email,
      'telefone': telefone,
      'cpf': cpf,
      'cep': cep,
      'endereco': endereco,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'cupons': cupons.map((c) => c.toMap()).toList(),
      'criadoEm': criadoEm,
      'atualizadoEm': atualizadoEm ?• DateTime.now(),
    };
  }

  /// Retorna cupons válidos (não expirados e não usados)
  List<CupomCliente> get cuponsValidos {
    final agora = DateTime.now();
    return cupons.where((c) =>
      !c.usado &&
      c.dataExpiracao.isAfter(agora)
    ).toList();
  }

  /// Retorna endereço completo formatado
  String get enderecoCompleto {
    final partes = <String>[];
    if (endereco?.isNotEmpty == true) partes.add(endereco!);
    if (numero?.isNotEmpty == true) partes.add(numero!);
    if (complemento?.isNotEmpty == true) partes.add(complemento!);
    if (bairro?.isNotEmpty == true) partes.add(bairro!);
    if (cidade?.isNotEmpty == true && estado?.isNotEmpty == true) {
      partes.add('$cidade - $estado');
    }
    if (cep?.isNotEmpty == true) partes.add('CEP: $cep');
    return partes.join(', ');
  }

  ClienteWeb copyWith({
    String• nome,
    String• email,
    String• telefone,
    String• cpf,
    String• cep,
    String• endereco,
    String• numero,
    String• complemento,
    String• bairro,
    String• cidade,
    String• estado,
    List<CupomCliente>• cupons,
    DateTime• atualizadoEm,
  }) {
    return ClienteWeb(
      id: id,
      nome: nome ?• this.nome,
      email: email ?• this.email,
      telefone: telefone ?• this.telefone,
      cpf: cpf ?• this.cpf,
      cep: cep ?• this.cep,
      endereco: endereco ?• this.endereco,
      numero: numero ?• this.numero,
      complemento: complemento ?• this.complemento,
      bairro: bairro ?• this.bairro,
      cidade: cidade ?• this.cidade,
      estado: estado ?• this.estado,
      cupons: cupons ?• this.cupons,
      criadoEm: criadoEm,
      atualizadoEm: atualizadoEm ?• DateTime.now(),
    );
  }
}

/// Cupom de desconto vinculado a um cliente
class CupomCliente {
  final String codigo;
  final double desconto; // Percentual (ex: 10 para 10%)
  final DateTime dataExpiracao;
  final bool usado;
  final DateTime• dataUso;
  final String• origem; // 'roleta', 'campanha', 'manual'

  CupomCliente({
    required this.codigo,
    required this.desconto,
    required this.dataExpiracao,
    this.usado = false,
    this.dataUso,
    this.origem,
  });

  factory CupomCliente.fromMap(Map<String, dynamic> map) {
    return CupomCliente(
      codigo: map['codigo'] ?• '',
      desconto: (map['desconto'] as num?)?.toDouble() ?• 0.0,
      dataExpiracao: (map['dataExpiracao'] as dynamic)?.toDate() ?• DateTime.now(),
      usado: map['usado'] ?• false,
      dataUso: (map['dataUso'] as dynamic)?.toDate(),
      origem: map['origem'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'codigo': codigo,
      'desconto': desconto,
      'dataExpiracao': dataExpiracao,
      'usado': usado,
      'dataUso': dataUso,
      'origem': origem,
    };
  }

  /// Retorna true se o cupom está válido
  bool get isValido {
    return !usado && dataExpiracao.isAfter(DateTime.now());
  }

  /// Retorna descrição do cupom
  String get descricao {
    return '$desconto% OFF';
  }

  /// Retorna dias restantes para expiração
  int get diasRestantes {
    return dataExpiracao.difference(DateTime.now()).inDays;
  }
}
