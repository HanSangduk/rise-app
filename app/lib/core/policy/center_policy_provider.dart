import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/center_api.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/session/session_provider.dart';

part 'center_policy_provider.g.dart';

/// 센터 운영 정책 — 세션 로드 후 조회해 성공 시에만 캐시([ref.keepAlive]).
/// 실패해도 절대 throw하지 않고 [CenterPolicy.fallback](24h/2회/30일)으로 폴백한다
/// — 정책 표시가 홈/예약/마이 탭 로드를 막으면 안 되기 때문(최종 검증은 서버).
///
/// keepAlive를 무조건 걸지 않는 이유(P03 보완):
/// 1) 실패 폴백이 앱 세션 내내 keepAlive 캐시에 눌러앉으면 이후 모든 화면이
///    기본값(24h)만 보게 된다 — 성공 시에만 keepAlive, 실패하면 autoDispose로
///    남겨 다음 구독/새로고침 때 재시도한다.
/// 2) 정책은 대표가 언제든 바꾼다. 예: 대표가 취소 컷오프를 축소(24h→6h)한 뒤에도
///    앱이 로그인 시점 정책을 붙들고 있으면, 회원은 취소 가능한 예약에서 취소 버튼을
///    못 보거나(버튼 미노출) 서버가 거부하는 버튼을 계속 누르는 사일런트 데드엔드에
///    빠진다 — 그래서 각 탭 새로고침 경로가 이 provider를 invalidate해 재로그인
///    없이도 최신 정책이 반영되게 한다.
@riverpod
Future<CenterPolicy> centerPolicy(Ref ref) async {
  // 로그인 전엔 호출하지 않는다(401/403 소음 방지) — 세션이 생기면 재빌드되어 조회.
  final session = ref.watch(sessionProvider);
  if (session == null) return CenterPolicy.fallback;

  try {
    final dto = await ref.watch(centerApiProvider).fetchCenter();
    final p = dto.policy;
    // 성공했을 때만 캐시 유지 — 실패 폴백은 캐시에 남기지 않는다(다음 구독 때 재시도).
    ref.keepAlive();
    return CenterPolicy(
      slotCapacity: p.slotCapacity,
      cancelCutoffHours: p.cancelCutoffHours,
      graceOnce: p.graceOnce,
      penaltyRate: p.penaltyRate,
      expiringDays: p.expiringDays,
      maxHoldsPerPass: p.maxHoldsPerPass,
      maxHoldTotalDays: p.maxHoldTotalDays,
    );
  } catch (_) {
    return CenterPolicy.fallback;
  }
}
