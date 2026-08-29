import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/my/domain/my_models.dart' show PassHold;

/// 순수 도메인 — 예약. Flutter/외부 의존 0, codegen 0.

class SlotTeam {
  const SlotTeam({
    required this.bookingId,
    required this.trainerId,
    required this.memberId,
    required this.kind,
  });

  final String bookingId;
  final String trainerId;
  final String memberId;
  final String kind; // pt|group|ot
}

/// API계약_v1.md — Slot. slotKey "20260814-20" (YYYYMMDD-HH).
class Slot {
  const Slot({required this.slotKey, this.capacity = 3, this.teams = const []});

  final String slotKey;
  final int capacity;
  final List<SlotTeam> teams;

  DateTime get startAt => DateFmt.slotKeyToDateTime(slotKey);

  /// 점유율(n/cap)은 teams "길이" 기준 — v1.5 최소노출로 타인 팀의 member_id가
  /// 비어 있어도 팀 수는 그대로라 잔여 계산에 영향 없다.
  int get remaining => capacity - teams.length;
  bool get isFull => remaining <= 0;

  bool hasTrainer(String trainerId) => teams.any((t) => t.trainerId == trainerId);

  /// v1.5 최소노출: 타인 팀 member_id는 ""로 오므로, 비어있지 않은 내 memberId와는
  /// 항상 불일치 — "내 예약"(AlreadyBookedByMe) 판정에 오판 없음(본인 팀은 원문 유지).
  bool hasMember(String memberId) => teams.any((t) => t.memberId == memberId);
}

class MyBooking {
  const MyBooking({
    required this.id,
    required this.slotKey,
    required this.passId,
    required this.trainerId,
    this.trainerName,
    this.trainerInactive = false,
    required this.kind,
    required this.status,
    this.recurringId,
  });

  final String id;
  final String slotKey;

  /// 이 예약이 어느 회원권(패스)을 물고 있는가 — `Booking.pass_id`.
  ///
  /// **판정에 필요한 필드다.** 서버는 예약 생성 예산을
  /// `pass.Remaining − (이 패스의 살아있는 confirmed 예약 수)`로 계산한다
  /// (`CreateBooking` → `countOpenPassBookings`). 뺄셈의 오른쪽 항은 "이 패스의"
  /// 예약만 세므로, 예약 목록에서 패스를 구분하지 못하면 앱은 그 값을 재현할 수
  /// 없다. `GET /v1/bookings`는 회원 응답에서도 `pass_id`를 마스킹하지 않고
  /// 그대로 내려준다(ListBookings는 슬롯과 달리 최소노출 처리가 없다) —
  /// DTO는 예전부터 파싱하고 있었고 도메인 모델에서만 버려지고 있었다.
  ///
  /// [BookingRules.countOpenBookings]가 이 값을 읽는다.
  final String passId;
  final String trainerId;
  final String? trainerName;

  /// 담당 코치 퇴사 여부(계약 v2.0) — **이미 잡힌 예약의 이름은 계속 해석**하되
  /// (계약: inactive도 GET /v1/staff에 남는 이유), 필요 시 구분할 수 있게 들고 있는다.
  final bool trainerInactive;
  final String kind; // pt|group|ot
  final String status; // confirmed|waitlist|cancelled|noshow|completed
  final String? recurringId;

  DateTime get startAt => DateFmt.slotKeyToDateTime(slotKey);
  bool get isRecurring => recurringId != null;
  bool get isConfirmed => status == 'confirmed';
  bool get isWaitlist => status == 'waitlist';
}

/// 예약에 쓸 수 있는 내 패스 하나 — POST /v1/bookings는 트레이너를 직접 받지
/// 않고 pass_id로 결정한다(Pass.trainer_id). "전체 코치 보기"는 곧 "내 패스들
/// 중 어느 걸로 예약할지"와 같다.
class BookablePass {
  const BookablePass({
    required this.passId,
    required this.trainerId,
    this.trainerName,
    this.trainerInactive = false,
    this.trainerOffdays = const {},
    required this.product,
    required this.validFrom,
    required this.validUntil,
    required this.status,
    required this.remaining,
    required this.openBookings,
    this.holds = const [],
  });

  final String passId;
  final String trainerId;
  final String? trainerName;

  /// 담당 코치 퇴사 여부(계약 v2.0) — "내 회원권 전체" 보기의 코치 선택지에서
  /// 이 패스를 빼기 위한 플래그([isSelectable]). 계약상 active 패스가
  /// 남아 있으면 퇴사 처리가 막히므로 정상 흐름에선 항상 false다.
  final bool trainerInactive;

  /// 담당 코치의 휴무일(Staff.offdays, "YYYY-MM-DD" 집합).
  ///
  /// **계약상 회원도 받는 필드다** — `GET /v1/staff`(ListStaff)는 role=member
  /// 응답에서 payout만 비우고 offdays는 그대로 내려준다. 예전엔 "원장·트레이너
  /// 전용"이라 보고 파싱조차 하지 않아, 서버가 400("담당 코치의 휴무일이에요")으로
  /// 거부할 슬롯이 앱에선 정상 "예약 가능"으로 보였다.
  ///
  /// 문자열 그대로 들고 비교한다 — 백엔드도 슬롯 날짜를 "YYYY-MM-DD"로 찍어
  /// 문자열 목록과 대조하므로(`containsStr(st.Offdays, slotDate)`), 파싱 왕복
  /// 없이 같은 판정을 하고 깨진 값이 섞여도 예약을 막지 않는다.
  final Set<String> trainerOffdays;

  /// 실제 상품명(예: "PT 20회") — 예약 확정 시트 표기에 사용('PT' 하드코딩 대체).
  final String product;
  final DateTime validFrom;
  final DateTime validUntil;
  final String status; // active|scheduled|expired|refunded

  /// 남은 세션 수(원장 합산의 캐시 — 서버가 예약마다 재계산해 판정한다).
  ///
  /// **필수 인자인 이유**: 예전엔 이 필드가 아예 없었다. 홈이 이미 들고 있던 잔여를
  /// 예약 탭 모델로 옮기며 조용히 버렸고, 그래서 잔여 0인 회원권에도 살아 있는
  /// "예약" 버튼이 계속 떴다(서버는 100% 400 "잔여 세션이 없어요"). 기본값을 주면
  /// 같은 누락이 다시 조용히 통과한다.
  final int remaining;

  /// 이 패스로 **이미 잡아 둔** confirmed 예약 수 — 서버 `countOpenPassBookings`의 거울.
  ///
  /// **잔여와 별개의 값이다.** 잔여는 완료 시점에만 차감되므로(P4) 예약을 잡아도
  /// 줄지 않는다. 그래서 서버는 예약 생성 예산을 `remaining − openBookings`로 보고
  /// 0 이하면 400으로 거부한다(P13 H1 — 이 뺄셈이 없던 동안 잔여 2회 패스에 4건이
  /// 잡히고 4건이 완료돼 원장이 −2로 내려갔다). 같은 규칙이 `POST /v1/recurrings`에도
  /// 걸려 있다.
  ///
  /// **기본값을 주지 않는 이유는 [remaining]과 같다** — 이 값을 채우지 않으면
  /// `remaining − 0`이 되어 판정이 조용히 옛 규칙(잔여만 보기)으로 되돌아간다.
  ///
  /// 세는 범위는 서버와 같다: 상태가 `confirmed`인 건만, 이 패스의 것만, **지난
  /// 회차도 포함**(곧 완료 또는 노쇼로 차감될 청구권이다). 앱이 쓰는
  /// `GET /v1/bookings?member=`는 날짜 필터 없이 회원의 전 예약을 주므로
  /// 서버가 보는 목록(`ListBookingsByMember`)과 같은 모집단이다.
  final int openBookings;

  /// Pass.holds — 일시정지 구간(마이 탭 [PassHold] 재사용). 홀드 기간에 걸친
  /// 슬롯은 예약 불가로 사전 차단한다(BookingRules → PassOnHoldForSlot).
  final List<PassHold> holds;

  /// 서버가 예약을 받아주는 패스 상태인가 — 서버 `domain.Pass.BookableStatus()`와 같은 값.
  ///
  /// **active + scheduled 둘 다 통과한다.** 아직 시작 전인 재등록 회원권으로도
  /// 유효기간 안의 슬롯이면 선예약이 되어야 한다(v1.3 시간축: 판정 기준은 "오늘"이
  /// 아니라 "슬롯이 일어나는 날"). 날짜 적합성은 [NotYetValid]·[PassExpiredForSlot]이
  /// 슬롯별로 따로 보므로, 여기서 또 막으면 **서버는 받아주는 예약을 앱이 거부**한다.
  ///
  /// 종전 주석은 "active 하나뿐"이라고 적혀 있었고 그건 그때 사실이었다 — 백엔드가
  /// scheduled를 **한 번도 쓰지 않았기** 때문이다(CreatePass는 항상 active를 박았다).
  /// 서버가 상태를 유효기간에서 계산하기 시작하면서(P25) 그 전제가 깨졌다.
  ///
  /// expired·refunded는 여기서 걸러진다 — 화이트리스트라 모르는 상태도 막힌다.
  bool get isUsable => status == 'active' || status == 'scheduled';

  /// 잔여 세션이 남았는가 — 서버 판정(`pass.Remaining <= 0` → 400)과 같은 기준.
  ///
  /// 백엔드에 패스를 expired로 넘기는 코드가 없다(PassStatusExpired는 통계에서
  /// 읽기만 한다). 20회를 다 쓴 패스도 유효기간이 남는 한 영원히 active라
  /// 회원권 소진은 예외가 아니라 **모든 회원의 종착 상태**다.
  bool get hasRemaining => remaining > 0;

  /// 지금 이 패스로 **더 잡을 수 있는** 예약 수 — 서버의 `pass.Remaining - open`.
  ///
  /// 음수도 그대로 노출한다(잔여보다 예약이 많은 상태는 원장 정정·수기 예약으로
  /// 실제로 생길 수 있다). 판정은 [hasBookingBudget]이 서버와 같은 `<= 0`으로 한다.
  int get bookingBudget => remaining - openBookings;

  /// 새 예약을 한 건이라도 더 잡을 수 있는가 — 서버 판정(`Remaining-open <= 0` → 400)의 거울.
  bool get hasBookingBudget => bookingBudget > 0;

  /// 새 예약의 코치 선택지에 띄워도 되는 패스인가 — 쓸 수 있는 상태 + 잔여가
  /// 남아 있고 + 담당 코치가 현직일 것. 셋 중 하나라도 어긋나면 서버가 거부할
  /// 수업을 권하는 셈이라 선택지에서 뺀다(이미 잡힌 예약의 이름 해석은 그대로).
  ///
  /// **[hasBookingBudget]은 일부러 여기 넣지 않았다.** 잔여 0·환불·퇴사와 달리
  /// "잔여만큼 이미 잡아 둠"은 성실한 회원의 **정상 상태**다(잔여 10회를 10주치
  /// 고정으로 채운 회원이 곧 이 상태다). 여기서 걸러 버리면 "내 회원권 전체" 뷰의
  /// 패스 목록이 통째로 비고([_AllCoachSlotRow]의 `passes.isEmpty` 분기),
  /// 그 회원이 **이미 잡아 둔 자기 예약의 "확정" 배지까지 사라진다** — 예약을 다
  /// 잡았다는 이유로 예약이 안 보이는 화면이 된다. 대신 목록에 남겨 두고
  /// [AllRemainingBooked] 상태로 "이 회원권은 다 잡았다"고 태그가 말하게 한다.
  bool get isSelectable => isUsable && hasRemaining && !trainerInactive;

  /// 실제로 새 예약을 **만들 수 있는** 패스인가 — 선택지 조건 + 예약 예산.
  ///
  /// [isSelectable]과 갈라 두는 이유는 위 주석대로 "목록에 띄울 것인가"와
  /// "지금 새로 잡을 수 있는가"가 다른 질문이기 때문이다. 다음 행동을 안내하는
  /// 자리("다른 회원권으로 예약해주세요")는 반드시 이쪽을 봐야 한다 — 예산이 0인
  /// 패스를 권하면 회원은 안내대로 옮겨 가서 또 거부당한다.
  bool get canBookNew => isSelectable && hasBookingBudget;

  /// [day]가 담당 코치의 휴무일인가(날짜 단위).
  bool isTrainerOffday(DateTime day) => trainerOffdays.contains(DateFmt.isoDate(day));
}

/// 예약 탭 화면 데이터 묶음.
class BookingScreenData {
  const BookingScreenData({
    required this.selectedDate,
    required this.slots,
    required this.myBookings,
    required this.myPasses,
    required this.primaryPassId,
  });

  final DateTime selectedDate;
  final List<Slot> slots;
  final List<MyBooking> myBookings;

  /// 내가 가진 모든 예약 가능 패스("전체 코치 보기"에서 순회).
  final List<BookablePass> myPasses;

  /// "내 코치" 필터 기준 = 홈에서 선택된 패스(디폴트).
  final String primaryPassId;

  BookablePass get primaryPass =>
      myPasses.firstWhere((p) => p.passId == primaryPassId, orElse: () => myPasses.first);

  /// 이 화면이 아는 코치의 퇴사 여부 — 내 패스 중 그 코치의 것이 있으면 그 플래그,
  /// 없으면 null("모른다").
  ///
  /// 화면 안에서 "퇴사 여부"의 **단일 출처**다. 같은 사실을 repository가 매번 새로
  /// 만드는 이 플래그와 15분 TTL 스태프 캐시 두 곳에서 읽던 탓에, 칩은 "(퇴사)"인데
  /// 아바타는 총천연색이고 프로필 시트는 퇴사를 설명하지 못하는 모순이 났다.
  /// (판단 근거는 booking_screen의 `_withDomainStatus` 주석.)
  bool? trainerInactiveOf(String trainerId) {
    for (final p in myPasses) {
      if (p.trainerId == trainerId) return p.trainerInactive;
    }
    return null;
  }
}
