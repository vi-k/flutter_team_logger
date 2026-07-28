# Обновление team_logger до 0.4.1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Обновить зависимость `team_logger` с 0.3.0 до 0.4.1 (опубликован на pub.dev), починить breaking changes в `lib/` и `example/`, поднять версию пакета до 0.4.0.

**Architecture:** Механическая миграция API по changelog 0.4.0/0.4.1. В 0.4.1 реэкспорт `ansi_escape_codes` сужен до `Style`, `NoStyle`, `Color16`, `Color256` — коллизий имён с Flutter (`Color`, `Colors`, `Stack`, `State`, `Text`), которые были в 0.4.0, больше нет, поэтому импорты менять не нужно. Остаются точечные переименования и один переписанный интерфейс.

**Tech Stack:** Dart 3.7 / Flutter (fvm 3.29.2), team_logger 0.4.1, ansi_escape_codes 3.1.2.

## Global Constraints

- `team_logger: ^0.4.1` — версия опубликована на pub.dev (проверено), локальный path-override НЕ нужен.
- Версия пакета `flutter_team_logger`: `0.4.0` (конвенция репо: minor пакета следует за minor team_logger; прецедент — team_logger 0.2.1 → пакет 0.2.0, коммит 715f5f3).
- SDK constraint не меняется: `sdk: ^3.6.0`.
- Прямая зависимость `ansi_escape_codes: ^3.1.2` остаётся: предопределённые стили (`ansi.gray8` в `example/lib/logging.dart`) в 0.4.1 больше не реэкспортируются из team_logger — они и так берутся из прямого импорта `as ansi`. Ничего менять не нужно.
- Тестов в репо нет; верификация каждой задачи — `dart analyze` с результатом `No issues found!`.
- Все правки заранее проверены спайком против опубликованного team_logger 0.4.1: после них `dart analyze lib` (корень) и `dart analyze lib` (example) чисты.

Полный список breaking changes 0.4.x, затрагивающих этот репозиторий:

| Изменение в team_logger 0.4.x | Где встречается |
|---|---|
| `Log.sequenceNum` → `Log.num` | `lib/src/log_item.dart:229` |
| `LogThemeData.sequenceNumStyle` → `numStyle` | `lib/src/log_item.dart:230` |
| `collectionMaxLength` → `collectionMaxCount` | `example/lib/main.dart` ×8 (строки 102, 111, 132, 139, 146, 155, 214, 240), `example/lib/data.dart:216` |
| `LoggableView(value, 'units')` — units стал именованным (`{String? units}`) | `example/lib/data.dart:201,202,211,212` |
| `LoggableTypeConverter` сокращён до `LoggableData convertToData(T obj)` | `example/lib/data.dart:244-257` |
| `LoggableResolvedConfig` → `LoggableEffectiveConfig` (тип исчез из сигнатуры конвертера) | там же |
| `LogSequenceNum` → `LogNum` (принтер) | `example/lib/logging.dart:19` (в закомментированном коде) |

Не затронуто (проверено спайком): `LogStorage`/`LogStorageEvent`/`onChanged`, `LogTime.timeToString`, `LogMainTheme`, `LogLevels.name`, `Logger.copyWith`, весь filter-код, все импорты (коллизий имён в 0.4.1 нет).

Вне скоупа: новые фичи 0.4.x (`team_logger_io.dart` / `FileLogStorage`, `LogNum`-принтер, `Prop.toJson` и т.д.) — библиотека их не использует; фильтр «диапазон по номерам» из TODO.md — отдельная задача.

---

### Task 1: Bump зависимостей + миграция lib/

**Files:**
- Modify: `pubspec.yaml:16` (team_logger constraint)
- Modify: `example/pubspec.yaml:16` (team_logger constraint)
- Modify: `lib/src/log_item.dart:229-230` (переименования)
- Modify (генерируется): `example/pubspec.lock` (коммитится — example это приложение); корневой `pubspec.lock` в git НЕ добавлять (игнорируется по `.gitignore`, конвенция для библиотек)

**Interfaces:**
- Consumes: team_logger 0.4.1 с pub.dev.
- Produces: компилирующийся `lib/` против 0.4.1; example пока сломан (чинится в Task 2).

- [ ] **Step 1: Обновить constraint в pubspec.yaml**

В `pubspec.yaml` заменить:

```yaml
  team_logger: ^0.3.0
```

на:

```yaml
  team_logger: ^0.4.1
```

- [ ] **Step 2: Обновить constraint в example/pubspec.yaml**

В `example/pubspec.yaml` заменить:

```yaml
  team_logger: ^0.2.1
```

на:

```yaml
  team_logger: ^0.4.1
```

- [ ] **Step 3: Обновить зависимости**

Run: `flutter pub get && (cd example && flutter pub get)`
Expected: `Got dependencies!` в обоих; в `pubspec.lock` team_logger 0.4.1.

- [ ] **Step 4: Убедиться, что анализатор падает ожидаемо (baseline поломки)**

Run: `dart analyze lib`
Expected: FAIL ровно с 2 ошибками — `undefined_getter 'sequenceNum'` (log_item.dart:229) и `undefined_getter 'sequenceNumStyle'` (log_item.dart:230). Никаких `ambiguous_import` быть не должно.

- [ ] **Step 5: Переименовать sequenceNum в lib/src/log_item.dart**

Строки 229–230, заменить:

```dart
                        text: log.sequenceNum.toString(),
                        style: theme.data.sequenceNumStyle,
```

на:

```dart
                        text: log.num.toString(),
                        style: theme.data.numStyle,
```

- [ ] **Step 6: Проверить, что lib/ чист**

Run: `dart analyze lib`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml example/pubspec.yaml example/pubspec.lock lib/src/log_item.dart
git commit -m "$(cat <<'EOF'
chore: update team_logger to 0.4.1 and migrate lib

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

(Example на этом коммите ещё сломан — чинится следующим коммитом.)

---

### Task 2: Миграция example/

**Files:**
- Modify: `example/lib/main.dart` — 8 строк с `collectionMaxLength` (102, 111, 132, 139, 146, 155, 214, 240)
- Modify: `example/lib/data.dart:200-216` (LoggableView, collectionMaxLength), `:244-257` (конвертер)
- Modify: `example/lib/logging.dart:19` (комментарий)

**Interfaces:**
- Consumes: `flutter_team_logger` из Task 1; team_logger 0.4.1: `LoggableTypeConverter.convertToData(T obj) → LoggableData`, `Loggable.builder(...) → LoggableData`, `LoggableView(Object? value, {String? units})`, `LoggableConfig({int? collectionMaxCount, ...})`.
- Produces: компилирующийся example.

- [ ] **Step 1: Переименовать collectionMaxLength → collectionMaxCount**

Run: `sed -i '' 's/collectionMaxLength:/collectionMaxCount:/g' example/lib/main.dart example/lib/data.dart`
Затронет 8 мест в main.dart (все вида `config: const LoggableConfig(collectionMaxLength: 2)`, одно с `3`) и одно в data.dart (`..prop('points', points, collectionMaxLength: 2)`).

- [ ] **Step 2: Сделать units именованным в LoggableView (example/lib/data.dart)**

Строки 200–203, заменить:

```dart
      view: LoggableMultiView([
        LoggableView(duration.inMinutes, 'min'),
        LoggableView(duration.inSeconds, 'sec'),
      ]),
```

на:

```dart
      view: LoggableMultiView([
        LoggableView(duration.inMinutes, units: 'min'),
        LoggableView(duration.inSeconds, units: 'sec'),
      ]),
```

Строки 210–213, заменить:

```dart
      view: LoggableMultiView([
        LoggableView(speed, 'm/s'),
        LoggableView(speed * 3.6, 'km/h'),
      ]),
```

на:

```dart
      view: LoggableMultiView([
        LoggableView(speed, units: 'm/s'),
        LoggableView(speed * 3.6, units: 'km/h'),
      ]),
```

- [ ] **Step 3: Переписать NotLoggableObjectConverter (example/lib/data.dart)**

Заменить целиком (строки 244–257):

```dart
final class NotLoggableObjectConverter
    implements LoggableTypeConverter<NotLoggableObject> {
  @override
  String call(
    NotLoggableObject obj,
    LogTheme theme,
    int depth,
    LoggableResolvedConfig config,
  ) =>
      (Loggable.builder(obj)
            ..prop('name', obj.name)
            ..prop('list', obj.list))
          .toLogString(theme: theme, depth: depth, config: config);
}
```

на:

```dart
final class NotLoggableObjectConverter
    implements LoggableTypeConverter<NotLoggableObject> {
  @override
  LoggableData convertToData(NotLoggableObject obj) => Loggable.builder(obj)
    ..prop('name', obj.name)
    ..prop('list', obj.list);
}
```

(Каскад `..prop()..prop()` возвращает сам `LoggableData` — форматирование в строку/JSON библиотека теперь делает сама.)

- [ ] **Step 4: Обновить закомментированный принтер (example/lib/logging.dart)**

Строка 19, заменить:

```dart
    //         LogSequenceNum(),
```

на:

```dart
    //         LogNum(),
```

- [ ] **Step 5: Проверить, что example чист**

Run: `cd example && dart analyze lib && cd ..`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add example/lib/main.dart example/lib/data.dart example/lib/logging.dart
git commit -m "$(cat <<'EOF'
chore: migrate example to team_logger 0.4.x API

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Версия пакета, CHANGELOG, финальная проверка

**Files:**
- Modify: `pubspec.yaml:3` (version)
- Modify: `CHANGELOG.md` (новая секция сверху)

**Interfaces:**
- Consumes: результат Task 1–2.
- Produces: пакет 0.4.0, готовый к публикации.

- [ ] **Step 1: Поднять версию пакета**

В `pubspec.yaml` заменить:

```yaml
version: 0.3.0
```

на:

```yaml
version: 0.4.0
```

- [ ] **Step 2: Добавить запись в CHANGELOG.md**

Вставить в начало файла (стиль существующих записей):

```markdown
## 0.4.0

- Update team_logger dependency to 0.4.1.

```

- [ ] **Step 3: Полная проверка репозитория**

Run: `flutter analyze`
Expected: `No issues found!` (оба пакета: корень + example).

- [ ] **Step 4: Смоук-тест example (опционально, если доступен девайс)**

Run: `cd example && flutter build macos --debug 2>&1 | tail -3 && cd ..`
Expected: сборка успешна. (Запуск и визуальная проверка UI — вручную.)

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "$(cat <<'EOF'
chore: bump project version to 0.4.0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
EOF
)"
```
