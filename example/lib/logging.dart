import 'package:team_logger/team_logger.dart';

final theme = LogTheme.defaultActiveTheme;

final logStorage = LogStorage(maxCount: 100);

final log = Logger('app')
  ..publisher = MultiPublisher([
    ConsoleLogPrinter(
      theme: theme,
      rows: const [
        LogRow(
          maxLength: 140,
          children: [
            LogSequenceNum(),
            LogLevelName.short(),
            LogTime.onlyTime(),
            LogPath(),
            LogTraceId(),
            LogMessage(
              showStackTrace: true,
              controlledPackages: {
                'team_logger',
                'flutter_team_logger',
              },
            ),
          ],
          tail: [
            LogTags(),
          ],
        ),
      ],
    ),
    logStorage,
  ]);
