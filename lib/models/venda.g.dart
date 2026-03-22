// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'venda.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VendaAdapter extends TypeAdapter<Venda> {
  @override
  final int typeId = 1;

  @override
  Venda read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Venda(
      clienteNome: fields[3] as String,
      produtosDescricao: fields[1] as String,
      quantidade: fields[2] as int,
      preco: fields[0] as double,
      total: fields[4] as double,
      formasPagamento: fields[5] as String,
      data: fields[6] as DateTime,
      tamanho: fields[7] as String,
      desconto: fields[8] as double,
      frete: fields[9] as double,
      vendedor: fields[10] as String,
      observacao: fields[11] as String,
      itens: (fields[12] as List?)?.cast<VendaItem>(),
      pagamentoDinheiro: fields[13] == null ? 0.0 : fields[13] as double,
      pagamentoPix: fields[14] == null ? 0.0 : fields[14] as double,
      pagamentoCartao: fields[15] == null ? 0.0 : fields[15] as double,
      taxas: fields[16] == null ? 0.0 : fields[16] as double,
      custoProdutos: fields[17] == null ? 0.0 : fields[17] as double,
      descontoValor: fields[18] == null ? 0.0 : fields[18] as double,
      lojaId: fields[19] as String?,
      idFirebase: fields[20] as String?,
      clienteId: fields[21] as String?,
      statusVenda: fields[22] as String?,
      cancelada: fields[23] == null ? false : fields[23] as bool,
      estornada: fields[24] == null ? false : fields[24] as bool,
      origemVenda: fields[25] as String?,
      paymentId: fields[26] as String?,
      orderId: fields[27] as String?,
      prePedidoId: fields[28] as String?,
      pedidoId: fields[29] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Venda obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.preco)
      ..writeByte(1)
      ..write(obj.produtosDescricao)
      ..writeByte(2)
      ..write(obj.quantidade)
      ..writeByte(3)
      ..write(obj.clienteNome)
      ..writeByte(4)
      ..write(obj.total)
      ..writeByte(5)
      ..write(obj.formasPagamento)
      ..writeByte(6)
      ..write(obj.data)
      ..writeByte(7)
      ..write(obj.tamanho)
      ..writeByte(8)
      ..write(obj.desconto)
      ..writeByte(9)
      ..write(obj.frete)
      ..writeByte(10)
      ..write(obj.vendedor)
      ..writeByte(11)
      ..write(obj.observacao)
      ..writeByte(12)
      ..write(obj.itens)
      ..writeByte(13)
      ..write(obj.pagamentoDinheiro)
      ..writeByte(14)
      ..write(obj.pagamentoPix)
      ..writeByte(15)
      ..write(obj.pagamentoCartao)
      ..writeByte(16)
      ..write(obj.taxas)
      ..writeByte(17)
      ..write(obj.custoProdutos)
      ..writeByte(18)
      ..write(obj.descontoValor)
      ..writeByte(19)
      ..write(obj.lojaId)
      ..writeByte(20)
      ..write(obj.idFirebase)
      ..writeByte(21)
      ..write(obj.clienteId)
      ..writeByte(22)
      ..write(obj.statusVenda)
      ..writeByte(23)
      ..write(obj.cancelada)
      ..writeByte(24)
      ..write(obj.estornada)
      ..writeByte(25)
      ..write(obj.origemVenda)
      ..writeByte(26)
      ..write(obj.paymentId)
      ..writeByte(27)
      ..write(obj.orderId)
      ..writeByte(28)
      ..write(obj.prePedidoId)
      ..writeByte(29)
      ..write(obj.pedidoId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VendaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
