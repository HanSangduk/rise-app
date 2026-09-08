import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'failure.dart';

/// 앱 전역 프로바이더 재시도 정책(P46).
///
/// **왜 기본값을 못 쓰나**: Riverpod 3의 기본 정책은 `Error`와 `ProviderException`만
/// 걸러내고 나머지는 전부 재시도한다(200ms부터 2배씩, 6.4초 상한, 10회 —
/// 지연만 합쳐 38초). 그런데 이 앱은 `home_view_model`처럼 **도메인 [Failure]를
/// 그대로 던져** 화면이 타입으로 분기한다. [Failure]는 `Error`가 아니라서 기본
/// 정책의 필터를 통과한다.
///
/// 그래서 "아직 회원권이 없어요"([EmptyPassesFailure])처럼 **다시 물어봐도 답이
/// 바뀌지 않는 확정 상태**를 10번 재시도했다. 홈 리포지토리는 한 번 빌드에 요청
/// 5개를 띄우므로 왕복 55번, 그동안 화면은 계속 스피너다 — 재시도 중에는
/// `AsyncError`가 아니라 `AsyncLoading(retrying: true)`이 흘러 `when(loading:)`이
/// 걸리기 때문이다(riverpod `element.dart` triggerRetry). 실기기에서 "회원권이
/// 없는데 로딩이 한참 돈다"로 드러났다.
///
/// **판단 기준은 "다시 시도하면 답이 달라질 수 있는가"**다:
/// - [NetworkFailure] — 달라질 수 있다(전파 지연·일시적 끊김). 단 **3회까지**만.
///   기본 10회는 1.4초면 될 일에 38초를 쓰고, 그동안 사용자는 원인을 못 본다.
/// - 그 밖의 [Failure] — 달라지지 않는다. 회원권 0개·거부·미연결·검증 실패는
///   서버가 이미 확정해 내려준 답이다. 즉시 화면에 넘긴다.
/// - [Failure]가 아닌 것(파싱 오류 등 예기치 못한 예외) — 기본 정책에 맡긴다.
Duration? appRetry(int retryCount, Object error) {
  if (error is Failure) {
    if (error is! NetworkFailure) return null;
    return ProviderContainer.defaultRetry(retryCount, error, maxRetries: 3);
  }
  return ProviderContainer.defaultRetry(retryCount, error);
}
