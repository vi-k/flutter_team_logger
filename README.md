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
- `LogDetails` — a screen with everything one log holds, opened by tapping a
  log in `Logs`, with an expandable tree of its `data`.

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

## The details screen

Tapping a log opens `LogDetails`: the head, the message, the error and the
stack trace in full, and a tree of the log's `data` that expands node by
node — objects, maps and collections alike.

The screen has two modes.

**As logged** draws exactly what the console prints: `view` substitutes are
applied and `hidden` properties are omitted.

**Real data** draws what is actually behind them — the value under each
`view`, plus the properties marked `hidden`. Properties added with
`computed` are shown in both modes and marked with a badge, since there is
no real value behind them.

> **Real data does not apply `Loggable.sanitizer`.** The mode exists to
> reveal what the log hides, and it reads the objects straight from memory,
> the way a debugger's inspector does — a redaction rule is not a barrier to
> it. Keep out of the log whatever must never reach the screen; a `view` or a
> sanitizer rule is a way to keep the log readable and the output clean, not
> a way to keep a secret from someone holding the app.

Objects rendered through `Loggable.registerTypeConverter` stay leaves: the
converter registry is private to `team_logger`, so their text is correct but
they cannot be expanded property by property. Lazy `Iterable`s are leaves
too — enumerating one for the tree would mean materializing it.

## Additional information

Issues and questions: the [GitHub repository](https://github.com/vi-k/flutter_team_logger).
