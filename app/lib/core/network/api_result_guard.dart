import 'package:dio/dio.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';

/// data 레이어 공용 헬퍼 — dio 예외를 [Failure]로 매핑해 [Result]로 감싼다.
/// 모든 RemoteDataSource 호출은 repository 구현체에서 이 함수를 통과시킨다.
Future<Result<T>> guardApi<T>(Future<T> Function() call) async {
  try {
    return Ok(await call());
  } on DioException catch (e) {
    final status = e.response?.statusCode;
    // 백엔드 공통 에러 포맷: {"error":"메시지"} (API계약_v1.md).
    // 값이 문자열이 아닐 수도 있어 toString으로 견고화.
    final serverMessage = e.response?.data is Map
        ? ((e.response?.data as Map)['error'])?.toString()
        : null;

    // 401은 **다른 종류의 실패**다: 규칙에 걸린 게 아니라 신원이 없어진 것이다.
    // 종전엔 400대를 전부 RejectedFailure로 뭉개서, 세션이 죽으면 회원이 모든 화면에서
    // "요청을 처리할 수 없어요"만 보고 **로그인으로 돌아갈 길을 안내받지 못했다**.
    //
    // 403은 여기 넣지 않는다 — 403은 신원은 멀쩡한데 권한이 없다는 뜻이고(탈퇴 회원·
    // 담당 아닌 코치), 그걸로 로그아웃시키면 정상 거절이 세션 종료로 번진다.
    if (status == 401) {
      return Err(AuthFailure(serverMessage ?? '로그인이 만료됐어요 — 다시 로그인해주세요'));
    }
    // 409 + `code: join_pending`(계약 v2.34) — "이미 보낸 요청이 있다"는 서버의 pending 확답이다.
    // `code`로만 가른다(문구 매칭은 서버가 문장을 다듬는 순간 조용히 깨진다). 구서버는 `code`가
    // 없어 아래 RejectedFailure로 떨어진다 — 종전 동작(시트 안 빨간 문구) 그대로.
    if (status == 409 && e.response?.data is Map) {
      final body = e.response!.data as Map;
      if (body['code'] == 'join_pending') {
        return Err(JoinPendingFailure(
          message: serverMessage ?? '이미 보낸 가입 요청이 있어요 — 센터에서 확인하면 연결돼요',
          centerId: body['center_id']?.toString() ?? '',
        ));
      }
    }
    if (status != null && status >= 400 && status < 500) {
      return Err(RejectedFailure(serverMessage ?? '요청을 처리할 수 없어요'));
    }
    return Err(NetworkFailure(serverMessage ?? '연결이 불안정해요'));
  } on Failure catch (f) {
    // repo/데이터 소스가 이미 도메인 Failure로 분류해 던진 경우 그대로 통과
    // (예: EmptyPassesFailure — 홈 탭이 타입으로 빈 상태 뷰를 구분).
    return Err(f);
  } on StateError catch (e) {
    // 데이터 소스가 의도적으로 던지는 표시용 메시지("발급된 회원권이 없어요" 등)
    // — 삼키지 않고 그대로 사용자에게 전달한다.
    return Err(RejectedFailure(e.message));
  } catch (_) {
    return const Err(UnknownFailure());
  }
}
