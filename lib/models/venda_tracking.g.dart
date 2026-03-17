// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'venda_tracking.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VendaTrackingAdapter extends TypeAdapter<VendaTracking> {
  @override
  final int typeId = 27;

  @override
  VendaTracking read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VendaTracking(
      trackingId: fields[0] as String,
      lojaId: fields[1] as String,
      vendedorUid: fields[2] as String,
      vendedorEmail: fields[3] as String,
      vendedorNome: fields[4] as String,
      token: fields[5] as String,
      clienteTelefone: fields[6] as String?,
      clienteNome: fields[7] as String?,
      criadoEm: fields[8] as DateTime,
      expiraEm: fields[9] as DateTime,
      utilizado: fields[10] as bool,
      vendaId: fields[11] as String?,
      utilizadoEm: fields[12] as DateTime?,
      origem: fields[13] as String?,
      deviceId: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, VendaTracking obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.trackingId)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.vendedorUid)
      ..writeByte(3)
      ..write(obj.vendedorEmail)
      ..writeByte(4)
      ..write(obj.vendedorNome)
      ..writeByte(5)
      ..write(obj.token)
      ..writeByte(6)
      ..write(obj.clienteTelefone)
      ..writeByte(7)
      ..write(obj.clienteNome)
      ..writeByte(8)
      ..write(obj.criadoEm)
      ..writeByte(9)
      ..write(obj.expiraEm)
      ..writeByte(10)
      ..write(obj.utilizado)
      ..writeByte(11)
      ..write(obj.vendaId)
      ..writeByte(12)
      ..write(obj.utilizadoEm)
      ..writeByte(13)
      ..write(obj.origem)
      ..writeByte(14)
      ..write(obj.deviceId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VendaTrackingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ComissaoVendaAdapter extends TypeAdapter<ComissaoVenda> {
  @override
  final int typeId = 28;

  @override
  ComissaoVenda read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ComissaoVenda(
      comissaoId: fields[0] as String,
      lojaId: fields[1] as String,
      vendaId: fields[2] as String,
      vendedorUid: fields[3] as String,
      vendedorEmail: fields[4] as String,
      vendedorNome: fields[5] as String,
      trackingId: fields[6] as String?,
      subtotalProdutos: fields[7] as double,
      frete: fields[8] as double,
      desconto: fields[9] as double,
      totalVenda: fields[10] as double,
      baseComissao: fields[11] as double,
      comissaoPercentual: fields[12] as double,
      comissaoValor: fields[13] as double,
      status: fields[14] as String,
      origem: fields[15] as String,
      statusPagamentoVenda: fields[16] as String,
      dataVenda: fields[17] as DateTime,
      dataConfirmacao: fields[18] as DateTime?,
      dataPagamento: fields[19] as DateTime?,
      dataEstorno: fields[20] as DateTime?,
      motivoEstorno: fields[21] as String?,
      observacao: fields[22] as String?,
      idFirebase: fields[23] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ComissaoVenda obj) {
    writer
      ..writeByte(24)
      ..writeByte(0)
      ..write(obj.comissaoId)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.vendaId)
      ..writeByte(3)
      ..write(obj.vendedorUid)
      ..writeByte(4)
      ..write(obj.vendedorEmail)
      ..writeByte(5)
      ..write(obj.vendedorNome)
      ..writeByte(6)
      ..write(obj.trackingId)
      ..writeByte(7)
      ..write(obj.subtotalProdutos)
      ..writeByte(8)
      ..write(obj.frete)
      ..writeByte(9)
      ..write(obj.desconto)
      ..writeByte(10)
      ..write(obj.totalVenda)
      ..writeByte(11)
      ..write(obj.baseComissao)
      ..writeByte(12)
      ..write(obj.comissaoPercentual)
      ..writeByte(13)
      ..write(obj.comissaoValor)
      ..writeByte(14)
      ..write(obj.status)
      ..writeByte(15)
      ..write(obj.origem)
      ..writeByte(16)
      ..write(obj.statusPagamentoVenda)
      ..writeByte(17)
      ..write(obj.dataVenda)
      ..writeByte(18)
      ..write(obj.dataConfirmacao)
      ..writeByte(19)
      ..write(obj.dataPagamento)
      ..writeByte(20)
      ..write(obj.dataEstorno)
      ..writeByte(21)
      ..write(obj.motivoEstorno)
      ..writeByte(22)
      ..write(obj.observacao)
      ..writeByte(23)
      ..write(obj.idFirebase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComissaoVendaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
