import 'package:flutter/material.dart';
import 'package:flutter_team_logger/flutter_team_logger.dart';
import 'package:flutter_team_logger/src/details/log_node_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:team_logger/team_logger.dart';

final class _Address with Loggable {
  final String city;

  const _Address(this.city);

  @override
  void collectLoggableData(LoggableData data) => data..prop('city', city);
}

final class _Payment with Loggable {
  const _Payment();

  @override
  void collectLoggableData(LoggableData data) => data
    ..prop('pan', '4111111111111234', view: '**** 1234')
    ..prop('address', const _Address('Berlin'))
    ..hidden('accuracy', 12.5)
    ..computed('total', '123.45 USD');
}

void main() {
  testWidgets('the details screen renders, expands and switches modes',
      (tester) async {
    final storage = LogStorage(maxCount: 10);
    final log = Logger('app')
      ..level = LogLevels.all
      ..publisher = storage;
    log.d('payment', data: const _Payment(), tags: {'demo'});

    final theme = LogMainTheme.defaultActiveTheme;
    final entry = storage.first;

    await tester.pumpWidget(
      MaterialApp(home: LogDetails(entry, theme[entry.level])),
    );

    // The head and the first tree level are on screen.
    expect(find.byType(LogNodeTile), findsWidgets);

    // As logged: the view is drawn, the hidden property is absent.
    expect(_texts(tester).any((t) => t.contains('**** 1234')), isTrue);
    expect(_texts(tester).any((t) => t.contains('4111111111111234')), isFalse);
    expect(_texts(tester).any((t) => t.contains('accuracy')), isFalse);

    // Real data: the value behind the view, the hidden prop and the badges.
    await tester.tap(find.text('real data'));
    await tester.pumpAndSettle();

    expect(_texts(tester).any((t) => t.contains('4111111111111234')), isTrue);
    expect(_texts(tester).any((t) => t.contains('accuracy')), isTrue);
    expect(find.text('hidden'), findsOneWidget);
    expect(find.text('computed'), findsOneWidget);
    expect(_texts(tester).any((t) => t.contains('<computed>')), isTrue);

    // A nested object is collapsed: it shows the console summary on one row.
    final rowsBefore = tester.widgetList(find.byType(LogNodeTile)).length;
    expect(
      _texts(tester).any((t) => t.contains('_Address(city: "Berlin")')),
      isTrue,
    );

    // Tapping it turns the summary into rows of its own.
    final address = find.byWidgetPredicate(
      (w) => w is LogNodeTile && w.node.label == 'address',
    );
    expect(address, findsOneWidget);
    await tester.tap(address);
    await tester.pumpAndSettle();

    expect(tester.widgetList(find.byType(LogNodeTile)).length, rowsBefore + 1);
    expect(_texts(tester).any((t) => t.contains('city: "Berlin"')), isTrue);
  });

  testWidgets('a log without data opens without a tree', (tester) async {
    final storage = LogStorage(maxCount: 10);
    final log = Logger('app')
      ..level = LogLevels.all
      ..publisher = storage;
    log.d('bare message');

    final theme = LogMainTheme.defaultActiveTheme;
    final entry = storage.first;

    await tester.pumpWidget(
      MaterialApp(home: LogDetails(entry, theme[entry.level])),
    );

    expect(find.byType(LogNodeTile), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Iterable<String> _texts(WidgetTester tester) sync* {
  for (final widget in tester.allWidgets) {
    if (widget is RichText) yield widget.text.toPlainText();
    if (widget is Text) yield widget.data ?? '';
  }
}
