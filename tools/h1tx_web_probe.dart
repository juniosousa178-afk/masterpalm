// Probe dart2js: variantes de mapa Firestore web.
void main() {
  _probe('A Map<String,Object?> nested', () {
    final top = <String, Object?>{'7mm': <String, Object?>{'cristal': 1}};
    final shallow = Map<String, dynamic>.from(top);
    Map<String, dynamic>.from(shallow['7mm'] as Map);
  });

  _probe('B Map<dynamic,dynamic> nested', () {
    final nested = Map<dynamic, dynamic>.from({'cristal': 1});
    final top = Map<String, dynamic>.from({'7mm': nested});
    Map<String, dynamic>.from(top['7mm'] as Map);
  });

  _probe('C legacy cast variacoes', () {
    final raw = Map<dynamic, dynamic>.from({
      '7mm': Map<dynamic, dynamic>.from({'cristal': 1}),
    });
    final _ = raw as Map<String, dynamic>?;
  });

  _probe('D shallow normalize then from', () {
    final raw = Map<dynamic, dynamic>.from({
      '7mm': Map<dynamic, dynamic>.from({'cristal': 1}),
    });
    Map<String, dynamic> shallow(dynamic r) {
      if (r is Map<String, dynamic>) return Map<String, dynamic>.from(r);
      if (r is Map) return Map<String, dynamic>.from(r);
      return {};
    }
    final v = shallow(raw);
    Map<String, dynamic>.from(v['7mm'] as Map);
  });
}

void _probe(String name, void Function() fn) {
  try {
    fn();
    // ignore: avoid_print
    print('$name: OK');
  } catch (e) {
    // ignore: avoid_print
    print('$name: ERR ${e.runtimeType} $e');
  }
}
