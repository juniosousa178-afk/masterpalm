// lib/core/compra_item_pipeline_constants.dart
// Estados persistidos — não renomear sem migração.

abstract class CompraItemPipelineEstado {
  static const String aguardandoPrecificacao = 'aguardando_precificacao';
  static const String precificadoPendenteEstoque = 'precificado_pendente_estoque';
  static const String concluidoNoEstoque = 'concluido_no_estoque';
  static const String cancelado = 'cancelado';

  static const List<String> todos = [
    aguardandoPrecificacao,
    precificadoPendenteEstoque,
    concluidoNoEstoque,
    cancelado,
  ];

  static String ouPadrao(String s) =>
      todos.contains(s) ? s : aguardandoPrecificacao;

  static String legivel(String s) {
    switch (s) {
      case aguardandoPrecificacao:
        return 'Aguardando precificação';
      case precificadoPendenteEstoque:
        return 'Precificado — pendente estoque';
      case concluidoNoEstoque:
        return 'Concluído no estoque';
      case cancelado:
        return 'Cancelado';
      default:
        return s;
    }
  }
}

/// Origem na lista da precificação universal (ramo legado vs compra).
abstract class PrecificacaoItemOrigem {
  static const String manual = 'manual';
  static const String compraPipeline = 'compra_pipeline';
}
