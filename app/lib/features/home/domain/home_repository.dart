import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

abstract interface class HomeRepository {
  /// GET /v1/me(세션에서 이미 보유) + 패스 목록 + 다음 예약 + 오늘 Home Work.
  /// [preferredPassId]를 주면 그 패스를 선택 상태로 두고 예약/Home Work를
  /// 그 패스의 담당 코치 기준으로 계산한다(패스 스위처 칩 전환용).
  ///
  /// 예전엔 `cancelCutoffHours`(센터 정책 실값)도 받아 다음 예약의 무료 취소 여부를
  /// 여기서 bool로 계산해 담았다. 그 값이 로드 시점에 굳는 게 P51 결함이라
  /// ([NextBooking] 클래스 주석) 판정을 화면의 파생 계산으로 옮겼고, 정책값은
  /// 화면이 [centerPolicyProvider]에서 직접 읽는다 — repository는 더 이상
  /// 시각 의존 판정을 스냅샷에 담지 않는다.
  Future<Result<HomeSummary>> loadHome({
    required String memberId,
    String? preferredPassId,
  });

  /// 체크박스 토글 → POST /v1/hw-checks {hw_id, date, done:[...]} (전체 배열 전송).
  Future<Result<void>> submitHomeworkChecks({
    required String memberId,
    required String hwId,
    required DateTime date,
    required List<bool> done,
  });

  /// 셀프 체크인 → POST /v1/checkin {source:"self_qr", qr_token}
  /// (서버가 ±30분 시간창 내 내 예약을 스스로 찾는다, P44).
  ///
  /// [scannedToken] = 데스크 QR에서 읽은 원문(1순위). null이면 dev 폴백 상수를 쓴다
  /// — 상세 근거는 [HomeRemoteDataSource.selfCheckIn] 주석.
  Future<Result<void>> selfCheckIn({String? scannedToken});
}
