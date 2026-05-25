import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:team_logger/team_logger.dart';

final theme = LogMainTheme.defaultActiveTheme;
final uiTheme = theme.copyWith(
  tagsStyle: ansi.gray8,
);

final logStorage = LogStorage(maxCount: 1000, reverse: true);

final log = Logger('app')
  ..publisher = MultiPublisher([
    // ConsoleLogPrinter(
    //   theme: theme,
    //   rows: const [
    //     LogRow(
    //       maxLength: 140,
    //       children: [
    //         LogSequenceNum(),
    //         LogLevelName.short(),
    //         LogTime.onlyTime(),
    //         LogPath(),
    //         LogTraceId(),
    //         LogMessage(
    //           showStackTrace: true,
    //           controlledPackages: {
    //             'team_logger',
    //             'flutter_team_logger',
    //           },
    //         ),
    //       ],
    //       tail: [
    //         LogTags(),
    //       ],
    //     ),
    //   ],
    // ),
    logStorage,
  ]);
