import 'package:flutter_test/flutter_test.dart';

/// Bombeia frames até [finder] encontrar um widget (sem pumpAndSettle infinito).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 3),
  Duration step = const Duration(milliseconds: 200),
  String stage = 'finder',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'Timeout (${timeout.inSeconds}s) aguardando $stage '
    '(finder=${finder.description})',
  );
}

/// Bombeia até [condition] ser verdadeira.
Future<void> pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(minutes: 3),
  Duration step = const Duration(milliseconds: 200),
  String stage = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (condition()) return;
  }
  throw TestFailure(
    'Timeout (${timeout.inSeconds}s) aguardando $stage',
  );
}

/// Aguarda ausência de um marcador (ex.: loading).
Future<void> pumpUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(minutes: 2),
  Duration step = const Duration(milliseconds: 200),
  String stage = 'absent',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) return;
  }
  throw TestFailure(
    'Timeout (${timeout.inSeconds}s) aguardando ausência de $stage',
  );
}
