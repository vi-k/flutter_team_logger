import 'package:flutter_team_logger/src/details/log_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:team_logger/team_logger.dart';

final class _User with Loggable {
  final int id;
  final String name;
  final String password;

  _User(this.id, this.name, this.password);

  @override
  void collectLoggableData(LoggableData data) => data
    ..prop('id', id)
    ..prop('name', name)
    ..hidden('password', password)
    ..computed('label', '$name#$id');
}

void main() {
  final user = _User(42, 'Ann', 'hunter2');

  group('children', () {
    test('a Loggable hides hidden props in log mode', () {
      final children = LogNode.root(user).children(real: false);

      expect(children.map((n) => n.label), ['id', 'name', 'label']);
    });

    test('a Loggable shows hidden props in real mode', () {
      final children = LogNode.root(user).children(real: true);

      expect(
        children.map((n) => n.label),
        ['id', 'name', 'password', 'label'],
      );
      expect(
        children.firstWhere((n) => n.label == 'password').hidden,
        isTrue,
      );
    });

    test('computed props are recognized', () {
      final children = LogNode.root(user).children(real: true);

      expect(children.firstWhere((n) => n.label == 'label').computed, isTrue);
      expect(children.firstWhere((n) => n.label == 'id').computed, isFalse);
    });

    test('a LoggableMultiData splits into sections', () {
      final node = LogNode.root(
        LoggableMultiData({'request': 1, 'response': 2}),
      );

      expect(
        node.children(real: false).map((n) => n.label),
        ['request', 'response'],
      );
      expect(node.children(real: false).first.kind, LogNodeKind.section);
    });

    test('a Map splits into entries and a List into elements', () {
      expect(LogNode.root({'a': 1, 'b': 2}).children(real: false).length, 2);
      expect(
        LogNode.root({'a': 1}).children(real: false).first.kind,
        LogNodeKind.entry,
      );
      expect(
        LogNode.root([1, 2, 3]).children(real: false).map((n) => n.label),
        [0, 1, 2],
      );
      expect(
        LogNode.root({1, 2}).children(real: false).first.kind,
        LogNodeKind.element,
      );
    });

    test('a LoggableWrapper is transparent', () {
      final node = LogNode.root(Loggable.from(user));

      expect(
        node.children(real: false).map((n) => n.label),
        ['id', 'name', 'label'],
      );
    });

    test('a lazy Iterable stays a leaf', () {
      final node = LogNode.root([1, 2, 3].where((e) => e > 1));

      expect(node.expandable(real: false), isFalse);
      expect(node.children(real: false), isEmpty);
    });

    test('paths are built from positions, not values', () {
      final node = LogNode.root([
        {'a': 1},
        {'a': 1},
      ]);
      final children = node.children(real: false);

      expect(children[0].path, isNot(children[1].path));
    });
  });

  group('text', () {
    const theme = LogTheme.noColors;

    test('log mode renders the view, real mode the value', () {
      final data = Loggable.mapBuilder()
        ..prop('pan', '4111111111111234', view: '**** 1234');
      final node = LogNode.root(data).children(real: false).single;

      expect(node.valueText(theme: theme, real: false), '**** 1234');
      expect(node.valueText(theme: theme, real: true), '"4111111111111234"');
    });

    test('a computed prop shows its marker in real mode', () {
      final data = Loggable.mapBuilder()..computed('total', '1.00');
      final node = LogNode.root(data).children(real: true).single;

      expect(node.valueText(theme: theme, real: false), '1.00');
      expect(node.valueText(theme: theme, real: true), '<computed>');
    });

    test('units are appended to a bare view', () {
      final data = Loggable.mapBuilder()
        ..prop('weight', 1000, view: 1, units: 'kg');
      final node = LogNode.root(data).children(real: false).single;

      expect(node.valueText(theme: theme, real: false), '1kg');
    });

    test('a map key is rendered as the name', () {
      final node = LogNode.root({'a': 1}).children(real: false).single;

      expect(node.nameText(theme), '"a"');
    });

    test('an expanded object shows its class name', () {
      final node = LogNode.root(_User(42, 'Ann', 'x'));

      expect(node.headerText(theme: theme, real: false), '_User');
    });
  });
}
