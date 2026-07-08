// WEBTX standalone — sem import Flutter (dart2js puro).

Map<String, dynamic> shallow(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return {};
}

Map<String, dynamic> deep(dynamic raw) {
  final top = shallow(raw);
  final out = <String, dynamic>{};
  for (final e in top.entries) {
    final v = e.value;
    out[e.key] = v is Map ? deep(v) : v;
  }
  return out;
}

void main() {
  _probe('WEBTX-2 cast legado top', () {
    final raw = Map<dynamic, dynamic>.from({
      '15': Map<dynamic, dynamic>.from({
        'sem-cor': Map<dynamic, dynamic>.from({'_sem_extra': 0}),
      }),
    });
    final _ = raw as Map<String, dynamic>?;
  });

  _probe('WEBTX-8 quantidade string as num (else branch anel)', () {
    final data = Map<String, dynamic>.from({
      'quantidade': '19',
      'variacoes': <String, dynamic>{},
    });
    final _ = (data['quantidade'] as num?)?.toInt();
  });

  _probe('WEBTX-10 mapaCor shallow cell nested JSObject', () {
    final variacoes = deep(Map<dynamic, dynamic>.from({
      '15': Map<dynamic, dynamic>.from({
        'sem-cor': Map<dynamic, dynamic>.from({'_sem_extra': 3}),
      }),
    }));
    final mapaCor = variacoes['15'];
    final mapa = shallow(mapaCor);
    final cell = mapa['sem-cor'];
    final m = Map<String, dynamic>.from(
      (cell as Map).map((k, v) => MapEntry(k.toString(), v)),
    );
    m['_sem_extra'] = (m['_sem_extra'] as num).toInt() - 1;
    mapa['sem-cor'] = m;
    Map<String, dynamic>.from(variacoes);
  });

  _probe('WEBTX-12 assertMarker param implicit cast', () {
    void assertMarker({required Map<String, dynamic> data}) {
      final _ = data['baixaAplicada'];
    }
    final dynamic markerData = Map<dynamic, dynamic>.from({
      'baixaAplicada': true,
      'operationId': 'op',
    });
    assertMarker(data: markerData);
  });

  _probe('WEBTX-14 encodeMapData cast<Object,dynamic>', () {
    final nested = Map<dynamic, dynamic>.from({'_sem_extra': 1});
    nested.cast<Object, dynamic>();
  });

  _probe('WEBTX-RED linha1390 quantidade string', () {
    final data = Map<dynamic, dynamic>.from({'quantidade': '19'});
    final quantidadeTotal = (data['quantidade'] as num?)?.toInt() ?? 0;
    if (quantidadeTotal < 1) throw Exception('insuficiente');
  });

  _probe('WEBTX-GREEN marker normalizado', () {
    void assertMarker({required Map<String, dynamic> data}) {
      final _ = data['baixaAplicada'];
    }
    final markerData = firestoreStringDynamicMapOrEmpty(
      Map<dynamic, dynamic>.from({'baixaAplicada': true}),
    );
    assertMarker(data: markerData);
  });

  _probe('WEBTX-GREEN quantidade string coercao', () {
    int firestoreIntFieldOrZero(dynamic raw) {
      if (raw == null) return 0;
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString().trim()) ?? 0;
    }
    final data = Map<dynamic, dynamic>.from({'quantidade': '19'});
    final quantidadeTotal = firestoreIntFieldOrZero(data['quantidade']);
    if (quantidadeTotal < 1) throw Exception('insuficiente');
  });
}

Map<String, dynamic> firestoreStringDynamicMapOrEmpty(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return {};
}

void _probe(String name, void Function() fn) {
  try {
    fn();
    print('$name: OK');
  } catch (e) {
    print('$name: ERR ${e.runtimeType} $e');
  }
}
