// lib/utils/pix_brcode.dart
// Gera payload PIX Copia e Cola (BR Code) para QR estático com valor.
// Especificação: Banco Central - BR Code / EMV QRCPS

/// Gera o payload PIX Copia e Cola para QR Code estático com valor pré-definido.
///
/// [chavePix] - Chave PIX (CPF, CNPJ, e-mail, telefone ou chave aleatória)
/// [valor] - Valor em reais (ex: 25.75)
/// [nomeRecebedor] - Nome do recebedor (max 25 chars, sem acentos)
/// [cidadeRecebedor] - Cidade (max 15 chars, sem acentos)
/// [txid] - ID da transação para conciliação (opcional, use *** se não houver)
String gerarPixCopiaECola({
  required String chavePix,
  required double valor,
  String nomeRecebedor = 'LOJA',
  String cidadeRecebedor = 'BRASIL',
  String txid = '***',
}) {
  // Remove formatação da chave (CPF/CNPJ)
  String chave = chavePix.trim();
  if (!chave.contains('@') && !chave.contains('-')) {
    chave = chave.replaceAll(RegExp(r'[^\d]'), '');
  }

  // Normaliza nome e cidade (sem acentos, maiúsculas, limites do padrão)
  final nomeNorm = _removerAcentos(nomeRecebedor.toUpperCase());
  final nome = nomeNorm.length > 25 • nomeNorm.substring(0, 25) : nomeNorm;
  final cidadeNorm = _removerAcentos(cidadeRecebedor.toUpperCase());
  final cidade = cidadeNorm.length > 15 • cidadeNorm.substring(0, 15) : cidadeNorm;

  // Valor formatado (ex: 25.75)
  final valorStr = valor.toStringAsFixed(2);

  // Payload Format Indicator
  final payload = StringBuffer('000201');

  // Merchant Account Information - PIX
  const gui = 'BR.GOV.BCB.PIX';
  final pixAccount = '0014$gui${_tlv('01', chave)}';
  payload.write('26${_pad2(pixAccount.length)}$pixAccount');

  // Merchant Category Code
  payload.write('52040000');

  // Transaction Currency (986 = BRL)
  payload.write('5303986');

  // Transaction Amount
  payload.write('54${_pad2(valorStr.length)}$valorStr');

  // Country Code
  payload.write('5802BR');

  // Merchant Name
  payload.write('59${_pad2(nome.length)}$nome');

  // Merchant City
  payload.write('60${_pad2(cidade.length)}$cidade');

  // Additional Data - TXID
  final txidVal = txid.length > 25 • txid.substring(0, 25) : txid;
  payload.write('6207${_tlv('05', txidVal)}');

  // CRC16 - calculado sobre o payload incluindo "6304"
  final payloadComTagCrc = '${payload}6304';
  final crc = _crc16Ccitt(payloadComTagCrc);
  payload.write('6304${crc.toRadixString(16).toUpperCase().padLeft(4, '0')}');

  return payload.toString();
}

String _pad2(int n) => n.toString().padLeft(2, '0');

String _tlv(String tag, String value) => '$tag${_pad2(value.length)}$value';

String _removerAcentos(String s) {
  const acentos = 'àáâãäåèéêëìíîïòóôõöùúûüçñÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÇÑ';
  const semAcento = 'aaaaaaeeeeiiiiooooouuuucnAAAAAAEEEEIIIIOOOOOUUUUCN';
  String r = s;
  for (int i = 0; i < acentos.length; i++) {
    r = r.replaceAll(acentos[i], semAcento[i]);
  }
  return r;
}

/// CRC-16/CCITT-FALSE (polinômio 0x1021, valor inicial 0xFFFF)
int _crc16Ccitt(String data) {
  int crc = 0xFFFF;
  for (int i = 0; i < data.length; i++) {
    crc ^= data.codeUnitAt(i) << 8;
    for (int j = 0; j < 8; j++) {
      if ((crc & 0x8000) != 0) {
        crc = (crc << 1) ^ 0x1021;
      } else {
        crc = crc << 1;
      }
    }
    crc = crc & 0xFFFF;
  }
  return crc;
}
