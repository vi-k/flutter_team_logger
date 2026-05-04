import 'package:flutter/material.dart';
import 'package:team_logger/team_logger.dart';

import 'app.dart';
import 'data.dart';
import 'logging.dart';

void main() {
  log.level = LogLevels.all;
  f();

  runApp(const App());
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
          data: const LoggableMultiData(
            {
              'HEADERS': Data.postHeaders,
              'BODY': Data.postBody,
            },
            collectionMaxLength: 2,
          ),
          tags: ['post'],
        );
        httpLog[level].log(
          '[success][200 OK][/success] ${Data.postUrl}',
          traceId: httpTraceId,
          data: Loggable.from(Data.succesResponse, collectionMaxLength: 2),
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

  log.d('json', data: Loggable.from(Data.json, collectionMaxLength: 2));
  log.d(
    '',
    data: const LoggableMultiData({'JSON': Data.json}, collectionMaxLength: 2),
  );
  log.d('', data: Loggable.from(Data.json, collectionMaxLength: 2));

  for (final l in LogLevels.values) {
    log[l].log(
      '',
      data: Loggable.from(Data.listOfLists, collectionMaxLength: 2),
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
    data: const LoggableMultiData({
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
      enumDotShorthand: false,
    ),
  );

  log.d('list', data: [1, 2, 3]);
  log.d(
    'wrapped list',
    data: Loggable.from(
      [1, 2, 3],
      collectionMaxLength: 2,
    ),
  );

  const notLoggableObject = NotLoggableObject('abc', [1, 2, 3]);
  Loggable.registerTypeConverter<NotLoggableObject>(
    NotLoggableObjectConverter(),
  );
  log.d('NotLoggableObject', data: notLoggableObject);

  // log.d('NotLoggableObject', data: notLoggableObject);
  // log.d(
  //   'NotLoggableObject',
  //   data: Loggable.builder(notLoggableObject)
  //     ..prop('name', notLoggableObject.name)
  //     ..prop('list', notLoggableObject.list),
  // );
  // Loggable.registerTypeConverter<NotLoggableObject>(
  //   ManualNotLoggableObjectConverter(),
  // );
  // log.d('NotLoggableObject', data: notLoggableObject);
  // Loggable.unregisterTypeConverter<NotLoggableObject>();
  // log.d('NotLoggableObject', data: notLoggableObject);

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
    data: Loggable.from(logStorage.snapshot(), collectionMaxLength: 3),
  );
}
