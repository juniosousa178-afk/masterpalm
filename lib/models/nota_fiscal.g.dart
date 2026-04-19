// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nota_fiscal.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NotaFiscalAdapter extends TypeAdapter<NotaFiscal> {
  @override
  final int typeId = 10;

  @override
  NotaFiscal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NotaFiscal(
      numero: fields[0] as String,
      serie: fields[1] as String,
      chaveAcesso: fields[2] as String?,
      status: fields[3] as String,
      vendaId: fields[4] as String?,
      clienteNome: fields[5] as String,
      clienteCpfCnpj: fields[6] as String,
      clienteEndereco: fields[7] as String?,
      clienteCidade: fields[8] as String?,
      clienteEstado: fields[9] as String?,
      clienteCep: fields[10] as String?,
      dataEmissao: fields[11] as DateTime,
      valorTotal: fields[12] as double,
      valorProdutos: fields[13] as double,
      valorFrete: fields[14] as double,
      valorDesconto: fields[15] as double,
      itens: (fields[16] as List).cast<NotaFiscalItem>(),
      baseCalculoIcms: fields[17] as double,
      valorIcms: fields[18] as double,
      protocoloAutorizacao: fields[19] as String?,
      dataAutorizacao: fields[20] as DateTime?,
      xmlUrl: fields[21] as String?,
      pdfUrl: fields[22] as String?,
      lojaId: fields[23] as String,
      idFirebase: fields[24] as String?,
      observacoes: fields[25] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, NotaFiscal obj) {
    writer
      ..writeByte(26)
      ..writeByte(0)
      ..write(obj.numero)
      ..writeByte(1)
      ..write(obj.serie)
      ..writeByte(2)
      ..write(obj.chaveAcesso)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.vendaId)
      ..writeByte(5)
      ..write(obj.clienteNome)
      ..writeByte(6)
      ..write(obj.clienteCpfCnpj)
      ..writeByte(7)
      ..write(obj.clienteEndereco)
      ..writeByte(8)
      ..write(obj.clienteCidade)
      ..writeByte(9)
      ..write(obj.clienteEstado)
      ..writeByte(10)
      ..write(obj.clienteCep)
      ..writeByte(11)
      ..write(obj.dataEmissao)
      ..writeByte(12)
      ..write(obj.valorTotal)
      ..writeByte(13)
      ..write(obj.valorProdutos)
      ..writeByte(14)
      ..write(obj.valorFrete)
      ..writeByte(15)
      ..write(obj.valorDesconto)
      ..writeByte(16)
      ..write(obj.itens)
      ..writeByte(17)
      ..write(obj.baseCalculoIcms)
      ..writeByte(18)
      ..write(obj.valorIcms)
      ..writeByte(19)
      ..write(obj.protocoloAutorizacao)
      ..writeByte(20)
      ..write(obj.dataAutorizacao)
      ..writeByte(21)
      ..write(obj.xmlUrl)
      ..writeByte(22)
      ..write(obj.pdfUrl)
      ..writeByte(23)
      ..write(obj.lojaId)
      ..writeByte(24)
      ..write(obj.idFirebase)
      ..writeByte(25)
      ..write(obj.observacoes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotaFiscalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class NotaFiscalItemAdapter extends TypeAdapter<NotaFiscalItem> {
  @override
  final int typeId = 11;

  @override
  NotaFiscalItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NotaFiscalItem(
      produtoNome: fields[0] as String,
      codigoProduto: fields[1] as String?,
      quantidade: fields[2] as int,
      valorUnitario: fields[3] as double,
      valorTotal: fields[4] as double,
      unidade: fields[5] as String,
      ncm: fields[6] as String?,
      cfop: fields[7] as String?,
      aliquotaIcms: fields[8] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, NotaFiscalItem obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.produtoNome)
      ..writeByte(1)
      ..write(obj.codigoProduto)
      ..writeByte(2)
      ..write(obj.quantidade)
      ..writeByte(3)
      ..write(obj.valorUnitario)
      ..writeByte(4)
      ..write(obj.valorTotal)
      ..writeByte(5)
      ..write(obj.unidade)
      ..writeByte(6)
      ..write(obj.ncm)
      ..writeByte(7)
      ..write(obj.cfop)
      ..writeByte(8)
      ..write(obj.aliquotaIcms);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotaFiscalItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
