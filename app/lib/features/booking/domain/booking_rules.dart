import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/my/domain/my_models.dart' show PassHold;

/// 슬롯 하나를 "지금 이 회원이 이 트레이너로" 예약하려 할 때의 UI 상태.
/// 목업 예약 탭의 배지들과 1:1 대응: 잔여 n/3 · 코치 수업중 · 3/3 만석 ·
/// 확정(내 예약) · 9/1부터(패스 유효기간 전).
sealed class SlotBookState {
  const SlotBookState();
}

/// 예약 가능 — "잔여 n/3팀".
final class Bookable extends SlotBookState {
  const Bookable(this.remaining, this.capacity);
  final int remaining;
  final int capacity;
}

/// 이 슬롯에 같은 트레이너가 이미 다른 팀을 맡고 있음(트레이너 동시 1) — "코치 수업중".
final class CoachBusy extends SlotBookState {
  const CoachBusy();
}

/// 용량 3 전부 참(다른 트레이너 포함) — "3/3 만석" → 대기 신청 가능.
final class SlotFull extends SlotBookState {
  const SlotFull();
}

/// 이미 내가 이 슬롯에 예약해둔 상태 — "확정 ✓".
final class AlreadyBookedByMe extends SlotBookState {
  const AlreadyBookedByMe();
}

/// 슬롯 날짜가 선택한 패스의 유효기간(valid_from) 시작 전 — 예: "9/1부터".
final class NotYetValid extends SlotBookState {
  const NotYetValid(this.validFrom);
  final DateTime validFrom;
}

/// 슬롯 날짜가 선택한 패스의 유효기간(valid_until)을 지남 — 예약 불가.
final class PassExpiredForSlot extends SlotBookState {
  const PassExpiredForSlot(this.validUntil);
  final DateTime validUntil;
}

/// 슬롯 날짜가 패스의 일시정지(홀드) 구간 안 — 예약 불가("일시정지 중").
/// 서버도 홀드 기간 예약을 거부하므로 UI에서 미리 차단해 헛클릭을 막는다.
final class PassOnHoldForSlot extends SlotBookState {
  const PassOnHoldForSlot(this.hold);
  final PassHold hold;
}

/// 패스 상태가 예약을 받을 수 없는 값 — 서버 400
/// "이용 가능한 상태의 패스가 아니에요(환불·만료 처리됨)".
/// [BookablePass.isUsable] 참조(active·scheduled 통과 — 서버 BookableStatus와 같다).
final class PassNotUsable extends SlotBookState {
  const PassNotUsable(this.status);

  /// 원본 status(expired|refunded|scheduled|…) — 라벨을 그에 맞게 고르기 위해.
  final String status;
}

/// 잔여 세션 0 — 서버 400 "잔여 세션이 없어요".
///
/// 회원권 소진은 예외가 아니라 모든 회원의 종착 상태다(백엔드에 패스를 expired로
/// 넘기는 코드가 없어, 다 쓴 패스도 유효기간이 남는 한 계속 active로 온다).
/// 그래서 이 상태는 "언젠가의 엣지케이스"가 아니라 정상 수명의 마지막 화면이다.
final class NoRemainingSessions extends SlotBookState {
  const NoRemainingSessions();
}

/// 잔여는 남았는데 **이미 잡아 둔 예약이 그 잔여를 전부 물고 있음** — 서버 400
/// "이미 잡힌 예약 N건이 잔여 M회를 채웠어요 — 기존 예약을 정리하거나 회차를
/// 추가해주세요"(P13 H1, `domain.ErrNoSessionsLeft`와 같은 규칙).
///
/// **[NoRemainingSessions]와 뭉치면 안 된다.** 두 상태는 회원이 할 일이 정반대다:
///  · 잔여 0 = 실제 소진 → 재등록(센터 문의) 말고는 방법이 없다.
///  · 이 상태 = 회차는 남았고 자리만 미리 다 잡아 둔 것 → **기존 예약을 하나
///    취소하면 즉시 다시 잡을 수 있다.** 여기에 "재등록해주세요"라고 안내하면
///    이미 가진 회차를 두고 돈을 더 내라는 말이 된다.
///
/// 잔여는 완료 시점에만 차감되므로(P4) 예약을 잡아도 잔여 숫자는 그대로다 —
/// 회원 눈에는 "잔여 2회인데 예약이 안 된다"로 보인다. 그래서 문구는 반드시
/// 두 숫자를 함께 말해야 한다([remaining]회 중 [openBookings]건이 잡혀 있음).
final class AllRemainingBooked extends SlotBookState {
  const AllRemainingBooked(this.remaining, this.openBookings);

  /// 원장 합(= 아직 차감되지 않은 남은 회차).
  final int remaining;

  /// 그 회차를 물고 있는 confirmed 예약 수.
  final int openBookings;
}

/// 슬롯 날짜가 담당 코치의 휴무일 — 서버 400 "담당 코치의 휴무일이에요"
/// (v1.4에서 recurring 선행 생성뿐 아니라 일반 예약까지 확장됐다).
final class TrainerOffday extends SlotBookState {
  const TrainerOffday();
}

/// 순수 함수 — API계약_v1.md P35 트랜잭션 규칙(용량3 + 트레이너동시1 + 잔여>0)을
/// UI 상태로 미리 판정해 버튼 라벨/활성화를 결정한다. 실제 예약은 서버가 최종 검증.
///
/// 유효기간 판정은 "슬롯의 날짜" 기준(현재 시각 아님) — 슬롯 날짜가
/// [validFrom, validUntil] 밖이면 예약 불가(백엔드도 같은 규칙).
abstract final class BookingRules {
  /// 빈 시간대 합성(P04 HIGH — 예약 여정 단절 해소): GET /v1/slots는 "예약이 있던
  /// 시간대"만 주므로, 아무도 예약 안 한 날짜는 목록이 텅 빈다("열린 슬롯이 없어요").
  /// 운영시간의 빈 슬롯(capacity = 센터 정책 slot_capacity, teams=[])을
  /// 만들어 서버 슬롯과 slot_key 기준으로 병합한다 — 같은 키는 항상 서버 우선
  /// (합성이 실제 예약·용량을 덮어쓰면 안 된다). 운영시간 밖의 서버 슬롯(관리자
  /// 수기 등록 등)도 버리지 않고 그대로 포함한다(어드민 Schedule 합성과 동일 원리).
  /// 지난 시각 처리(오늘의 지난 시간대 "지남" 칩)는 기존 UI 로직이 그대로 담당.
  ///
  /// ## [openHour]·[closeHour]는 **슬롯 시작 시각, 양끝 포함**이다
  ///
  /// 9·21이면 09시 시작부터 21시 시작까지 **13칸**이고 마지막 수업은 21:00에 시작한다
  /// (`h <= closeHour`). 이 경계에서 하나만 틀려도 센터의 영업 한 시간이 사라지거나
  /// (`h < closeHour` → 21시 수업이 목록에서 통째로 증발) 없는 한 시간이 생긴다
  /// (`h <= closeHour + 1` → 22시에 예약 버튼이 뜨고 서버가 거부한다).
  /// `booking_rules_test`가 첫/마지막 slot_key를 직접 단언해 이 경계를 못박는다.
  ///
  /// ## 값은 **주입받는다** — 여기서 정책을 읽지 않는다
  ///
  /// 예전엔 이 클래스가 `openHour = 9` / `closeHour = 21`을 상수로 들고 있었다.
  /// 06시에 열거나 23시에 닫는 센터는 그 시간대를 앱에서 **표현할 방법 자체가
  /// 없었고**, 회원은 실제로 영업 중인 시간을 예약할 수 없었다.
  /// 지금은 `GET /v1/center`의 `policy.open_hour`/`close_hour`가 진실이고,
  /// 이 파일은 규칙 파일의 규약대로 값을 받기만 한다(정책을 읽는 경계는
  /// `core/policy/center_policy_provider.dart` — 구버전 서버의 기본값 9·21도
  /// 거기서 `CenterPolicy.resolveHours`가 정한다).
  static List<Slot> mergeWithOpenHours({
    required DateTime date,
    required List<Slot> serverSlots,
    required int capacity,
    required int openHour,
    required int closeHour,
  }) {
    final byKey = {for (final s in serverSlots) s.slotKey: s};
    final keys = <String>{
      for (var h = openHour; h <= closeHour; h++) DateFmt.toSlotKey(date, h),
      ...byKey.keys,
    };
    // slotKey는 "YYYYMMDD-HH"(HH 제로패딩)라 문자열 정렬 == 시간순.
    final sorted = keys.toList()..sort();
    return [
      for (final key in sorted) byKey[key] ?? Slot(slotKey: key, capacity: capacity),
    ];
  }

  /// 이 패스로 **이미 잡아 둔** confirmed 예약 수 — 서버 `countOpenPassBookings`의 거울.
  ///
  /// 서버 구현과 같은 세 가지 규칙을 지킨다(`service.go`):
  ///  1. `b.PassID == passID` — 예약은 패스 단위로 잔여를 문다. 회원의 다른 패스
  ///     예약은 이 패스의 예산과 무관하다(코치도 유효기간도 다르다).
  ///  2. `b.Status == confirmed` — 완료·노쇼는 **이미 원장에서 차감된** 회차라 다시
  ///     세면 이중 차감이 되고, 취소는 청구권을 되돌려준 건이다. confirmed만 센다.
  ///  3. 날짜 필터 없음 — **지난 회차의 confirmed도 센다**(곧 완료 또는 노쇼로
  ///     차감될 예정이다). 앱의 `GET /v1/bookings?member=`도 `from` 없이 부르므로
  ///     서버의 `ListBookingsByMember`와 같은 모집단이다. 여기서 "다가오는 예약만"
  ///     세면 앱만 예산을 넉넉히 보고 서버가 거부한다.
  static int countOpenBookings(Iterable<MyBooking> bookings, String passId) {
    var n = 0;
    for (final b in bookings) {
      if (b.passId == passId && b.isConfirmed) n++;
    }
    return n;
  }

  /// 이 슬롯을 [pass]로 예약할 수 있는가.
  ///
  /// **패스 전체를 통째로 받는다** — 예전엔 유효기간·홀드만 개별 인자로 받았고,
  /// 그래서 잔여(remaining)처럼 서버가 반드시 검사하는 값이 판정에서 통째로 빠져
  /// 있어도 컴파일이 통과했다. 서버 계약이 늘어나면(휴무일 v1.4 등) 여기에 인자를
  /// 하나 더 붙이는 대신 [BookablePass]에 필드를 추가하고 이 함수가 읽게 한다.
  ///
  /// **판정 순서는 `CreateBooking`의 거부 순서를 그대로 따른다** — 앱이 먼저 말하는
  /// 이유와 서버가 먼저 거부할 이유가 어긋나면, 두 제약이 겹칠 때 앱이 엉뚱한 이유를
  /// 안내하게 된다(status → 잔여 → **예약 예산** → 유효기간 → 홀딩 → 휴무일 →
  /// 슬롯 사정).
  /// 다만 [AlreadyBookedByMe]는 "새 예약 가능 여부"가 아니라 이미 확정된 사실이라
  /// 언제나 맨 앞이다.
  static SlotBookState evaluate({
    required Slot slot,
    required BookablePass pass,
    required String myMemberId,
  }) {
    // v1.5 최소노출: member 응답에서 타인 팀의 member_id는 ""로 온다 — 내 memberId는
    // 빈 문자열이 아니므로 "" == 내 id 불일치로 오판이 없고, isNotEmpty 가드는 혹시
    // 빈 myMemberId가 들어와도(비로그인 방어) ""팀과 매칭돼 가짜 "확정"이 뜨는 걸 막는다.
    if (myMemberId.isNotEmpty && slot.hasMember(myMemberId)) {
      return const AlreadyBookedByMe();
    }
    if (!pass.isUsable) {
      return PassNotUsable(pass.status);
    }
    if (!pass.hasRemaining) {
      return const NoRemainingSessions();
    }
    // 예약 예산 = 잔여 − 이미 잡아 둔 confirmed 예약(P13 H1). 서버는 이 판정을
    // **잔여 0 바로 다음, 유효기간 검사 앞**에서 한다(`CreateBooking`) — 순서를
    // 옮기면 예산도 없고 기간도 지난 슬롯에서 앱은 "8/10까지"라 하고 서버는
    // "이미 잡힌 예약이 잔여를 채웠어요"라 해, 회원이 안내대로 날짜를 바꿔도
    // 또 거부당한다.
    if (!pass.hasBookingBudget) {
      return AllRemainingBooked(pass.remaining, pass.openBookings);
    }
    final slotDate = _dateOnly(slot.startAt);
    if (slotDate.isBefore(_dateOnly(pass.validFrom))) {
      return NotYetValid(pass.validFrom);
    }
    if (slotDate.isAfter(_dateOnly(pass.validUntil))) {
      return PassExpiredForSlot(pass.validUntil);
    }
    // 일시정지 구간에 걸친 날짜는 예약 불가 — 유효기간과 같은 패스 단위 제약이라
    // 슬롯 상태(코치/만석)보다 먼저 판정한다(양끝 포함, 날짜 단위 — PassHold.contains).
    for (final h in pass.holds) {
      if (h.contains(slotDate)) {
        return PassOnHoldForSlot(h);
      }
    }
    // 담당 코치 휴무일 — 슬롯이 비어 있어도 서버가 거부한다(v1.4).
    if (pass.isTrainerOffday(slotDate)) {
      return const TrainerOffday();
    }
    if (slot.hasTrainer(pass.trainerId)) {
      return const CoachBusy();
    }
    if (slot.isFull) {
      return const SlotFull();
    }
    return Bookable(slot.remaining, slot.capacity);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 지금 취소하면 **무차감**인가(= 컷오프 이전인가).
  ///
  /// **"취소할 수 있는가"가 아니다.** DELETE /v1/bookings/{id}는 컷오프와 무관하게
  /// 항상 취소를 실행한다 — 백엔드 `CancelBooking` 주석이 명시적이다: "취소 자체는
  /// 항상 허용한다(막으면 노쇼로 위장할 유인만 커짐)". 컷오프가 지난 취소는 거부가
  /// 아니라 노쇼에 준한 원장 차감(정책상 최초 1회 유예)이 붙을 뿐이다.
  ///
  /// 그래서 이 판정으로 **취소 버튼을 감추면 안 된다**. 예전엔 false일 때 버튼 자리를
  /// "확정" 배지로 바꿔 탭 타깃 자체를 없앴는데, 그러면 회원에게 남는 선택지가
  /// 노쇼뿐이 된다 — 차감은 똑같이 일어나고 코치는 통보를 못 받는, 서버가 일부러
  /// 열어 둔 문을 앱이 닫아버리는 결과였다. 지금은 **취소는 항상 열어 두고**, 이
  /// 판정은 확인 문구가 결과(무차감/1회 차감)를 정확히 말하게 하는 데만 쓴다.
  ///
  /// [cutoffHours]는 센터 정책 실값(policy.cancel_cutoff_hours, GET /v1/center v1.4)
  /// — 정책이 편집 가능해져 24시간 하드코딩은 거짓말이 될 수 있다.
  static bool isFreeCancel({
    required DateTime startAt,
    required DateTime now,
    required int cutoffHours,
  }) {
    return startAt.difference(now) >= Duration(hours: cutoffHours);
  }
}
