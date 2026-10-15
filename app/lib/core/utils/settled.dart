/// 성공/실패를 **값으로** 담는다 — 던지지 않는다.
///
/// 한 화면이 여러 요청을 **동시에** 띄울 때 쓴다(홈·마이·기록 탭). 중간에 빠져나가는 경로
/// (`EmptyPassesFailure`, 필수 조회 실패)가 있으면 남은 future가 나중에 실패했을 때 **아무도 받지
/// 않는 비동기 예외**가 되어 앱이 죽는다. 감싸 두면 에러가 값으로 잡히고, 원래 코드가 던지던
/// 자리에서 원래 순서대로 다시 던질 수 있다. 홈 탭에 있던 것을 공용으로 올렸다(P74 — 마이·기록
/// 탭이 같은 직렬 왕복 문제를 갖고 있었다).
class Settled<T> {
  const Settled(this.value, this.error, this.stack);
  final T? value;
  final Object? error;
  final StackTrace? stack;

  bool get failed => error != null;

  /// 실패면 그대로 다시 던진다 — **스택을 보존**해서 원인 추적이 끊기지 않게.
  T valueOrThrow() {
    if (error != null) Error.throwWithStackTrace(error!, stack ?? StackTrace.current);
    return value as T;
  }

  /// best-effort 호출용 — 실패하면 대체값.
  T valueOr(T fallback) => error != null ? fallback : value as T;
}

/// [f]의 결과를 [Settled]로 감싼다. 동기적으로 던지는 호출도 잡으려면 `settleCall(() => call())`처럼
/// 클로저로 넘기는 [settleCall]을 쓴다.
Future<Settled<T>> settle<T>(Future<T> f) async {
  try {
    return Settled(await f, null, null);
  } catch (e, st) {
    return Settled(null, e, st);
  }
}

/// 호출 자체가 동기적으로 던질 수 있을 때(데이터 소스가 인자 검증으로 throw하는 경우) — 클로저 안에서
/// 부른다.
Future<Settled<T>> settleCall<T>(Future<T> Function() call) async {
  try {
    return Settled(await call(), null, null);
  } catch (e, st) {
    return Settled(null, e, st);
  }
}

/// [items]마다 [call]을 **최대 [limit]개씩** 동시에 부르고, 결과를 입력 순서대로 [Settled]로 돌려준다
/// (던지지 않는다 — 하나의 실패가 나머지를 막지 않는다).
///
/// 개수가 회원 이력에 비례하는 조회용(마이 탭의 패스별 원장 — P74). 전부 한꺼번에 띄우면 오래 다닌
/// 회원일수록 연결·TLS 핸드셰이크가 그 수만큼 동시에 열린다(dart:io HttpClient는 호스트당 상한이 없다).
/// 서버의 `forEachParallel`(회원 8 · 패스 4)과 같은 이유의 상한이다.
Future<List<Settled<R>>> settleEach<T, R>(
  List<T> items,
  Future<R> Function(T item) call, {
  int limit = 4,
}) async {
  final out = List<Settled<R>?>.filled(items.length, null);
  var next = 0;
  // 이벤트 루프가 하나라 `next++`는 경합하지 않는다 — 각 일꾼이 다음 칸을 집어 끝까지 돈다.
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      out[i] = await settleCall(() => call(items[i]));
    }
  }

  final workers = limit < 1 ? 1 : (limit < items.length ? limit : items.length);
  await Future.wait([for (var w = 0; w < workers; w++) worker()]);
  return [for (final s in out) s!];
}
