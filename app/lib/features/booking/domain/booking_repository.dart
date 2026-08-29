import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';

abstract interface class BookingRepository {
  /// GET /v1/slots?date= (해당 날짜의 전체 슬롯·팀 현황).
  Future<Result<List<Slot>>> loadSlots(DateTime date);

  /// 내 예약 목록(⚠️ GET 갭 — bookings_api.dart 참고).
  Future<Result<List<MyBooking>>> loadMyBookings(String memberId);

  /// POST /v1/bookings {slot_key, member_id, pass_id} — 트랜잭션(P35): 용량3 +
  /// 트레이너동시1 + 회원동시1 + **잔여 − 이미 잡힌 confirmed 예약 > 0**.
  ///
  /// 마지막 항이 P13 H1으로 추가됐다. 잔여는 완료 시점에만 차감되므로(P4) 예약을
  /// 잡아도 줄지 않아, `remaining > 0`이어도 400으로 거부된다("이미 잡힌 예약 N건이
  /// 잔여 M회를 채웠어요"). 앱은 [BookingRules.evaluate]가 같은 순서·같은 식으로
  /// 미리 판정한다([AllRemainingBooked]).
  ///
  /// **만석이면 409로 거부된다** — 자동 대기(waitlist) 승격은 없다.
  /// `backend/internal/domain/booking.go`의 `CanBook`은 `ErrSlotFull`만 반환하고
  /// 백엔드에 waitlist 생성 경로 자체가 없다(`Booking.status="waitlist"`는 예약어로만
  /// 남겨 둔 값 — 알림 인프라 없는 자동 승격은 노쇼 함정이라 v1에서 뺐다).
  /// UI도 만석을 비활성 칩으로만 표시한다(slot_list.dart).
  Future<Result<void>> book({
    required String slotKey,
    required String memberId,
    required String passId,
  });

  /// DELETE /v1/bookings/{id} — 24시간 컷오프는 서버가 최종 검사.
  Future<Result<void>> cancel(String bookingId);

  /// POST /v1/recurrings {member_id, trainer_id, pass_id, days, hour, until} (P47).
  ///
  /// ⚠️ 회원 앱에서 호출부가 없고, 있어도 서버가 막는다 — `api/service.go`의
  /// `CreateRecurring`/`DeleteRecurring`은 `p.IsMember()`면 즉시 403이다
  /// (고정 스케줄은 데스크·트레이너가 잡는다. 앱은 `MyBooking.isRecurring`으로
  /// "고정" 배지를 읽기만 한다). 제거 여부는 data 계층과 함께 판단해야 해 남겨 둔다.
  ///
  /// 서버는 여기에도 [book]과 **같은 예약 예산 규칙**을 건다(P12 H4 → P13 H1: 선행
  /// 생성 수를 `잔여 − 이미 잡힌 confirmed`로 캡핑하고, 예산이 0이면 규칙 생성 자체를
  /// 거부한다). 회원 앱에 생성 경로가 열리면 [BookingRules.evaluate]와 같은 판정을
  /// 여기에도 미러해야 한다 — 지금은 403으로 막혀 사전 판정할 자리가 없다.
  /// 반대 방향은 이미 반영돼 있다: 고정 스케줄이 만든 예약도 confirmed라
  /// [MyBooking]으로 내려오고 [BookingRules.countOpenBookings]가 그대로 센다
  /// (10주치 고정이 걸린 회원이 곧 예산 소진 상태의 전형이다).
  Future<Result<void>> createRecurring({
    required String memberId,
    required String trainerId,
    required String passId,
    required List<String> days,
    required int hour,
    DateTime? until,
  });

  /// DELETE /v1/recurrings/{id} — 고정 스케줄 자체 해제(개별 회차 취소는 [cancel]).
  Future<Result<void>> deleteRecurring(String recurringId);
}
