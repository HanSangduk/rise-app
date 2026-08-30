import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rise_member/core/api/dto/consult_request_dto.dart';
import 'package:rise_member/core/network/dio_client.dart';
import 'package:rise_member/features/consult/data/consult_api.dart';

part 'consult_providers.g.dart';

@riverpod
ConsultApi consultApi(Ref ref) => ConsultApi(ref.watch(dioProvider));

/// 재시도 안 함 — CTA는 조회 실패 시 버튼을 그대로 보여주는 fail-open 설계라(중복은
/// 서버 409가 최종선) 백그라운드 재시도가 고칠 것이 없고, 기본 재시도(backoff)의
/// 타이머가 위젯 테스트에서 "Timer still pending"으로 샌다.
Duration? _noRetry(int retryCount, Object error) => null;

/// 내 재등록/상담 요청 목록 — CTA가 "요청 보냈어요" 상태를 세션·재실행을 넘어 복원하는
/// 유일한 출처다(로컬 플래그로 들면 앱 재설치·기기 변경에서 거짓말이 된다).
///
/// keepAlive를 걸지 않는다 — 이 값을 보는 화면은 CTA가 뜬 홈/예약뿐이고, 요청 전송
/// 직후 invalidate로 즉시 갱신되므로 짧은 생명주기가 맞다(staffMap처럼 앱 전역에서
/// 이름 해석에 쓰이는 캐시가 아니다).
@Riverpod(retry: _noRetry)
Future<List<ConsultRequestDto>> myConsultRequests(Ref ref) {
  return ref.watch(consultApiProvider).fetchMine();
}
