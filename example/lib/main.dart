import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:team_logger/team_logger.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data.dart';
import 'logging.dart';

const _timerPeriod = Duration(milliseconds: 2000);
// const _timerPeriod = Duration(milliseconds: 500);

Future<void> main() async {
  log.level = LogLevels.all;
  f();

  Object data(Timer timer) => {
        'tick': timer.tick,
        'now': DateTime.now(),
      };
  // Data.loggableObject,

  Timer.periodic(_timerPeriod, (timer) {
    log.d('timer debug 1', data: () => data(timer));
    log.d('timer debug 2', data: () => data(timer));
  });

  Timer.periodic(_timerPeriod * 2, (timer) {
    log.i('timer info 1', data: () => data(timer));
    log.i('timer info 2', data: () => data(timer));
  });

  Timer.periodic(_timerPeriod * 3, (timer) {
    log.w('timer warning 1', data: () => data(timer));
    log.w('timer warning 2', data: () => data(timer));
  });

  Timer.periodic(_timerPeriod * 4, (timer) {
    log.e('timer error 1', data: () => data(timer), error: Exception('test'));
    log.e('timer error 2', data: () => data(timer), error: Exception('test'));
  });

  await Chain.capture(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        size: Size(400, 800),
        // center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      // ignore: unawaited_futures
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      runApp(const App());
    },
    onError: (error, chain) {
      // ignore: avoid_print
      print(chain.terse);
    },
  );
}

void f() {
  final httpLog = log.copyWith(name: 'network', tags: {'http'});
  final eventLog = log.copyWith(name: 'events').createChild(name: 'polling');

  for (var i = 0; i < 1; i++) {
    for (final level in LogLevels.values) {
      log.trace(TraceId.auto('feature'), () {
        eventLog[level].log('Loggable object', data: Data.loggableObject);

        final httpTraceId = TraceId.auto('http');

        httpLog[level].log(
          Data.postUrl,
          traceId: httpTraceId,
          data: LoggableMultiData(
            {
              'HEADERS': Data.postHeaders,
              'BODY': Data.postBody,
            },
            config: const LoggableConfig(collectionMaxLength: 2),
          ),
          tags: ['post'],
        );
        httpLog[level].log(
          '[success][200 OK][/success] ${Data.postUrl}',
          traceId: httpTraceId,
          data: Loggable.from(
            Data.succesResponse,
            config: const LoggableConfig(collectionMaxLength: 2),
          ),
          tags: ['response'],
        );

        if (level >= LogLevels.error) {
          httpLog[level].log(
            '[500 Internal Server Error] ${Data.postUrl}',
            traceId: httpTraceId,
            data: Data.errorResponse,
            tags: ['response', 'error'],
          );
        }
      });
    }
  }

  log.d(
    'json',
    data: Loggable.from(
      Data.json,
      config: const LoggableConfig(collectionMaxLength: 2),
    ),
  );
  log.d(
    '',
    data: LoggableMultiData(
      {'JSON': Data.json},
      config: const LoggableConfig(collectionMaxLength: 2),
    ),
  );
  log.d(
    '',
    data: Loggable.from(
      Data.json,
      config: const LoggableConfig(collectionMaxLength: 2),
    ),
  );

  for (final l in LogLevels.values) {
    log[l].log(
      '',
      data: Loggable.from(
        Data.listOfLists,
        config: const LoggableConfig(collectionMaxLength: 2),
      ),
    );
  }

  log.d('LogTheme', data: theme);
  for (final l in LogLevels.values) {
    log[l].log(
      'LogLevelTheme',
      traceId: TraceId.auto('theme'),
      data: theme[l],
    );
  }

  log.d('Without error', stackTrace: StackTrace.current);
  log.d('With error', error: Exception('test'), stackTrace: StackTrace.current);
  log.d(
    '',
    error: Exception('Without message'),
    stackTrace: StackTrace.current,
  );
  log.d(
    'With data and error',
    data: {'error': 'internal error', 'code': 500},
    error: Exception('test'),
    stackTrace: StackTrace.current,
  );
  log.d(
    'With multi data and error',
    data: LoggableMultiData({
      'RESPONSE': {'error': 'internal error', 'code': 500},
    }),
    error: Exception('test'),
    stackTrace: StackTrace.current,
  );

  log.d(
    'enums',
    data: {
      'textAlign': LogTextAlign.left,
      'verticalAlign': LogVerticalAlign.top,
    },
  );
  log.d(
    'wrapped enums',
    data: Loggable.from(
      {
        'textAlign': LogTextAlign.left,
        'verticalAlign': LogVerticalAlign.top,
      },
      config: const LoggableConfig(enumDotShorthand: false),
    ),
  );

  log.d('list', data: [1, 2, 3]);
  log.d(
    'wrapped list',
    data: Loggable.from(
      [1, 2, 3],
      config: const LoggableConfig(collectionMaxLength: 2),
    ),
  );

  const notLoggableObject = NotLoggableObject('abc', [1, 2, 3]);
  Loggable.registerTypeConverter<NotLoggableObject>(
    NotLoggableObjectConverter(),
  );
  log.d('NotLoggableObject', data: notLoggableObject);

  log.d(
    'map',
    data: {'a': 1, 'b': 2, 'c': 3},
  );
  log.d(
    'built map',
    data: Loggable.mapBuilder()
      ..prop('a', 1, units: 'kg')
      ..prop('b', 2, units: 'm')
      ..prop('c', 3, units: 'sec'),
  );

  log.d(
    'storage snapshot',
    data: Loggable.from(
      logStorage.snapshot(),
      config: const LoggableConfig(collectionMaxLength: 3),
    ),
  );

  log.d(
    'double',
    data: Loggable.from(
      123456.0,
      config: const LoggableConfig(doubleFormat: '.2f', units: 'kg'),
    ),
  );

  log.d(
    'int',
    data: Loggable.from(
      123456,
      config: const LoggableConfig(intFormat: '+d', units: 'items'),
    ),
  );

  // For debugging:
  // for (var i = logStorage.count; i < logStorage.maxCount; i++) {
  //   log.d(
  //     'test #$i',
  //     traceId: TraceId.auto('test'),
  //     data: Data.loggableObject,
  //   );
  // }
}
