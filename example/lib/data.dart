import 'package:team_logger/team_logger.dart';

// ignore: avoid_classes_with_only_static_members
abstract final class Data {
  static const postUrl =
      '[b]POST[/b] https://test-api.tezapp.org/[b]clients/addresses[/b]';

  static const postHeaders = {
    'content-type': 'application/json',
    'accept': 'application/json',
    'the-timezone-iana': 'Asia/Almaty',
    'connection-type': 'wifi',
    'platform': 'android',
    'device-id': 'ef211e2c-29b8-4119-a4dd-d8c8b0c36324',
    'Device-Type': 'Samsung SM-A556E',
    'Device-OS-Version': '16',
    'App-Version': '1.8.25',
    'App-Build': '164',
    'authorization':
        'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxODc0MiwidXNlcl90eXBlIjoiY2xpZW50Iiwic2Vzc2lvbl9pZCI6MzUzNzN9.LWgB2NPJKf6rQ5nhxtq3Eecc2o5I5Es-9kfLLjdxIUQ',
    'accept-language': 'ru',
    'null': null,
    'false': false,
    'true': true,
    'int': 42,
    'double': 123.456,
    'record': (12, 'abc', true, null),
    'list': [1, 2, 3],
    'map': {'a': 1, 'b': 2, 'c': 3},
    'set': {1, 2, 3},
    'control-codes': 'abc\ndef\tghi\rjkl\bmno',
  };

  static const postBody = {
    'point': {'lon': '76.9456697', 'lat': '43.2308028'},
    'allow_outside_area': false,
  };

  static const succesResponse = [
    {
      'id': 1704,
      'name': 'Sweet sisters.kz, кондитерская',
      'type': 'work',
      'address': 'ул. Кабанбай батыра, 91',
      'address_ru': 'ул. Кабанбай батыра, 91',
      'address_kk': '',
      'points': [
        {'lat': '43.249473', 'lon': '76.939319'},
      ],
      'client_name': 'Кондитер',
    },
    {
      'id': 1706,
      'name': 'Continental, бассейн',
      'type': 'other',
      'address': 'пр. Сейфуллина, 404',
      'address_ru': 'пр. Сейфуллина, 404',
      'address_kk': '',
      'points': [
        {'lat': '43.267741', 'lon': '76.932179'},
      ],
      'client_name': 'Бассейн треня',
    },
    {
      'id': 1844,
      'name': '',
      'type': 'other',
      'address': 'улица Байтурсынова, 147а',
      'address_ru': 'улица Байтурсынова, 147а',
      'address_kk': 'Байтұрсынов көшесі, 147а',
      'points': [
        {'lat': '43.23288724409935', 'lon': '76.93205011077225'},
      ],
      'client_name': 'Salon',
    }
  ];

  static const errorResponse = {'code': 50000, 'error': 'Something went wrong'};

  static const loggableObject = LoggableObject(
    id: 1,
    duration: Duration(seconds: 143),
    bearing: 90,
    speed: 10,
    distance: 100,
    point: Point(43.250229, 76.926352),
    points: [
      Point(43.250229, 76.926352),
      Point(43.233664, 76.911589),
      Point(43.196249, 76.984717),
    ],
    destinations: {
      'a': [
        Point(43.250229, 76.926352),
        Point(43.233664, 76.911589),
        Point(43.196249, 76.984717),
      ],
      'b': [
        Point(43.250229, 76.926352),
        Point(43.233664, 76.911589),
        Point(43.196249, 76.984717),
      ],
    },
  );

  static const json = {
    'active_cities': [
      {
        'id': 12,
        'title': 'Актобе',
        'is_active': true,
        'center_point': {'lat': '0.000000', 'lon': '0.000000'},
        'city_polygon': [
          [
            [56.897667241460255],
            [50.2187685702103],
            [11.111111],
            [22.222222],
            [56.897667241460255],
          ],
          [
            [56.950893744325896],
            [50.182233885471334],
            [11.111111],
            [22.222222],
            [56.950893744325896],
          ],
          [
            [56.9918157263381],
            [50.20415823088945],
            [11.111111],
            [22.222222],
            [56.9918157263381],
          ],
          [
            [57.02535158229375],
            [50.186004802921815],
            [11.111111],
            [22.222222],
            [57.02535158229375],
          ],
          [
            [11.111111],
            [11.111111],
            [11.111111],
            [11.111111],
          ],
          [
            [22.222222],
            [22.222222],
            [22.222222],
            [22.222222],
          ],
          [
            [56.897667241460255],
            [50.2187685702103],
            [11.111111],
            [56.897667241460255],
          ],
        ],
      },
    ],
  };

  static const _list1 = [1, 2, 3];
  static const _list2 = [_list1, ..._list1];
  static const _list3 = [_list2, ..._list1];
  static const listOfLists = [_list3, ..._list1];
}

final class LoggableObject with Loggable {
  final int id;
  final Duration duration;
  final int bearing;
  final int speed;
  final int distance;
  final Point point;
  final List<Point> points;
  final Map<String, List<Point>> destinations;

  const LoggableObject({
    required this.id,
    required this.duration,
    required this.bearing,
    required this.speed,
    required this.distance,
    required this.point,
    required this.points,
    required this.destinations,
  });

  @override
  void collectLoggableData(LoggableData data) => data
    ..name = '$LoggableObject'
    ..prop('id', id)
    ..prop('point', point)
    ..prop(
      'duration',
      duration,
      view: LoggableMultiView([
        LoggableView(duration.inMinutes, 'min'),
        LoggableView(duration.inSeconds, 'sec'),
      ]),
    )
    ..prop('bearing', bearing, units: '°')
    ..prop(
      'speed',
      speed,
      units: 'm/s',
      view: LoggableMultiView([
        LoggableView(speed, 'm/s'),
        LoggableView(speed * 3.6, 'km/h'),
      ]),
    )
    ..prop('distance', distance, units: 'm')
    ..prop('points', points, collectionMaxLength: 2)
    ..prop('destinations', destinations);
}

final class Point with Loggable {
  final double lat;
  final double lon;

  const Point(this.lat, this.lon);

  @override
  void collectLoggableData(LoggableData data) => data
    ..name = 'Point'
    ..showName = false
    ..fixed('lat', lat, 5, showName: false)
    ..fixed('lon', lon, 5, showName: false);
}

final class NotLoggableObject {
  final String name;
  final List<int> list;

  const NotLoggableObject(this.name, this.list);

  @override
  String toString() => '$NotLoggableObject(name: $name, list: $list)';
}

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
