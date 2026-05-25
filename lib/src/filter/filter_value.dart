part of 'filter_exp.dart';

@immutable
sealed class FilterValue {
  const FilterValue();
}

sealed class _FilterValue<T extends Object?> extends FilterValue {
  final T value;

  const _FilterValue(this.value);

  @override
  int get hashCode => Object.hash(runtimeType.hashCode, value.hashCode);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is _FilterValue &&
          other.value == value;
}

final class FilterLevel extends _FilterValue<int> {
  const FilterLevel._(super.value);
}

final class FilterSingleLevel extends FilterLevel {
  const FilterSingleLevel._(super.value) : super._();

  static const FilterSingleLevel any = FilterSingleLevel._(-1);

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterSingleLevel ||
      other is FilterLevel && other.value == value;
}

final class FilterLogger extends _FilterValue<String> {
  const FilterLogger._(super.value);
}

final class FilterSingleLogger extends FilterLogger {
  const FilterSingleLogger._(super.value) : super._();

  static const FilterSingleLogger any = FilterSingleLogger._('');

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterSingleLogger ||
      other is FilterLogger && other.value == value;
}

final class FilterTraceId extends _FilterValue<String?> {
  const FilterTraceId._(super.value);
}

final class FilterTag extends _FilterValue<String> {
  const FilterTag._(super.value);
}
