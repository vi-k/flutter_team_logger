# Устройство проекта

Flutter-виджеты для отображения логов из [team_logger](https://pub.dev/packages/team_logger).
Пакет — чисто UI-надстройка над `team_logger`: своих `Publisher`/`Logger` не
реализует, только читает и рендерит то, что `team_logger` уже собрал.

Здесь — то, что меняется редко. Текущее состояние — `docs/handoff.md`.

## Публичный API

`lib/flutter_team_logger.dart` экспортирует три виджета:

- `Logs` (`lib/src/logs.dart`) — экран списка логов целиком (AppBar,
  фильтр, список, пауза/возобновление).
- `LogItem` (`lib/src/log_item.dart`) — виджет одного лога, можно
  использовать отдельно от `Logs`.
- `LogDetails` (`lib/src/details/log_details.dart`) — экран одного лога
  целиком с деревом данных, открывается по тапу из `Logs`.

Всё остальное в `lib/src/` — приватная реализация.

## Logs / LogsState

`Logs` оборачивает `LogStorage` из `team_logger` в реверсированном виде
(`logStorage.reversed`) и держит собственный список логов (`_logs`,
`_newLogs`), потому что `team_logger` может удалять логи из `LogStorage`, а
UI должен успеть показать их удаление.

- Подписывается на `LogStorage.onChanged` (add / remove / clear) и обновляет
  свои списки и `Filter`.
- Пауза/возобновление: при скролле вверх пользователем (`pause()`) список
  замораживается — новые логи копятся в `_newLogs`, удаления — в
  `_removedLogs`. При `resume()` отложенные удаления применяются, отложенные
  логи выезжают через анимацию.
- Режим "новые логи отдельно" (`_newLogsMode`) включается на паузе или когда
  новых логов накопилось ≥10 — в AppBar тогда показывается `"1000 +13"`
  вместо мгновенного пересчёта суммы.
- `LogsState` доступен через `Logs.of(context)` (`InheritedWidget`), `Filter`
  — через `Logs.filterOf(context)` (`InheritedNotifier`).
- Рендер — `ScrollablePositionedList` (`reverse: true`) с `LogItem` на
  каждый лог; UI фильтра (чипы) собран прямо в `logs.dart`
  (`_FilterEdit`, `_FilterEditRow`, `_FilterResult`).

## LogItem

Рендерит один `Log`: уровень, время, путь, номер (`log.num`), traceId,
сообщение, данные (`Loggable` / `LoggableMultiData`), ошибку, стектрейс
(через `LogStackTrace` из `team_logger`), теги. Цвета и стили берутся из
`LogTheme` (тема `team_logger`, описанная в ANSI-стилях) и конвертируются во
Flutter через `ansi_utils.dart`.

## details/ — экран одного лога

`LogDetails` показывает лог целиком: шапку, сообщение, дерево `data`, ошибку
и стек — всё без ограничений по высоте, в отличие от `LogItem`.

- `log_node.dart` — `LogNode`: модель узла дерева. Рекурсивно разбирает
  значение (`Loggable` → `logClassInfo().props`, `LoggableData` → `props`,
  `LoggableMultiData` → секции, `Map` → записи, `List`/`Set` → элементы,
  `LoggableWrapper` — прозрачен) и рендерит имя и значение узла в
  ANSI-текст теми же вызовами `team_logger`, что и консоль. Ветвление
  `valueText` повторяет `Prop.toLogString`.
- `log_node_tile.dart` — `LogNodeTile`: одна строка дерева (отступ по
  глубине, стрелка, имя, значение, бейджи `hidden`/`computed`).
- `log_details.dart` — экран: AppBar с тумблером режима, шапка (`_Head`),
  плоский список узлов, ошибка и стек (`_Tail`).

Два режима. «As logged» — то же, что печатает консоль: применяется `view`,
`hidden` не показываются. «Real data» — значения под `view`, показанные
`hidden` и **без** `Loggable.sanitizer`: экран читает объекты из памяти, как
инспектор отладчика. Это осознанное решение, а не упущение —
`docs/records/2026-08-24[5]-log-details-design.md`.

Раскрытые узлы уплощаются в один `ListView.builder`, состояние раскрытия —
набор путей в состоянии экрана, поэтому переключение режима его не теряет.
Свёрнутый узел показывает консольную сводку целиком (`_Address(city:
"Berlin")`), раскрытый — имя класса и детей отдельными строками.

Признак `computed` в публичном API `team_logger` отсутствует, поэтому
`log_node.dart` ловит общий const-инстанс зондом
(`Loggable.mapBuilder()..computed(...)`) и сравнивает через `identical`.

## Filter (`lib/src/filter/`)

- `filter.dart` — `Filter`: фасад, привязанный к `LogsState` через колбэки
  доступа к исходным спискам логов. Считает отфильтрованные `logs`/`newLogs`
  и "доступные значения" (`availableLevels`/`Loggers`/`TraceIds`/`Tags` —
  счётчики `(отфильтровано, всего)` для чипов фильтра).
- `filter_exp.dart` — `FilterExp`: одно OR∩AND-выражение. `Filter` хранит
  список `FilterExp`, объединённых через OR (`[e1] ∪ [e2]`). `FilterOr` /
  `FilterAnd` — операции добавления/удаления facet-значений (level / logger /
  traceId / tag) с переносом значения между `or` и `and` при конфликте.
- `filter_value.dart` (`part of filter_exp.dart`) — sealed `FilterValue`:
  `FilterLevel` / `FilterLogger` / `FilterTraceId` / `FilterTag`, плюс
  Single-варианты (`FilterSingleLevel.any`, `FilterSingleLogger.any`) —
  маркеры "любое значение" для AND.

## utils/ — инфраструктура нотификаций

В кодовой базе исторически сосуществуют два разных механизма нотификации —
не путать местами при правках:

- `stream_notifier.dart` — `StreamNotifier`/`StreamNotifierMixin`: свой
  `Stream<void>`-based нотификатор (`addListener`/`removeListener`/
  `notifyListeners`), НЕ `ChangeNotifier`. От него наследуются `Filter` и
  `FilterExp`.
- `stream_notifier_ext.dart` — расширение `asListenable()`, оборачивающее
  `StreamNotifier` во Flutter `Listenable` (нужно, чтобы отдать `Filter` в
  `InheritedNotifier`).
- `stream_notifier_builder.dart` — `StreamNotifierBuilder`, тонкая обёртка
  над `StreamBuilder<void>` для стрим-нотификаторов.
- `lib/src/notifier.dart` (вне `utils/`) — отдельный простой `Notifier` на
  `ChangeNotifier`, используется только для `LogsState.onLogsChanged`.

## ansi_utils.dart

Мост между `ansi_escape_codes` (`Style`/`Color16`/`Color256`/`ColorRgb` —
так `team_logger` описывает тему логов) и Flutter (`TextStyle`/`TextSpan`/
`Color`). `team_logger` сам ничего не знает о Flutter — вся конвертация
цветов и парсинг ANSI-текста (`ansi.Parser`) для `RichText` живёт здесь.

## uikit/

- `chip.dart` — `Chip`/`FilterChip`, обычные presentational-виджеты для
  чипов фильтра, ничего специфичного для логов в них нет.
- `border_container.dart` — `BorderContainer`, бордюрная плашка (уровень,
  время, путь, номер, теги, бейджи дерева). Общая для `LogItem` и
  `LogDetails`, поэтому живёт здесь, а не внутри `log_item.dart`.

## Внешние зависимости

- `team_logger` — модель данных: `Log`, `LogStorage`, `LogMainTheme`/
  `LogTheme`, `Loggable`/`LoggableData`, `LogLevels`, `LogStackTrace`,
  `TraceId` и т.д.
- `ansi_escape_codes` — используется напрямую (`ansi.Style` и т.п.) и
  транзитивно через темы `team_logger`.
- `scrollable_positioned_list` — список логов с управляемой позицией
  скролла.
- `meta` — аннотации (`@immutable` и т.п.).

## example/

Отдельное desktop-приложение (`window_manager`) — демонстрирует `Logs`/
`LogItem` в работе: генерирует логи по таймеру на всех уровнях, показывает
форматирование разных типов данных (`Loggable`, `LoggableMultiData`,
коллекции, enum, `double`/`int` с форматом и `units`, кастомные конвертеры
через `Loggable.registerTypeConverter`).

- `example/lib/logging.dart` — глобальные `log`/`logStorage`/`theme`.
- `example/lib/data.dart` — тестовые данные для демонстрации форматирования.
- `example/lib/app.dart`, `home.dart` — сборка экрана поверх `Logs`.
