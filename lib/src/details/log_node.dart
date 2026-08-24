import 'package:team_logger/team_logger.dart';

/// What a node's label means.
enum LogNodeKind {
  /// The `data` of the log itself.
  root,

  /// A property of a `Loggable` or a `LoggableData`.
  prop,

  /// A section of a `LoggableMultiData`.
  section,

  /// An element of a `List` or a `Set`.
  ///
  /// Not `index`: `Enum` already declares `int index`.
  element,

  /// An entry of a `Map`.
  entry,
}

/// The value every computed property carries.
///
/// `team_logger` exposes no flag for a computed property, but all of them
/// share a single const instance. This probe captures that instance through
/// the public API, so `identical` recognizes any computed property exactly.
///
/// Should `team_logger` ever stop sharing one instance, computed properties
/// merely lose their badge — nothing breaks.
final Object? computedMarker =
    (Loggable.mapBuilder()..computed('probe', 0)).props.first.value;

/// One row of the log data tree.
final class LogNode {
  final LogNodeKind kind;

  /// Property name, section key, element index or the key object of a map
  /// entry. Rendered later, when a theme is at hand.
  final Object? label;

  final bool showName;

  /// The real value behind the node.
  final Object? value;

  /// What the log prints instead of [value], or `Prop.noView`.
  final Object? view;

  final bool hidden;
  final LoggableConfig config;
  final int depth;

  /// Identity of the node, used to remember what the user expanded.
  ///
  /// Built from positions rather than values: equal values sitting on
  /// different branches must not expand together.
  final String path;

  const LogNode({
    required this.kind,
    required this.label,
    required this.value,
    required this.path,
    this.showName = true,
    this.view = Prop.noView,
    this.hidden = false,
    this.config = const LoggableConfig(),
    this.depth = 0,
  });

  /// The root node of a log's data.
  factory LogNode.root(Object? data) => LogNode(
        kind: LogNodeKind.root,
        label: null,
        value: data,
        path: '',
      );

  bool get computed => identical(value, computedMarker);

  /// The value the given mode renders and expands.
  ///
  /// In log mode that is the view when one is set, because that is what the
  /// log actually prints; in real mode it is always the value itself.
  Object? target({required bool real}) =>
      real || view is LoggableNoView ? value : view;

  bool expandable({required bool real}) => _expandable(target(real: real));

  /// Children of the node, empty when it cannot be expanded.
  List<LogNode> children({required bool real}) =>
      _children(target(real: real), config, depth + 1, path, real: real) ??
      const [];

  static bool _expandable(Object? target) => switch (target) {
        final LoggableWrapper wrapper => _expandable(wrapper.data),
        Loggable() ||
        LoggableData() ||
        LoggableMultiData() ||
        Map<Object?, Object?>() ||
        List<Object?>() ||
        Set<Object?>() =>
          true,
        _ => false,
      };

  /// Only `List` and `Set` are walked, not every `Iterable`: a lazy one may
  /// be endless, and enumerating it for the tree would materialize it.
  static List<LogNode>? _children(
    Object? target,
    LoggableConfig config,
    int depth,
    String parentPath, {
    required bool real,
  }) =>
      switch (target) {
        final LoggableWrapper wrapper => _children(
            wrapper.data,
            wrapper.config.merge(config),
            depth,
            parentPath,
            real: real,
          ),
        final Loggable loggable => _props(
            loggable.logClassInfo(),
            config,
            depth,
            parentPath,
            real: real,
          ),
        final LoggableData data =>
          _props(data, config, depth, parentPath, real: real),
        final LoggableMultiData data => [
            for (final entry in data.data.entries)
              LogNode(
                kind: LogNodeKind.section,
                label: entry.key,
                value: entry.value,
                config: data.config.merge(config),
                depth: depth,
                path: '$parentPath/${entry.key}',
              ),
          ],
        final Map<Object?, Object?> map => [
            for (final (index, entry) in map.entries.indexed)
              LogNode(
                kind: LogNodeKind.entry,
                label: entry.key,
                value: entry.value,
                config: config,
                depth: depth,
                path: '$parentPath/[$index]',
              ),
          ],
        final List<Object?> list => _elements(list, config, depth, parentPath),
        final Set<Object?> set => _elements(set, config, depth, parentPath),
        _ => null,
      };

  static List<LogNode> _elements(
    Iterable<Object?> items,
    LoggableConfig config,
    int depth,
    String parentPath,
  ) =>
      [
        for (final (index, item) in items.indexed)
          LogNode(
            kind: LogNodeKind.element,
            label: index,
            value: item,
            config: config,
            depth: depth,
            path: '$parentPath/[$index]',
          ),
      ];

  static List<LogNode> _props(
    LoggableData data,
    LoggableConfig config,
    int depth,
    String parentPath, {
    required bool real,
  }) =>
      [
        for (final prop in data.props)
          if (real || !prop.hidden)
            LogNode(
              kind: LogNodeKind.prop,
              label: prop.name,
              showName: prop.showName,
              value: prop.value,
              view: prop.view,
              hidden: prop.hidden,
              config: prop.config.merge(config),
              depth: depth,
              path: '$parentPath/${prop.name}',
            ),
      ];
}
