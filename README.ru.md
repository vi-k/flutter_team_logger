# flutter_team_logger

Flutter-виджеты для отображения логов из [team_logger](https://pub.dev/packages/team_logger) в UI.

> **Статус: ранняя стадия.** Пока делается для внутреннего использования;
> публичный API может меняться между minor-версиями без предупреждения.

## Возможности

- `Logs` — готовый экран логов: живое обновление из `LogStorage`, пауза
  при скролле вверх со счётчиком "новых логов", возобновление с анимацией
  подгрузки и фильтр по level / logger / traceId / tag.
- `LogItem` — виджет одного лога, можно использовать отдельно от `Logs`.

Пакет только отображает то, что уже собрал `team_logger` — настройка
логирования (логгеры, publisher'ы, темы) целиком остаётся задачей
`team_logger`.

## Начало работы

```yaml
dependencies:
  team_logger: ^0.7.0
  flutter_team_logger: ^0.7.0
```

## Использование

```dart
final logStorage = LogStorage(maxCount: 1000);
final log = Logger('app')..publisher = MultiPublisher([logStorage]);

// ...

log.i('hello');

// ...

Logs(
  theme: LogMainTheme.defaultActiveTheme,
  logStorage: logStorage,
)
```

Полноценный пример — в `example/`.

## Дополнительно

Вопросы и проблемы — в [репозитории на GitHub](https://github.com/vi-k/flutter_team_logger).
