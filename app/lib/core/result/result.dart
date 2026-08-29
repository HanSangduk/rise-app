import 'package:rise_member/core/result/failure.dart';

/// 성공/실패를 값으로 표현 (Dart 3 sealed). wodshot과 동일한 패턴.
///
/// ```dart
/// switch (result) {
///   case Ok(:final value): use(value);
///   case Err(:final failure): show(failure.message);
/// }
/// ```
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  /// 성공이면 값, 실패면 null.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// 변환 (성공 값만 매핑, 실패는 전파).
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Ok(transform(value)),
        Err<T>(:final failure) => Err(failure),
      };

  R fold<R>(
    R Function(T value) onOk,
    R Function(Failure failure) onErr,
  ) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}
