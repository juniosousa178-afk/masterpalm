// H1TX-R3 — marker payload transaction.set cast web (dart2js).

class _FakeFieldValueDelete {
  @override
  String toString() => 'FieldValue.delete()';
}

void simulateTransactionSetCast(Map payload) {
  final firestoreData = payload as Map<String, dynamic>;
  final _ = firestoreData.length;
}

void main() {
  _probe('RED-R3 inline marker JsLinkedHashMap cast', () {
    final payload = Map<dynamic, dynamic>.from({
      'protocolVersion': 1,
      'origem': 'pdv',
      'operationId': 'a4400412-test',
      'saleId': 'a4400412-test',
      'lojaId': 'nathy-pratas-e-folheados',
      'baixaAplicada': true,
      'estornoAplicado': false,
      'snapshotHash': 'abc123',
      'txItemsHash': 'def456',
    });
    simulateTransactionSetCast(payload);
  });

  _probe('RED Map<String,Object?> com FieldValue simulado', () {
    final payload = Map<String, Object?>.from({
      'protocolVersion': 1,
      'origem': 'pdv',
      'operationId': 'a4400412-test',
      'saleId': 'a4400412-test',
      'lojaId': 'nathy-pratas-e-folheados',
      'baixaAplicada': true,
      'estornoAplicado': false,
      'estornoAplicadoAt': _FakeFieldValueDelete(),
      'estornoOrigem': _FakeFieldValueDelete(),
      'snapshotHash': 'abc123',
      'txItemsHash': 'def456',
    });
    simulateTransactionSetCast(payload);
  });

  _probe('RED marker literal com FieldValue.delete', () {
    final payload = {
      'protocolVersion': 1,
      'origem': 'pdv',
      'operationId': 'a4400412-test',
      'saleId': 'a4400412-test',
      'lojaId': 'nathy-pratas-e-folheados',
      'baixaAplicada': true,
      'estornoAplicado': false,
      'estornoAplicadoAt': _FakeFieldValueDelete(),
      'estornoOrigem': _FakeFieldValueDelete(),
      'snapshotHash': 'abc123',
      'txItemsHash': 'def456',
    };
    simulateTransactionSetCast(payload);
  });

  _probe('GREEN marker Map<String,dynamic> sem delete', () {
    final payload = <String, dynamic>{
      'protocolVersion': 1,
      'origem': 'pdv',
      'operationId': 'a4400412-test',
      'saleId': 'a4400412-test',
      'lojaId': 'nathy-pratas-e-folheados',
      'baixaAplicada': true,
      'snapshotHash': 'abc123',
      'txItemsHash': 'def456',
    };
    simulateTransactionSetCast(payload);
  });

  _probe('GREEN marker normalizado shallow', () {
    Map<String, dynamic> shallow(dynamic raw) {
      if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return {};
    }
    final raw = Map<dynamic, dynamic>.from({
      'protocolVersion': 1,
      'origem': 'pdv',
      'operationId': 'op',
      'saleId': 'op',
      'lojaId': 'loja',
      'baixaAplicada': true,
      'snapshotHash': 'snap',
      'txItemsHash': 'tx',
    });
    simulateTransactionSetCast(shallow(raw));
  });
}

void _probe(String name, void Function() fn) {
  try {
    fn();
    print('$name: OK');
  } catch (e) {
    print('$name: ERR ${e.runtimeType} $e');
  }
}
