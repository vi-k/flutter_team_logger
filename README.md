# flutter_team_logger

Flutter widgets for displaying logs from [team_logger](https://pub.dev/packages/team_logger) in the UI.

> **Status: early stage.** Built for internal use so far; the public API can
> still change between minor versions without notice.

## Features

- `Logs` — a ready-made log screen: live updates from `LogStorage`,
  pause-on-scroll with a "new logs" counter, resume with a catch-up
  animation, and a filter by level / logger / traceId / tag.
- `LogItem` — a single log entry widget, usable on its own outside of
  `Logs`.

The package only renders what `team_logger` already collected — logging
setup (loggers, publishers, themes) stays entirely `team_logger`'s job.

## Getting started

```yaml
dependencies:
  team_logger: ^0.7.0
  flutter_team_logger: ^0.7.0
```

## Usage

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

See `example/` for a complete demo app.

## Additional information

Issues and questions: the [GitHub repository](https://github.com/vi-k/flutter_team_logger).
