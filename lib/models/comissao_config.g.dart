// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comissao_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ComissaoConfigAdapter extends TypeAdapter<ComissaoConfig> {
  @override
  final int typeId = 25;

  @override
  ComissaoConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ComissaoConfig(
      lojaId: fields[0] as String,
      comissaoGlobalPercent: fields[1] as double,
      apenasAposPagamentoConfirmado: fields[2] as bool,
      excluirFreteDaBase: fields[3] as bool,
      descontoReduzBase: fields[4] as bool,
      trackingExpiracaoDias: fields[5] as int,
      regraAtribuicao: fields[6] as String,
      bonusMetaBatida100: fields[7] as double,
      bonusMetaBatida150: fields[8] as double,
      comissaoMinimaValor: fields[9] as double,
      comissaoMaximaValor: fields[10] as double,
      estornoAutomaticoEmCancelamento: fields[11] as bool,
      criadoEm: fields[12] as DateTime?,
      atualizadoEm: fields[13] as DateTime?,
      idFirebase: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ComissaoConfig obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.lojaId)
      ..writeByte(1)
      ..write(obj.comissaoGlobalPercent)
      ..writeByte(2)
      ..write(obj.apenasAposPagamentoConfirmado)
      ..writeByte(3)
      ..write(obj.excluirFreteDaBase)
      ..writeByte(4)
      ..write(obj.descontoReduzBase)
      ..writeByte(5)
      ..write(obj.trackingExpiracaoDias)
      ..writeByte(6)
      ..write(obj.regraAtribuicao)
      ..writeByte(7)
      ..write(obj.bonusMetaBatida100)
      ..writeByte(8)
      ..write(obj.bonusMetaBatida150)
      ..writeByte(9)
      ..write(obj.comissaoMinimaValor)
      ..writeByte(10)
      ..write(obj.comissaoMaximaValor)
      ..writeByte(11)
      ..write(obj.estornoAutomaticoEmCancelamento)
      ..writeByte(12)
      ..write(obj.criadoEm)
      ..writeByte(13)
      ..write(obj.atualizadoEm)
      ..writeByte(14)
      ..write(obj.idFirebase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComissaoConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ComissaoVendedorAdapter extends TypeAdapter<ComissaoVendedor> {
  @override
  final int typeId = 26;

  @override
  ComissaoVendedor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ComissaoVendedor(
      lojaId: fields[0] as String,
      vendedorUid: fields[1] as String,
      vendedorEmail: fields[2] as String,
      vendedorNome: fields[3] as String,
      comissaoPercentual: fields[4] as double?,
      ativo: fields[5] as bool,
      criadoEm: fields[6] as DateTime?,
      atualizadoEm: fields[7] as DateTime?,
      idFirebase: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ComissaoVendedor obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.lojaId)
      ..writeByte(1)
      ..write(obj.vendedorUid)
      ..writeByte(2)
      ..write(obj.vendedorEmail)
      ..writeByte(3)
      ..write(obj.vendedorNome)
      ..writeByte(4)
      ..write(obj.comissaoPercentual)
      ..writeByte(5)
      ..write(obj.ativo)
      ..writeByte(6)
      ..write(obj.criadoEm)
      ..writeByte(7)
      ..write(obj.atualizadoEm)
      ..writeByte(8)
      ..write(obj.idFirebase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComissaoVendedorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
