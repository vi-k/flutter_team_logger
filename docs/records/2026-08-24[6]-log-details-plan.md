# План реализации: окно деталей лога (LogDetails)

> **Состояние на 2026-08-24:** выполнен целиком, все восемь задач сделаны и
> смержены. Код в трёх местах разошёлся с планом (имя константы enum,
> раскрытие первого уровня, `prefer_foreach`) — разбор в отчёте, сам план
> оставлен как был.
> **Что это:** пошаговый план реализации экрана `LogDetails` по спеке.
> **Связанные записи:** `2026-08-24[5]-log-details-design.md` — спека,
> `2026-08-24[7]-log-details-report.md` — отчёт.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** по тапу на лог открывается экран с полным описанием лога, включая
дерево `data` с переключением `view`/`hidden` на реальные значения.

**Architecture:** модель узлов (`LogNode`) рекурсивно разбирает `log.data`
средствами публичного API `team_logger`; раскрытые узлы уплощаются в один
`ListView.builder`; текст значений рисуется теми же вызовами, что и консоль,
и переводится во Flutter через существующий `ansi_utils.dart`.

**Tech Stack:** Flutter, `team_logger` 0.7.0, `ansi_escape_codes`,
`flutter_test` (только для модели узлов).

**Spec:** `docs/records/2026-08-24[5]-log-details-design.md`

## Global Constraints

- Весь код и комментарии в `lib/` и `example/` — **по-английски**, включая
  dartdoc (`AGENTS.md`, раздел «Язык»). Сообщения коммитов — по-английски.
- `dart analyze` в корне и в `example/` должен давать `No issues found!` —
  обязательное условие перед каждым коммитом (`docs/conventions.md`).
- **Нельзя обращаться к `@internal` членам `team_logger`**: все геттеры
  `LoggableConfig.resolved*` и `withoutUnits()` помечены `@internal` и дают
  `invalid_use_of_internal_member`. Публичная замена — `toEffectiveConfig()`.
- **Нельзя использовать `LoggableData.name`** — геттер всегда возвращает
  строку `'type'`. Имя класса берётся как
  `data.type.typeName ?? data.type.value.toString()`.
- Активные линты, о которые легко споткнуться: `comment_references` (любая
  ссылка `[Foo]` в dartdoc обязана резолвиться в области видимости файла),
  `prefer_const_constructors`, `prefer_const_declarations`,
  `prefer_final_locals`, `omit_local_variable_types`,
  `prefer_relative_imports`. Ширина кода в проекте — 80 колонок.
- Версия пакета в конце работы — **0.7.1**. Публикация в план не входит и
  требует отдельного разрешения владельца (`AGENTS.md`).
- Мержить прямо в `main`, без PR.

## Структура файлов

| Файл | Ответственность |
|---|---|
| `lib/src/uikit/border_container.dart` | бордюрная плашка (уровень, время, путь, номер), общая для `LogItem` и `LogDetails` |
| `lib/src/details/log_node.dart` | модель узла, разбор целей, зонд `computed`, рендер имени и значения в ANSI-текст |
| `lib/src/details/log_node_tile.dart` | виджет одной строки дерева |
| `lib/src/details/log_details.dart` | экран: AppBar с тумблером, шапка лога, плоский список дерева, ошибка и стек |
| `test/log_node_test.dart` | тесты модели узлов |

---

### Task 1: Вынести BorderContainer в uikit

Плашка нужна обоим экранам, а сейчас она приватна в `log_item.dart`.

**Files:**
- Create: `lib/src/uikit/border_container.dart`
- Modify: `lib/src/log_item.dart:1-10` (импорт и константа),
  `lib/src/log_item.dart:352-412` (удаление класса), все вхождения
  `_BorderContainer` (строки 214, 222, 231, 240, 262, 320, 333)

**Interfaces:**
- Produces: `class BorderContainer extends StatelessWidget` с теми же
  параметрами, что были у `_BorderContainer`, и `const borderColorAlpha =
  0.4`.

- [ ] **Step 1: Создать файл с перенесённым классом**

Скопировать тело `_BorderContainer` из `log_item.dart:352-412` без
изменений, кроме: имя без подчёркивания, `super.key` без
`// ignore: unused_element_parameter`, и **удалить строку
`Colors.red.computeLuminance();`** (`log_item.dart:381`) — вызов без
эффекта. Константа `_borderColorAlpha` переезжает сюда как публичная.

```dart
import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:flutter/material.dart';

import '../ansi_utils.dart';

/// Alpha applied to a foreground color to derive a border color.
const borderColorAlpha = 0.4;

/// A small bordered label: level name, time, path, log number, tags.
class BorderContainer extends StatelessWidget {
  static const EdgeInsetsGeometry _padding =
      EdgeInsets.only(left: 3, right: 3, top: 1, bottom: 1);
  static const double _borderRadius = 4;
  static const double _fontSize = 11;

  final String text;
  final ansi.Style style;
  final Color? borderColor;
  final bool topLeftRounded;
  final bool topRightRounded;
  final bool borderLeftRounded;
  final bool borderRightRounded;

  const BorderContainer({
    super.key,
    required ansi.Style style,
    required ansi.Style defaultStyle,
    this.borderColor,
    this.topLeftRounded = false,
    this.topRightRounded = false,
    this.borderLeftRounded = false,
    this.borderRightRounded = false,
    required this.text,
  }) : style = style is ansi.NoStyle ? defaultStyle : style;

  @override
  Widget build(BuildContext context) {
    final textStyle = ansiStyle2TextStyle(style, fontSize: _fontSize);
    final borderColor = this.borderColor ??
        ansiColor2Color(style.foregroundColor)?.withValues(
          alpha: borderColorAlpha,
        ) ??
        Colors.red;

    return Container(
      decoration: BoxDecoration(
        color: textStyle.backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.only(
          topLeft: topLeftRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
          topRight: topRightRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
          bottomLeft: borderLeftRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
          bottomRight: borderRightRounded //
              ? const Radius.circular(_borderRadius)
              : Radius.zero,
        ),
      ),
      padding: _padding,
      child: Text(text, style: textStyle),
    );
  }
}
```

- [ ] **Step 2: Переключить log_item.dart на новый класс**

Удалить из `log_item.dart` класс `_BorderContainer` целиком и объявление
`const _borderColorAlpha = 0.4;` (строка 7). Добавить импорт
`import 'uikit/border_container.dart';`. Заменить все `_BorderContainer` на
`BorderContainer` и оба вхождения `_borderColorAlpha` (строки 61, 75) на
`borderColorAlpha`.

- [ ] **Step 3: Проверить**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 4: Коммит**

```bash
git add lib/src/uikit/border_container.dart lib/src/log_item.dart
git commit -m "refactor: extract BorderContainer into uikit"
```

---

### Task 2: Модель узлов — структура и разбор

Ядро работы. Логика чистая, без Flutter, поэтому покрывается тестами.

**Files:**
- Create: `lib/src/details/log_node.dart`
- Test: `test/log_node_test.dart`

**Interfaces:**
- Produces:
  - `enum LogNodeKind { root, prop, section, index, entry }`
  - `final Object? computedMarker`
  - `final class LogNode` с полями `kind`, `label`, `showName`, `value`,
    `view`, `hidden`, `config`, `depth`, `path`; геттером `bool get
    computed`; методами `Object? target({required bool real})`,
    `bool expandable({required bool real})`,
    `List<LogNode> children({required bool real})`; фабрикой
    `LogNode.root(Object? data)`.

- [ ] **Step 1: Написать падающие тесты на разбор**

```dart
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

      expect(children.map((n) => n.label), ['id', 'name', 'password',
          'label']);
      expect(children.firstWhere((n) => n.label == 'password').hidden,
          isTrue);
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

      expect(node.children(real: false).map((n) => n.label),
          ['request', 'response']);
      expect(node.children(real: false).first.kind, LogNodeKind.section);
    });

    test('a Map splits into entries and a List into elements', () {
      expect(LogNode.root({'a': 1, 'b': 2}).children(real: false).length, 2);
      expect(LogNode.root({'a': 1}).children(real: false).first.kind,
          LogNodeKind.entry);
      expect(LogNode.root([1, 2, 3]).children(real: false).map((n) => n.label),
          [0, 1, 2]);
      expect(LogNode.root({1, 2}).children(real: false).first.kind,
          LogNodeKind.index);
    });

    test('a LoggableWrapper is transparent', () {
      final node = LogNode.root(Loggable.from(user));

      expect(node.children(real: false).map((n) => n.label),
          ['id', 'name', 'label']);
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
}
```

- [ ] **Step 2: Запустить тесты и убедиться, что падают**

Run: `flutter test test/log_node_test.dart`
Expected: FAIL — `Target of URI doesn't exist:
'package:flutter_team_logger/src/details/log_node.dart'`

- [ ] **Step 3: Реализовать модель**

Ключевые решения кода: `label` — `Object?`, а не `String`, потому что для
записи `Map` меткой служит сам объект ключа (его рендер требует темы и
происходит позже); `expandable` определяется по типу цели, а не построением
детей, иначе свёрнутая коллекция на 10 000 элементов материализовала бы их
ради одной стрелки.

```dart
import 'package:team_logger/team_logger.dart';

/// What a node's label means.
enum LogNodeKind {
  /// The `data` of the log itself.
  root,

  /// A property of a `Loggable` or a `LoggableData`.
  prop,

  /// A section of a `LoggableMultiData`.
  section,

  /// An element of a `List` or a `Set`.
  index,

  /// An entry of a `Map`.
  entry,
}

/// The value every computed property carries.
///
/// `team_logger` exposes no flag for a computed property, but all of them
/// share a single const instance. This probe captures that instance through
/// the public API, so `identical` recognizes any computed property exactly.
///
/// Should `team_logger` ever stop sharing one instance, computed properties
/// merely lose their badge — nothing breaks.
final Object? computedMarker =
    (Loggable.mapBuilder()..computed('probe', 0)).props.first.value;

/// One row of the log data tree.
final class LogNode {
  final LogNodeKind kind;

  /// Property name, section key, element index or the key object of a map
  /// entry. Rendered later, when a theme is at hand.
  final Object? label;

  final bool showName;

  /// The real value behind the node.
  final Object? value;

  /// What the log prints instead of [value], or `Prop.noView`.
  final Object? view;

  final bool hidden;
  final LoggableConfig config;
  final int depth;

  /// Identity of the node, used to remember what the user expanded.
  ///
  /// Built from positions rather than values: equal values sitting on
  /// different branches must not expand together.
  final String path;

  const LogNode({
    required this.kind,
    required this.label,
    required this.value,
    required this.path,
    this.showName = true,
    this.view = Prop.noView,
    this.hidden = false,
    this.config = const LoggableConfig(),
    this.depth = 0,
  });

  /// The root node of a log's data.
  factory LogNode.root(Object? data) => LogNode(
        kind: LogNodeKind.root,
        label: null,
        value: data,
        path: '',
      );

  bool get computed => identical(value, computedMarker);

  /// The value the given mode renders and expands.
  ///
  /// In log mode that is the view when one is set, because that is what the
  /// log actually prints; in real mode it is always the value itself.
  Object? target({required bool real}) =>
      real || view is LoggableNoView ? value : view;

  bool expandable({required bool real}) => _expandable(target(real: real));

  /// Children of the node, empty when it cannot be expanded.
  List<LogNode> children({required bool real}) =>
      _children(target(real: real), config, depth + 1, path, real: real) ??
      const [];

  static bool _expandable(Object? target) => switch (target) {
        final LoggableWrapper wrapper => _expandable(wrapper.data),
        Loggable() ||
        LoggableData() ||
        LoggableMultiData() ||
        Map<Object?, Object?>() ||
        List<Object?>() ||
        Set<Object?>() =>
          true,
        _ => false,
      };

  /// Only `List` and `Set` are walked, not every `Iterable`: a lazy one may
  /// be endless, and enumerating it for the tree would materialize it.
  static List<LogNode>? _children(
    Object? target,
    LoggableConfig config,
    int depth,
    String parentPath, {
    required bool real,
  }) =>
      switch (target) {
        final LoggableWrapper wrapper => _children(
            wrapper.data,
            wrapper.config.merge(config),
            depth,
            parentPath,
            real: real,
          ),
        final Loggable loggable => _props(
            loggable.logClassInfo(),
            config,
            depth,
            parentPath,
            real: real,
          ),
        final LoggableData data =>
          _props(data, config, depth, parentPath, real: real),
        final LoggableMultiData data => [
            for (final entry in data.data.entries)
              LogNode(
                kind: LogNodeKind.section,
                label: entry.key,
                value: entry.value,
                config: data.config.merge(config),
                depth: depth,
                path: '$parentPath/${entry.key}',
              ),
          ],
        final Map<Object?, Object?> map => [
            for (final (index, entry) in map.entries.indexed)
              LogNode(
                kind: LogNodeKind.entry,
                label: entry.key,
                value: entry.value,
                config: config,
                depth: depth,
                path: '$parentPath/[$index]',
              ),
          ],
        final List<Object?> list => _elements(list, config, depth, parentPath),
        final Set<Object?> set => _elements(set, config, depth, parentPath),
        _ => null,
      };

  static List<LogNode> _elements(
    Iterable<Object?> items,
    LoggableConfig config,
    int depth,
    String parentPath,
  ) =>
      [
        for (final (index, item) in items.indexed)
          LogNode(
            kind: LogNodeKind.index,
            label: index,
            value: item,
            config: config,
            depth: depth,
            path: '$parentPath/[$index]',
          ),
      ];

  static List<LogNode> _props(
    LoggableData data,
    LoggableConfig config,
    int depth,
    String parentPath, {
    required bool real,
  }) =>
      [
        for (final prop in data.props)
          if (real || !prop.hidden)
            LogNode(
              kind: LogNodeKind.prop,
              label: prop.name,
              showName: prop.showName,
              value: prop.value,
              view: prop.view,
              hidden: prop.hidden,
              config: prop.config.merge(config),
              depth: depth,
              path: '$parentPath/${prop.name}',
            ),
      ];
}
```

- [ ] **Step 4: Запустить тесты**

Run: `flutter test test/log_node_test.dart`
Expected: PASS, все 8 тестов.

- [ ] **Step 5: Проверить анализатор**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: Коммит**

```bash
git add lib/src/details/log_node.dart test/log_node_test.dart
git commit -m "feat: add the log data tree node model"
```

---

### Task 3: Модель узлов — рендер текста

**Files:**
- Modify: `lib/src/details/log_node.dart`
- Test: `test/log_node_test.dart`

**Interfaces:**
- Consumes: `LogNode` из Task 2.
- Produces: методы `String nameText(LogTheme theme)`,
  `String valueText({required LogTheme theme, required bool real})`,
  `String headerText({required LogTheme theme, required bool real})`.

- [ ] **Step 1: Написать падающие тесты на рендер**

Тема `LogTheme.noColors` даёт текст без ANSI-кодов, поэтому сравнение
строк читаемо.

```dart
  group('text', () {
    const theme = LogTheme.noColors;

    test('log mode renders the view, real mode the value', () {
      final data = Loggable.mapBuilder()
        ..prop('pan', '4111111111111234', view: '**** 1234');
      final node = LogNode.root(data).children(real: false).single;

      expect(node.valueText(theme: theme, real: false), '**** 1234');
      expect(node.valueText(theme: theme, real: true),
          '"4111111111111234"');
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
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `flutter test test/log_node_test.dart`
Expected: FAIL — `The method 'valueText' isn't defined`.

- [ ] **Step 3: Реализовать рендер**

Ветвление `valueText` — точная копия `Prop.toLogString`
(`loggable_data.dart:591-624`) минус приватные сегменты санитайзера.
`config.toEffectiveConfig()` вместо `@internal`-геттеров `resolved*`.

```dart
  /// The node's label as the log would draw it.
  String nameText(LogTheme theme) {
    final effective = config.toEffectiveConfig();

    return switch (kind) {
      LogNodeKind.root => '',
      LogNodeKind.prop => theme.data.keyStyle(
          theme.formatValue(
            '$label',
            escapeAnsiCodes: effective.escapeAnsiCodes,
          ),
        ),
      LogNodeKind.section => theme.data.sectionStyle('$label'),
      LogNodeKind.index => theme.data.dim('[$label]'),
      LogNodeKind.entry =>
        Loggable.objectToString(label, theme: theme, config: config),
    };
  }

  /// The node's value as the given mode draws it.
  String valueText({required LogTheme theme, required bool real}) =>
      switch (real ? Prop.noView : view) {
        LoggableNoView() => Loggable.objectToString(
            value,
            theme: theme,
            depth: depth,
            config: config,
          ),
        final LoggableView view => theme.formatValue(
            view.toLogString(value, theme: theme, depth: depth),
            escapeAnsiCodes: false,
          ),
        final view => theme.formatValue(
            '$view'
            '${Loggable.unitsToString(config.toEffectiveConfig().units, theme)}',
            escapeAnsiCodes: false,
          ),
      };

  /// What an expanded node shows in place of its value.
  ///
  /// `LoggableData.name` is unusable here: its getter always returns the
  /// string `'type'`, so the class name is taken the way `team_logger` takes
  /// it internally.
  String headerText({required LogTheme theme, required bool real}) =>
      _header(target(real: real), theme);

  static String _header(Object? target, LogTheme theme) => switch (target) {
        final LoggableWrapper wrapper => _header(wrapper.data, theme),
        final Loggable loggable => _typeName(loggable.logClassInfo(), theme),
        final LoggableData data => _typeName(data, theme),
        final LoggableMultiData _ => '',
        final Map<Object?, Object?> map => theme.data.punctuation(
            '{${map.length}}',
          ),
        final List<Object?> list => theme.data.punctuation('[${list.length}]'),
        final Set<Object?> set => theme.data.punctuation('{${set.length}}'),
        _ => '',
      };

  static String _typeName(LoggableData data, LogTheme theme) =>
      data.type.showName
          ? theme.data.nameStyle(
              data.type.typeName ?? data.type.value.toString(),
            )
          : '';
```

- [ ] **Step 4: Запустить тесты**

Run: `flutter test test/log_node_test.dart`
Expected: PASS, все 13 тестов.

Если строка ожидаемого значения разошлась с фактической (кавычки,
пробелы) — исправлять **тест**, а не реализацию: эталон здесь —
поведение `team_logger`, а не догадка о нём.

- [ ] **Step 5: Проверить анализатор**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 6: Коммит**

```bash
git add lib/src/details/log_node.dart test/log_node_test.dart
git commit -m "feat: render node names and values in the tree model"
```

---

### Task 4: Виджет строки дерева

**Files:**
- Create: `lib/src/details/log_node_tile.dart`

**Interfaces:**
- Consumes: `LogNode`, `nameText`, `valueText`, `headerText` из Tasks 2-3;
  `ansiText2TextSpan` из `lib/src/ansi_utils.dart`.
- Produces: `class LogNodeTile extends StatelessWidget` с параметрами
  `LogNode node`, `LogTheme theme`, `bool real`, `bool expanded`,
  `bool expandable`, `void Function()? onTap`.

- [ ] **Step 1: Написать виджет**

Отступ — по `node.depth`. Стрелка рисуется только для раскрываемых узлов,
для остальных — пустое место той же ширины, чтобы колонки не плясали.
Бейджи `hidden` и `computed` — существующий `BorderContainer` из Task 1.

```dart
import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import '../ansi_utils.dart';
import '../uikit/border_container.dart';
import 'log_node.dart';

const double _fontSize = 11;
const double _indent = 14;
const double _arrowSize = 14;

/// One row of the log data tree.
class LogNodeTile extends StatelessWidget {
  final LogNode node;
  final LogTheme theme;
  final bool real;
  final bool expanded;
  final bool expandable;
  final void Function()? onTap;

  const LogNodeTile({
    super.key,
    required this.node,
    required this.theme,
    required this.real,
    required this.expanded,
    required this.expandable,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = node.showName ? node.nameText(theme) : '';
    final text = expanded
        ? node.headerText(theme: theme, real: real)
        : node.valueText(theme: theme, real: real);
    final line = name.isEmpty || text.isEmpty
        ? '$name$text'
        : '$name${theme.styledColon} $text';

    return InkWell(
      onTap: expandable ? onTap : null,
      child: Padding(
        padding: EdgeInsets.only(left: _indent * node.depth, top: 1,
            bottom: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _arrowSize,
              child: expandable
                  ? Icon(
                      expanded
                          ? Icons.arrow_drop_down
                          : Icons.arrow_right,
                      size: _arrowSize,
                    )
                  : null,
            ),
            Expanded(
              child: RichText(
                text: ansiText2TextSpan(
                  line,
                  defaulStyle: theme.data.normal,
                  fontSize: _fontSize,
                ),
              ),
            ),
            if (node.hidden)
              BorderContainer(
                text: 'hidden',
                style: theme.data.dim,
                defaultStyle: theme.data.normal,
                topLeftRounded: true,
                topRightRounded: true,
                borderLeftRounded: true,
                borderRightRounded: true,
              ),
            if (node.computed)
              BorderContainer(
                text: 'computed',
                style: theme.data.emphasis,
                defaultStyle: theme.data.normal,
                topLeftRounded: true,
                topRightRounded: true,
                borderLeftRounded: true,
                borderRightRounded: true,
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Проверить анализатор**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 3: Коммит**

```bash
git add lib/src/details/log_node_tile.dart
git commit -m "feat: add the tree row widget"
```

---

### Task 5: Экран LogDetails

**Files:**
- Create: `lib/src/details/log_details.dart`

**Interfaces:**
- Consumes: `LogNode`, `LogNodeTile`, `BorderContainer`.
- Produces: `class LogDetails extends StatefulWidget` с конструктором
  `const LogDetails(Log log, LogTheme theme, {super.key})`.

- [ ] **Step 1: Написать экран**

Плоский список строится обходом от корня: раскрытые узлы (по набору путей)
отдают детей, свёрнутые — нет. Набор путей живёт в состоянии, поэтому
переключение тумблера раскрытие не теряет.

```dart
import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import '../ansi_utils.dart';
import '../uikit/border_container.dart';
import 'log_node.dart';
import 'log_node_tile.dart';

final ThemeData _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.lightBlue,
    brightness: Brightness.dark,
  ),
);

const double _padding = 6;
const double _messageFontSize = 12;
const double _dataFontSize = 11;
const _stackTraceBuilder = LogStackTrace(showIndexes: true);
const _row = LogRow(children: [], maxLength: 10000);

/// A screen with everything one log holds.
///
/// Two modes. As logged: views are drawn, hidden properties are omitted —
/// exactly what the console shows. Real data: the values behind the views,
/// the hidden properties, and no `Loggable.sanitizer` — the screen reads the
/// objects from memory, the way a debugger's inspector does.
///
/// The tree is lazy, so a mutable object is shown as it is at the moment a
/// node gets expanded, not as it was when the log was written.
class LogDetails extends StatefulWidget {
  final Log log;
  final LogTheme theme;

  const LogDetails(this.log, this.theme, {super.key});

  @override
  State<LogDetails> createState() => _LogDetailsState();
}

class _LogDetailsState extends State<LogDetails> {
  final _expanded = <String>{};
  bool _real = false;

  @override
  void initState() {
    super.initState();

    // The first level is open from the start: a collapsed root would show
    // nothing but the summary the list already shows.
    for (final node in LogNode.root(widget.log.data).children(real: _real)) {
      if (node.expandable(real: _real)) _expanded.add(node.path);
    }
  }

  List<LogNode> _flatten() {
    final rows = <LogNode>[];

    void walk(LogNode node) {
      rows.add(node);
      if (!_expanded.contains(node.path)) return;
      for (final child in node.children(real: _real)) {
        walk(child);
      }
    }

    final root = LogNode.root(widget.log.data);
    if (!root.expandable(real: _real)) {
      return widget.log.hasData ? [root] : const [];
    }

    for (final child in root.children(real: _real)) {
      walk(child);
    }

    return rows;
  }

  void _toggle(LogNode node) => setState(() {
        if (!_expanded.remove(node.path)) _expanded.add(node.path);
      });

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final theme = widget.theme;
    final rows = _flatten();

    return Theme(
      data: _theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text('#${log.num} ${log.levelName}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: _padding),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('as logged')),
                  ButtonSegment(value: true, label: Text('real data')),
                ],
                selected: {_real},
                onSelectionChanged: (selection) =>
                    setState(() => _real = selection.first),
              ),
            ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(_padding),
          itemCount: rows.length + 2,
          itemBuilder: (context, index) => switch (index) {
            0 => _Head(log: log, theme: theme),
            final i when i <= rows.length => _row2tile(rows[i - 1]),
            _ => _Tail(log: log, theme: theme),
          },
        ),
      ),
    );
  }

  Widget _row2tile(LogNode node) => LogNodeTile(
        node: node,
        theme: widget.theme,
        real: _real,
        expanded: _expanded.contains(node.path),
        expandable: node.expandable(real: _real),
        onTap: () => _toggle(node),
      );
}
```

- [ ] **Step 2: Написать шапку и подвал экрана**

`_Head` — уровень, время, путь, номер, traceIds, теги и сообщение;
`_Tail` — ошибка и стек-трейс. Оба без ограничений по высоте, в отличие от
`LogItem`.

Внимание: `use_key_in_widget_constructors` из `flutter_lints` требует `key`
даже у приватного виджета, а неиспользуемый именованный параметр ловит
другое правило. В проекте для этого сложился приём — `super.key` со строкой
`// ignore: unused_element_parameter` над ним (см. `_LogsList`, `_Starter` в
`logs.dart`). Оба виджета ниже следуют ему.

Дописать в тот же файл:

```dart
class _Head extends StatelessWidget {
  final Log log;
  final LogTheme theme;

  const _Head({
    // ignore: unused_element_parameter
    super.key,
    required this.log,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _padding,
        children: [
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: [
              BorderContainer(
                text: log.levelName,
                style: theme.data.levelNameStyle,
                defaultStyle: theme.data.normal,
                borderLeftRounded: true,
                borderRightRounded: true,
                topLeftRounded: true,
                topRightRounded: true,
              ),
              BorderContainer(
                text: LogTime.timeToString(log.time),
                style: theme.data.timeStyle,
                defaultStyle: theme.data.normal,
                borderLeftRounded: true,
                borderRightRounded: true,
                topLeftRounded: true,
                topRightRounded: true,
              ),
              BorderContainer(
                text: log.path,
                style: theme.data.pathStyle,
                defaultStyle: theme.data.normal,
                borderLeftRounded: true,
                borderRightRounded: true,
                topLeftRounded: true,
                topRightRounded: true,
              ),
              for (final traceId in log.traceIds)
                BorderContainer(
                  text: traceId.toString(),
                  style: theme.main.traceIdStyle,
                  defaultStyle: theme.data.normal,
                  borderLeftRounded: true,
                  borderRightRounded: true,
                  topLeftRounded: true,
                  topRightRounded: true,
                ),
              for (final tag in log.tags)
                BorderContainer(
                  text: '#$tag',
                  style: theme.main.tagsStyle,
                  defaultStyle: theme.data.normal,
                  borderLeftRounded: true,
                  borderRightRounded: true,
                  topLeftRounded: true,
                  topRightRounded: true,
                ),
            ],
          ),
          if (log.message.isNotEmpty)
            RichText(
              text: ansiText2TextSpan(
                theme.formatMessage(
                  theme.formatValue(
                    log.message,
                    escapeAnsiCodes: LoggableConfig.defaultEscapeAnsiCodes,
                  ),
                  escapeAnsiCodes: false,
                ),
                defaulStyle: theme.data.normal,
                fontSize: _messageFontSize,
              ),
            ),
        ],
      );
}

class _Tail extends StatelessWidget {
  final Log log;
  final LogTheme theme;

  const _Tail({
    // ignore: unused_element_parameter
    super.key,
    required this.log,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final errorTheme = theme.main.error;
    final error = log.error;
    final stackTrace = _stackTraceBuilder(log, errorTheme, _row, null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: _padding,
      children: [
        if (error != null)
          RichText(
            text: ansiText2TextSpan(
              '${errorTheme.data.sectionStyle(errorTheme.main.errorTitle)}'
              '${errorTheme.styledColon}'
              ' ${errorTheme.formatMessage(
                errorTheme.formatValue(
                  '$error',
                  escapeAnsiCodes: LoggableConfig.defaultEscapeAnsiCodes,
                ),
                escapeAnsiCodes: false,
              )}',
              defaulStyle: errorTheme.data.normal,
              fontSize: _dataFontSize,
            ),
          ),
        if (stackTrace.lines.isNotEmpty)
          RichText(
            text: ansiText2TextSpan(
              stackTrace.lines.join('\n'),
              defaulStyle: errorTheme.data.normal,
              fontSize: _dataFontSize,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: Проверить анализатор**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 4: Коммит**

```bash
git add lib/src/details/log_details.dart
git commit -m "feat: add the log details screen"
```

---

### Task 6: Открытие по тапу и экспорт

**Files:**
- Modify: `lib/flutter_team_logger.dart`
- Modify: `lib/src/logs.dart:961-966`

**Interfaces:**
- Consumes: `LogDetails` из Task 5.

- [ ] **Step 1: Экспортировать виджет**

`lib/flutter_team_logger.dart` — добавить строку рядом с существующими
экспортами:

```dart
export 'src/details/log_details.dart';
```

- [ ] **Step 2: Открывать экран по тапу**

В `lib/src/logs.dart` добавить импорт `import 'details/log_details.dart';` и
дописать `onTap` у `LogItem` в `_LogsList` (строки 961-966). `onTapDown`
остаётся: список сначала встаёт на паузу.

```dart
                  child: LogItem(
                    log,
                    controller.widget.theme[log.level],
                    removed: controller.isLogRemoved(log),
                    onTapDown: controller.pause,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LogDetails(
                          log,
                          controller.widget.theme[log.level],
                        ),
                      ),
                    ),
                  ),
```

- [ ] **Step 3: Проверить анализатор**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 4: Коммит**

```bash
git add lib/flutter_team_logger.dart lib/src/logs.dart
git commit -m "feat: open the details screen on log tap"
```

---

### Task 7: Демонстрация в example

Сейчас в примере есть `view:` и `LoggableMultiView`, но нет ни одного
`hidden` и ни одного `computed` — тумблер нечего показывать.

**Files:**
- Modify: `example/lib/data.dart`
- Modify: `example/lib/main.dart:222` (рядом с логом `NotLoggableObject`)

- [ ] **Step 1: Добавить класс с hidden и computed**

Дописать в `example/lib/data.dart`:

```dart
/// Demonstrates what the details screen can reveal: a masked value, a
/// property kept out of the log, and one computed from the others.
final class Payment with Loggable {
  final String pan;
  final int amount;
  final double accuracy;

  const Payment({
    required this.pan,
    required this.amount,
    required this.accuracy,
  });

  @override
  void collectLoggableData(LoggableData data) => data
    ..prop('pan', pan, view: '**** ${pan.substring(pan.length - 4)}')
    ..prop('amount', amount, units: 'cents')
    ..hidden('accuracy', accuracy)
    ..computed('total', '${amount / 100} USD');
}
```

- [ ] **Step 2: Залогировать его**

Дописать в `example/lib/main.dart` после строки 222:

```dart
  log.d(
    'payment',
    data: const Payment(
      pan: '4111111111111234',
      amount: 12345,
      accuracy: 12.5,
    ),
  );
```

- [ ] **Step 3: Проверить анализатор в example**

Run: `cd example && dart analyze`
Expected: `No issues found!`

- [ ] **Step 4: Прогнать приложение вручную**

Run: `cd example && flutter run -d macos`

Проверить по списку: тап по логу открывает экран; дерево раскрывается и
сворачивается; тумблер переключает `pan` с `**** 1234` на настоящий номер;
`accuracy` появляется только в режиме «real data» с бейджем `hidden`;
`total` в этом режиме показывает `<computed>` с бейджем; лог без данных
(`log.d('message')`) открывается без дерева; лог с ошибкой показывает стек
полностью; `Map` и `List` из `Data.postHeaders` раскрываются.

- [ ] **Step 5: Коммит**

```bash
git add example/lib/data.dart example/lib/main.dart
git commit -m "example: show hidden, computed and view data"
```

---

### Task 8: Документация и версия

**Files:**
- Modify: `README.md`, `README.ru.md`, `CHANGELOG.md`, `pubspec.yaml`,
  `docs/architecture.md`, `docs/conventions.md`, `docs/handoff.md`,
  `docs/backlog.md`
- Modify: `docs/records/2026-08-24[5]-log-details-design.md` (шапка
  состояния), `docs/records/2026-08-24[6]-log-details-plan.md` (шапка
  состояния)

- [ ] **Step 1: README на двух языках**

В `README.md` — раздел про экран деталей с предупреждением, дословно по
смыслу:

> Tapping a log opens a screen with everything the log holds, including a
> tree of its `data`. The screen has two modes. **As logged** draws exactly
> what the console prints. **Real data** draws the values behind the views,
> shows properties marked `hidden`, and does **not** apply
> `Loggable.sanitizer` — it reads the objects from memory, the way a
> debugger's inspector does. If a value must never reach the screen, keep it
> out of the log, not behind a view or a sanitizer rule.

В `README.ru.md` — тот же раздел по-русски (перевод не должен отставать,
`docs/conventions.md`).

- [ ] **Step 2: CHANGELOG и версия**

`pubspec.yaml`: `version: 0.7.1`. В `CHANGELOG.md` — запись 0.7.1 в стиле
существующих: экран деталей, тумблер режимов, оговорка про `sanitizer`.

- [ ] **Step 3: Документы для агентов**

- `docs/architecture.md` — раздел про `lib/src/details/` (модель узлов,
  плоский список, два режима) и про переехавший `BorderContainer`;
- `docs/conventions.md` — в проекте появились тесты: `flutter test` на
  модель узлов рядом с обязательным `dart analyze`; виджеты не покрываются;
- `docs/handoff.md` — текущее состояние: 0.7.1 готова, не опубликована;
- `docs/backlog.md` — удалить пункт «Полноценный вывод информации по
  конкретному логу», добавить копирование лога в буфер;
- шапки обеих записей в `docs/records/` — «сделано и смержено (коммит)».

- [ ] **Step 4: Финальная проверка**

Run: `dart analyze && cd example && dart analyze && cd .. && flutter test`
Expected: `No issues found!` дважды и все тесты зелёные.

- [ ] **Step 5: Коммит**

```bash
git add -A
git commit -m "docs: document the log details screen, bump to 0.7.1"
```

---

## Что в план не входит

- Публикация на pub.dev — отдельная задача, требует явного разрешения
  владельца одним сообщением (`AGENTS.md`).
- Копирование лога в буфер — уходит в `docs/backlog.md` (решение 6 спеки).
- Правка формулировки про in-app viewer в доках `team_logger` — другой
  репозиторий.
- Публичный геттер конвертеров и `Prop.isComputed` в `team_logger` —
  сняли бы два ограничения спеки, но это другой пакет и другой релиз.
