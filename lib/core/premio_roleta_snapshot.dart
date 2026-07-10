// Contrato canônico V1 do prêmio da roleta (snapshot imutável pós-giro).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_dynamic_map.dart';

/// Tipos canônicos do prêmio da roleta.
enum PremioRoletaTipoCanonico {
  percentual,
  valorFixo,
  freteGratis,
  brinde,
  nenhum,
}

/// Snapshot normalizado do prêmio — não recalcula a partir da config da roleta.
class PremioRoletaSnapshot {
  const PremioRoletaSnapshot({
    this.protocolVersion = 1,
    this.codigo,
    required this.tipo,
    required this.valor,
    required this.descricao,
    this.status = 'pendente',
    this.valido = false,
    this.dataGanho,
  });

  static const int protocolVersionAtual = 1;

  final int protocolVersion;
  final String? codigo;
  final PremioRoletaTipoCanonico tipo;
  final double valor;
  final String descricao;
  final String status;
  final bool valido;
  final dynamic dataGanho;

  bool get temPremio =>
      tipo != PremioRoletaTipoCanonico.nenhum &&
      (codigo?.isNotEmpty == true || descricao.isNotEmpty);

  /// Tipo legado persistido no Firestore / MP webhook.
  String get tipoFirestoreLegado {
    switch (tipo) {
      case PremioRoletaTipoCanonico.percentual:
      case PremioRoletaTipoCanonico.valorFixo:
        return 'desconto';
      case PremioRoletaTipoCanonico.freteGratis:
        return 'frete_gratis';
      case PremioRoletaTipoCanonico.brinde:
        return 'brinde';
      case PremioRoletaTipoCanonico.nenhum:
        return 'nenhum';
    }
  }

  /// Monta snapshot a partir de mapa Firestore (inclui legado e Map web).
  factory PremioRoletaSnapshot.fromFirestoreMap(dynamic raw) {
    final map = firestoreStringDynamicMapOrNull(raw);
    if (map == null || map.isEmpty) {
      return const PremioRoletaSnapshot(
        tipo: PremioRoletaTipoCanonico.nenhum,
        valor: 0,
        descricao: '',
      );
    }

    final codigo = (map['codigo'] ?? '').toString().trim();
    final descricaoRaw = (map['descricao'] ?? map['label'] ?? '').toString().trim();
    final status = (map['status'] ?? 'pendente').toString();
    final valido = map['valido'] == true;
    final dataGanho = map['dataGanho'];
    final protocolVersion =
        firestoreIntFieldOrZero(map['protocolVersion']).clamp(0, 99);
    final valorNum = _parseValor(map['valor'] ?? map['percentual'] ?? map['desconto']);

    final tipoCanonico = _resolverTipoCanonico(
      tipoRaw: map['tipo']?.toString(),
      codigo: codigo,
      descricao: descricaoRaw,
      valor: valorNum,
    );

    final descricao = descricaoRaw.isNotEmpty
        ? descricaoRaw
        : PremioRoletaFormatter.descricaoCurta(
            tipo: tipoCanonico,
            valor: valorNum,
          );

    return PremioRoletaSnapshot(
      protocolVersion: protocolVersion > 0 ? protocolVersion : protocolVersionAtual,
      codigo: codigo.isEmpty ? null : codigo,
      tipo: tipoCanonico,
      valor: valorNum,
      descricao: descricao,
      status: status,
      valido: valido,
      dataGanho: dataGanho,
    );
  }

  /// Monta snapshot no checkout (antes de persistir no pré-pedido).
  static PremioRoletaSnapshot? fromCheckoutInputs({
    String? descricao,
    String? codigo,
    double? valorLegado,
  }) {
    final cod = (codigo ?? '').trim();
    final desc = (descricao ?? '').trim();
    if (cod.isEmpty && desc.isEmpty) return null;

    if (cod == 'FRETE_GRATIS' || _pareceFreteGratis(desc)) {
      return PremioRoletaSnapshot(
        codigo: cod.isEmpty ? 'FRETE_GRATIS' : cod,
        tipo: PremioRoletaTipoCanonico.freteGratis,
        valor: 0,
        descricao: desc.isEmpty ? 'Frete grátis' : desc,
      );
    }

    if (cod == 'BRINDE' || _pareceBrinde(desc)) {
      return PremioRoletaSnapshot(
        codigo: cod.isEmpty ? 'BRINDE' : cod,
        tipo: PremioRoletaTipoCanonico.brinde,
        valor: 0,
        descricao: desc.isEmpty ? 'Brinde' : desc,
      );
    }

    final valorParsed = valorLegado ?? _extrairValorDaDescricao(desc);
    final tipoCanonico = _resolverTipoCanonico(
      tipoRaw: null,
      codigo: cod,
      descricao: desc,
      valor: valorParsed,
    );

    if (tipoCanonico == PremioRoletaTipoCanonico.nenhum) return null;

    return PremioRoletaSnapshot(
      codigo: cod.isEmpty ? null : cod,
      tipo: tipoCanonico,
      valor: valorParsed,
      descricao: desc.isEmpty
          ? PremioRoletaFormatter.descricaoCurta(
              tipo: tipoCanonico,
              valor: valorParsed,
            )
          : desc,
    );
  }

  Map<String, dynamic> toFirestoreMap({bool incluirTimestamp = true}) {
    if (!temPremio) return {};
    return {
      'protocolVersion': protocolVersionAtual,
      if (codigo != null && codigo!.isNotEmpty) 'codigo': codigo,
      'tipo': tipoFirestoreLegado,
      'valor': valor,
      'descricao': descricao,
      'status': status,
      'valido': valido,
      if (incluirTimestamp && dataGanho != null) 'dataGanho': dataGanho,
      if (incluirTimestamp && dataGanho == null)
        'dataGanho': FieldValue.serverTimestamp(),
    };
  }

  static double _parseValor(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString().replaceAll(',', '.')) ?? 0;
  }

  static bool _pareceFreteGratis(String desc) {
    final d = desc.toLowerCase();
    return d.contains('frete') && (d.contains('grátis') || d.contains('gratis') || d.contains('gr'));
  }

  static bool _pareceBrinde(String desc) {
    final d = desc.toLowerCase();
    return d.contains('brinde') ||
        d.contains('mimo') ||
        d.contains('chaveiro') ||
        d.contains('presente') ||
        d.contains('adesivo');
  }

  static double _extrairValorDaDescricao(String desc) {
    final d = desc.trim();
    if (d.isEmpty) return 0;

    final pct = RegExp(r'(\d+(?:[.,]\d+)?)\s*%').firstMatch(d);
    if (pct != null) {
      return double.tryParse(pct.group(1)!.replaceAll(',', '.')) ?? 0;
    }

    final moeda = RegExp(r'R\$\s*(\d+(?:[.,]\d+)?)').firstMatch(d);
    if (moeda != null) {
      return double.tryParse(moeda.group(1)!.replaceAll(',', '.')) ?? 0;
    }

    return 0;
  }

  static PremioRoletaTipoCanonico _resolverTipoCanonico({
    String? tipoRaw,
    required String codigo,
    required String descricao,
    required double valor,
  }) {
    final tipoNorm = (tipoRaw ?? '').toLowerCase().trim();
    switch (tipoNorm) {
      case 'percentual':
      case 'desconto_percentual':
        return PremioRoletaTipoCanonico.percentual;
      case 'valor_fixo':
      case 'valor':
      case 'fixo':
        return PremioRoletaTipoCanonico.valorFixo;
      case 'frete_gratis':
      case 'frete':
        return PremioRoletaTipoCanonico.freteGratis;
      case 'brinde':
        return PremioRoletaTipoCanonico.brinde;
      case 'nenhum':
        return PremioRoletaTipoCanonico.nenhum;
      case 'desconto':
        if (codigo == 'FRETE_GRATIS' || _pareceFreteGratis(descricao)) {
          return PremioRoletaTipoCanonico.freteGratis;
        }
        if (codigo == 'BRINDE' || _pareceBrinde(descricao)) {
          return PremioRoletaTipoCanonico.brinde;
        }
        if (_pareceValorFixo(descricao)) {
          return PremioRoletaTipoCanonico.valorFixo;
        }
        if (valor > 0 || descricao.contains('%')) {
          return PremioRoletaTipoCanonico.percentual;
        }
        return PremioRoletaTipoCanonico.nenhum;
      default:
        break;
    }

    if (codigo == 'FRETE_GRATIS' || _pareceFreteGratis(descricao)) {
      return PremioRoletaTipoCanonico.freteGratis;
    }
    if (codigo == 'BRINDE' || _pareceBrinde(descricao)) {
      return PremioRoletaTipoCanonico.brinde;
    }
    if (_pareceValorFixo(descricao)) {
      return PremioRoletaTipoCanonico.valorFixo;
    }
    if (valor > 0 || descricao.contains('%')) {
      return PremioRoletaTipoCanonico.percentual;
    }
    if (codigo.isNotEmpty) {
      // Código sem valor legível — não assumir desconto 0%.
      return PremioRoletaTipoCanonico.nenhum;
    }
    return PremioRoletaTipoCanonico.nenhum;
  }

  static bool _pareceValorFixo(String desc) {
    final d = desc.toLowerCase();
    return (d.contains('r\$') || d.contains('rs')) && !d.contains('%');
  }
}

/// Formatação única para mensagens e UI do vendedor.
class PremioRoletaFormatter {
  static String descricaoCurta({
    required PremioRoletaTipoCanonico tipo,
    required double valor,
  }) {
    switch (tipo) {
      case PremioRoletaTipoCanonico.percentual:
        if (valor <= 0) return 'Desconto';
        final v = valor == valor.roundToDouble()
            ? valor.toInt().toString()
            : valor.toStringAsFixed(1);
        return '$v% OFF';
      case PremioRoletaTipoCanonico.valorFixo:
        if (valor <= 0) return 'Desconto em valor';
        return 'R\$ ${_formatarMoeda(valor)} OFF';
      case PremioRoletaTipoCanonico.freteGratis:
        return 'Frete grátis';
      case PremioRoletaTipoCanonico.brinde:
        return 'Brinde';
      case PremioRoletaTipoCanonico.nenhum:
        return '';
    }
  }

  /// Linha principal na mensagem WhatsApp ao vendedor.
  static String linhaMensagemVendedor(PremioRoletaSnapshot snap) {
    switch (snap.tipo) {
      case PremioRoletaTipoCanonico.brinde:
        return 'Brinde: ${snap.descricao}';
      case PremioRoletaTipoCanonico.freteGratis:
        return 'Frete grátis';
      case PremioRoletaTipoCanonico.percentual:
        final v = snap.valor > 0
            ? (snap.valor == snap.valor.roundToDouble()
                ? snap.valor.toInt().toString()
                : snap.valor.toStringAsFixed(1))
            : _extrairPercentualFallback(snap.descricao);
        if (v.isEmpty) return 'Cupom de desconto';
        return 'Cupom de $v% OFF';
      case PremioRoletaTipoCanonico.valorFixo:
        if (snap.valor > 0) {
          return 'Cupom de R\$ ${_formatarMoeda(snap.valor)} OFF';
        }
        return 'Cupom de desconto em valor';
      case PremioRoletaTipoCanonico.nenhum:
        return '';
    }
  }

  static String tipoLabelVendedor(PremioRoletaSnapshot snap) {
    switch (snap.tipo) {
      case PremioRoletaTipoCanonico.percentual:
        if (snap.valor > 0) {
          final v = snap.valor == snap.valor.roundToDouble()
              ? snap.valor.toInt()
              : snap.valor;
          return '$v% de desconto';
        }
        final pct = _extrairPercentualFallback(snap.descricao);
        return pct.isEmpty ? 'Desconto percentual' : '$pct% de desconto';
      case PremioRoletaTipoCanonico.valorFixo:
        return snap.valor > 0
            ? 'R\$ ${_formatarMoeda(snap.valor)} de desconto'
            : 'Desconto em valor fixo';
      case PremioRoletaTipoCanonico.freteGratis:
        return 'Frete grátis';
      case PremioRoletaTipoCanonico.brinde:
        return snap.descricao.isEmpty ? 'Brinde' : snap.descricao;
      case PremioRoletaTipoCanonico.nenhum:
        return '';
    }
  }

  static String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'ativo':
        return 'Ativo';
      case 'usado':
        return 'Usado';
      case 'pendente':
      default:
        return 'Pendente';
    }
  }

  static String textoAplicacao(PremioRoletaSnapshot snap) {
    switch (snap.tipo) {
      case PremioRoletaTipoCanonico.brinde:
        return 'Será entregue junto com este pedido';
      case PremioRoletaTipoCanonico.freteGratis:
        if (snap.status == 'usado') return 'Frete grátis já utilizado';
        if (snap.valido) return 'Frete grátis ativo para próxima compra';
        return 'Válido para a próxima compra após pagamento confirmado';
      case PremioRoletaTipoCanonico.percentual:
      case PremioRoletaTipoCanonico.valorFixo:
        if (snap.status == 'usado') {
          return 'Cupom já utilizado';
        }
        if (snap.valido) {
          return 'Cupom ativo para próxima compra';
        }
        return 'Próxima compra após pagamento confirmado';
      case PremioRoletaTipoCanonico.nenhum:
        return '';
    }
  }

  static String notaMensagemVendedor(PremioRoletaSnapshot snap) {
    switch (snap.tipo) {
      case PremioRoletaTipoCanonico.brinde:
        return '   ⚠️ Será entregue junto com o pedido';
      case PremioRoletaTipoCanonico.freteGratis:
      case PremioRoletaTipoCanonico.percentual:
      case PremioRoletaTipoCanonico.valorFixo:
        return '   ⚠️ Válido para a próxima compra após pagamento confirmado';
      case PremioRoletaTipoCanonico.nenhum:
        return '';
    }
  }

  static String _formatarMoeda(double v) =>
      v.toStringAsFixed(2).replaceAll('.', ',');

  static String _extrairPercentualFallback(String desc) {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*%').firstMatch(desc);
    if (m == null) return '';
    return m.group(1)!.replaceAll(',', '.');
  }
}

/// Alias exportado conforme especificação da homologação.
PremioRoletaSnapshot? premioRoletaFromFirestoreMap(dynamic raw) {
  final snap = PremioRoletaSnapshot.fromFirestoreMap(raw);
  return snap.temPremio ? snap : null;
}
