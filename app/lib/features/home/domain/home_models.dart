// 순수 도메인 — 홈 화면 집계. Flutter/외부 의존 0, codegen 0.

import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';
import 'package:rise_member/features/home/domain/checkin_rules.dart';
import 'package:rise_member/features/my/domain/my_models.dart' show PassHold;

/// 패스 스위처 칩 하나(= Pass 1건, 담당 코치 기준으로 예약/Home Work가 바뀜).
class PassOption {
  const PassOption({
    required this.id,
    required this.product,
    required this.trainerId,
    this.trainerName,
    this.trainerInactive = false,
    this.trainerOffdays = const {},
    required this.status,
    required this.remaining,
    required this.totalSessions,
    required this.validFrom,
    required this.validUntil,
    this.holds = const [],
  });

  final String id;
  final String product; // 예: "PT 20회"
  final String trainerId;
  final String? trainerName;

  /// 담당 코치가 퇴사(Staff.status=inactive)했는가 — 계약 v2.0. 이름은 그대로 두고
  /// 표기에만 "(퇴사)"를 덧붙이기 위한 플래그. 기본 false = 구버전 서버/미해석은 현직.
  final bool trainerInactive;

  /// 담당 코치의 휴무일(Staff.offdays, "YYYY-MM-DD" 집합) — 이름·퇴사 여부와 **같은
  /// 스태프 응답**에서 함께 해석한다. 홈은 쓰지 않지만 예약 탭의 사전 판정
  /// (BookingRules → TrainerOffday)이 이 패스를 통해 받는다: 같은 사실을 두 곳에서
  /// 따로 읽으면 화면끼리 답이 갈린다(퇴사 여부에서 이미 겪은 문제).
  /// 기본 빈 집합 = 구버전 서버/스태프 조회 실패 시 "모른다" — 예약을 막지 않는다.
  final Set<String> trainerOffdays;
  final String status; // active|scheduled|expired|refunded
  final int remaining;
  final int totalSessions;
  final DateTime validFrom;
  final DateTime validUntil;

  /// Pass.holds — 일시정지 구간(마이 탭 PassHold 로직 재사용).
  final List<PassHold> holds;

  bool get isActive => status == 'active';
  bool get isScheduled => status == 'scheduled';
  double get remainingRatio => totalSessions == 0 ? 0 : remaining / totalSessions;

  /// 오늘이 포함된 일시정지 구간(없으면 null) — 마이 탭과 동일 판정으로
  /// 홈 회원권 카드에 "일시정지 중 ~M/D" 배지를 띄운다.
  /// "오늘"은 서버와 같은 센터(KST) 기준 — 기기 로컬 날짜로 재면 해외 체류 시
  /// 구간 양끝에서 하루씩 어긋난다(DateFmt 클래스 주석의 시간축 규약).
  PassHold? get activeHold {
    final today = DateFmt.todayKst();
    for (final h in holds) {
      if (h.contains(today)) return h;
    }
    return null;
  }

  /// 만료까지 남은 일수 — 날짜 단위(dateOnly) 비교. 시각까지 비교하면 만료 당일
  /// D-0이 자정 이후 음수로 표기되는 문제가 있어 날짜만 비교한다.
  /// 기준일은 센터(KST) 오늘 — 서버의 만료 판정과 같은 날짜를 본다.
  ///
  /// 달력 날짜 차이는 **UTC 생성자**로 센다(P73). 로컬 플래그 `DateTime`끼리의 `difference`는
  /// 절대 시각 차라, 기기가 서머타임 지역이면 전환일을 낀 하루가 23시간 → `inDays` 0으로
  /// 하루가 사라진다(한국엔 DST가 없지만 이 값은 **기기** 타임존 규칙을 탄다). 필드만 옮겨
  /// UTC로 만들면 기기 규칙이 개입할 자리가 없다.
  int get daysUntilExpiry {
    final today = DateFmt.todayKst();
    final from = DateTime.utc(today.year, today.month, today.day);
    final until = DateTime.utc(validUntil.year, validUntil.month, validUntil.day);
    return until.difference(from).inDays;
  }

  /// 유효기간 표기 라벨 — 이미 만료된 패스는 "D--3" 같은 음수 D-day 대신 "만료".
  String get expiryLabel => daysUntilExpiry < 0 ? '만료' : 'D-$daysUntilExpiry';
}

/// 홈 "다음 예약" 카드가 그리는 예약 1건.
///
/// ## 시각 의존 값은 **필드가 아니라 파생 계산**이다 (P51)
///
/// 예전엔 `canCheckIn`·`freeCancel`이 bool **필드**였다. repository가 로드 시점의
/// `DateFmt.nowKst()`로 한 번 계산해 담았고, 그 값은 다음 홈 재조회까지 굳었다.
/// 실기기에서 드러난 결과: 19:00 예약(체크인 창 18:30~19:30)을 18:26에 열어 둔
/// 회원은 18:35에도 회색 버튼과 "수업 시작 전후 30분에 열려요"를 봤다. 당겨서
/// 새로고침해야 풀린다는 걸 알 방법이 없으니, 셀프 체크인이 없애려던 데스크
/// 왕복을 그대로 했다.
///
/// 그래서 스냅샷에는 **시각 자체([startAt])만** 담고, 판정은 `now`를 받는 메서드로
/// 옮겼다. 화면은 매 build에서 `DateFmt.nowKst()`로 다시 묻고, 경계 시각
/// ([checkInOpensAt] 등)에 스스로 다시 그린다(`TimeBoundaryBuilder`).
/// 재평가에 서버 왕복은 없다 — 바뀐 건 시계뿐이고 예약 사실은 그대로다.
class NextBooking {
  const NextBooking({
    required this.id,
    required this.startAt,
    required this.kind,
    this.trainerName,
    this.trainerInactive = false,
  });

  final String id;
  final DateTime startAt;
  final String kind; // pt|group|ot
  final String? trainerName;

  /// 담당 코치 퇴사 여부(계약 v2.0). 계약상 **미래 confirmed 예약이 남아 있으면
  /// 퇴사 처리가 409로 막히므로** 정상 흐름에선 항상 false다 — 서버가 규칙을
  /// 어겼을 때 이름만 멀쩡히 보여주지 않도록 들고만 있는 방어용 플래그.
  final bool trainerInactive;

  /// [now] 시점에 셀프 체크인이 열려 있는가 — 서버 ±30분 시간창과 같은 판정
  /// ([CheckinRules.isOpen], `backend/internal/domain/checkin.go`의 거울).
  bool canCheckInAt(DateTime now) => CheckinRules.isOpen(startAt: startAt, now: now);

  /// 셀프 체크인 창이 열리는/닫히는 시각 — 화면이 그때 다시 그리기 위한 경계.
  DateTime get checkInOpensAt => CheckinRules.opensAt(startAt);
  DateTime get checkInClosesAt => CheckinRules.closesAt(startAt);

  /// [now]에 취소하면 **무차감**인가(= 취소 컷오프 이전인가).
  ///
  /// "취소할 수 있는가"가 아니다 — 서버는 컷오프와 무관하게 취소를 항상 허용한다
  /// ([BookingRules.isFreeCancel] 주석). 예전 이름(canCancel)을 그대로 읽고 홈 카드가
  /// 자물쇠 + "취소 마감"을 띄웠던 탓에, 회원은 서버가 열어 둔 문 앞에서 노쇼 말고는
  /// 선택지가 없다고 믿게 됐다. 이 값은 **문구만** 가른다.
  ///
  /// 여기도 필드가 아닌 이유는 [canCheckInAt]과 같다 — 게다가 이쪽은 **돈이
  /// 걸려 있다**. 컷오프를 넘기는 순간 문구가 "무료"에서 "1회 차감"으로 바뀌어야
  /// 하는데, 굳어 있으면 회원이 무차감인 줄 알고 예약 탭으로 건너간다.
  bool isFreeCancelAt(DateTime now, {required int cutoffHours}) =>
      BookingRules.isFreeCancel(startAt: startAt, now: now, cutoffHours: cutoffHours);

  /// 무료 취소가 끝나는 시각(= 시작 −[cutoffHours]) — 화면의 재평가 경계.
  DateTime freeCancelUntil(int cutoffHours) => startAt.subtract(Duration(hours: cutoffHours));

  /// [now] 기준으로 이 예약이 "오늘"인가.
  ///
  /// [startAt]은 slotKey에서 온 센터(KST) 벽시계 표현이라 [now]도 같은 기준
  /// ([DateFmt.nowKst])이어야 한다 — 로컬 날짜와 섞으면 해외 기기에서 '오늘'
  /// 배지가 하루 어긋난다.
  bool isTodayAt(DateTime now) =>
      startAt.year == now.year && startAt.month == now.month && startAt.day == now.day;
}

class HomeworkItem {
  const HomeworkItem({
    required this.hwId,
    required this.index,
    required this.name,
    this.sets,
    this.reps,
    this.note,
    required this.done,
  });

  final String hwId;
  final int index; // HwCheck.done 배열 내 위치
  final String name;

  /// 처방 세트 수. null 또는 0 = "세트 개념이 없는 과제"(걷기 30분 등).
  ///
  /// 두 값을 같게 취급하는 이유는 출처가 둘이라서다: 어드민 폼은 빈 칸을 `null`로
  /// 보내고(admin ItemsEditor), Go의 `HwItem.Sets`는 int라 미지정이 zero value `0`으로
  /// 직렬화된다. 어느 쪽이 오든 화면에서는 세트 표기가 빠져야 한다.
  final int? sets;

  /// 처방 횟수 — **문자열**이다(계약 v1.3). "12"뿐 아니라 "10-12"·"40초"·"각 15회"처럼
  /// 숫자가 아닌 현장 표기가 그대로 온다. 파싱하지 않고 받은 대로 보여준다.
  final String? reps;
  final String? note;
  final bool done;

  /// "3×40초" 표기 — 처방이 하나도 없으면 null(호출측이 자리를 비운다).
  ///
  /// 빈 세그먼트 조합("0×15"·"3×")을 만들지 않는 게 요점이다. 규약은 기록 탭의
  /// 수업기록 카드(`workout_log_list.dart`의 `_entryLabel`)와 같다 — 같은 성격의 값
  /// (sets int + reps string)이 두 화면에서 다르게 읽히면 회원이 다른 것으로 오해한다.
  String? get prescription {
    final s = sets ?? 0;
    final r = reps?.trim() ?? '';
    if (s > 0 && r.isNotEmpty) return '$s×$r';
    if (s > 0) return '$s세트';
    return r.isEmpty ? null : r;
  }

  HomeworkItem copyWith({bool? done}) => HomeworkItem(
        hwId: hwId,
        index: index,
        name: name,
        // 낙관적 토글이 이 둘을 흘리면 체크 한 번에 처방이 화면에서 사라진다
        // (HomeViewModel.toggleHomework가 항목을 통째로 갈아끼운다).
        sets: sets,
        reps: reps,
        note: note,
        done: done ?? this.done,
      );
}

class HomeSummary {
  const HomeSummary({
    required this.passes,
    required this.selectedPassId,
    this.hasUsablePass = true,
    this.nextBooking,
    required this.homeworkItems,
    required this.homeworkDate,
    this.homeworkChecksFailed = false,
  });

  final List<PassOption> passes;
  final String selectedPassId;

  /// 지금 **쓸 수 있는** 회원권(active 또는 scheduled)이 하나라도 있는가.
  ///
  /// false면 [passes]는 비어 있지 않지만 전부 종료 상태(만료·환불)다. 회원권이
  /// 0개인 상태([EmptyPassesFailure])와 다른 사건이라 실패로 던지지 않는다 —
  /// 예약 탭이 홈 요약을 그대로 받아 만료·환불 패스를 `PassNotUsable`로 안내하고
  /// 있어서(booking_view_model), 여기서 던지면 그 안내까지 함께 사라진다.
  ///
  /// 대신 홈이 이 값을 보고 정상 본문(잔여 링·다음 예약·헤더 배지)을 그리지 않는다.
  /// 그리는 순간 환불된 회원권이 "잔여 8회"로 살아 있는 것처럼 보인다.
  final bool hasUsablePass;
  final NextBooking? nextBooking;
  final List<HomeworkItem> homeworkItems;

  /// [homeworkItems]가 **어느 날짜의 것인가**(센터 KST 날짜, 자정으로 자름).
  ///
  /// ## 왜 날짜를 들고 다니는가 (P17 — 자정 경계의 조용한 덮어쓰기)
  ///
  /// Home Work는 시각 판정이 아니라 **문서 선택**이다. 배정 필터(`isActiveOn`),
  /// 체크 조회(`GET /v1/hw-checks?date=`), 그리고 쓰기(`POST /v1/hw-checks`)가
  /// 전부 하나의 날짜를 키로 삼는다 — 서버 `store.SaveHwCheck`는
  /// `(회원,배정,날짜)` 합성 키에 `.Set()`이라 **문서 전체 교체**다.
  ///
  /// 예전엔 읽기가 repository에서 `todayKst()`를 한 번 읽고, 쓰기는
  /// `HomeViewModel.toggleHomework`가 **그 순간의 시계를 다시** 읽었다. 23:50에
  /// 홈을 열고 00:05에 한 칸을 체크하면, 어제 목록으로 만든 done 배열이 **오늘
  /// 문서를 통째로 덮었다.** 오늘 이미 체크해 둔 기록이 조용히 사라지고, 배정
  /// 항목 수가 다르면 인덱스까지 어긋난다.
  ///
  /// 그래서 "언제 읽었는가"를 요약에 함께 실어 올린다. 쓰기는 이 값을 그대로
  /// 쓰고(두 번째 시계 읽기 없음), 이 값이 오늘과 다르면 아예 보내지 않는다
  /// ([HomeViewModel.toggleHomework]). [homeworkChecksFailed]와 같은 처방이다 —
  /// **모르는(혹은 다른) 상태에서 문서 전체를 덮지 않는다.**
  final DateTime homeworkDate;

  /// 오늘 체크 상태(GET /v1/hw-checks) 조회 실패 여부 — true면 [homeworkItems]의
  /// `done`은 **서버 값이 아니라 폴백(false)**이다.
  ///
  /// POST /v1/hw-checks는 done 배열 **전체**를 보내고 서버는 문서를 통째로 교체한다
  /// (store.SaveHwCheck의 `.Set()`). 그래서 이 플래그가 서 있는 동안 토글을
  /// 허용하면, 서버의 `[true,true,false]`가 회원이 방금 누른 한 칸만 반영된
  /// `[false,false,true]`로 덮여 완료 기록 두 건이 조용히 사라진다.
  /// 홈 화면과 [HomeViewModel.toggleHomework]가 이 값을 보고 토글을 잠근다.
  final bool homeworkChecksFailed;

  /// 오늘 Home Work 진행 배지 — items에서 파생(토글 copyWith 후에도 항상 최신).
  int get homeworkDone => homeworkItems.where((i) => i.done).length;
  int get homeworkTotal => homeworkItems.length;

  PassOption get selectedPass =>
      passes.firstWhere((p) => p.id == selectedPassId, orElse: () => passes.first);

  HomeSummary copyWith({
    List<PassOption>? passes,
    String? selectedPassId,
    bool? hasUsablePass,
    NextBooking? nextBooking,
    List<HomeworkItem>? homeworkItems,
    DateTime? homeworkDate,
    bool? homeworkChecksFailed,
  }) {
    return HomeSummary(
      passes: passes ?? this.passes,
      selectedPassId: selectedPassId ?? this.selectedPassId,
      // homeworkChecksFailed와 같은 이유로 반드시 현재 값을 이어받는다 — 낙관적
      // 토글의 copyWith가 이 플래그를 떨어뜨리면 "이용 가능한 회원권 없음" 화면이
      // 체크 한 번에 정상 홈으로 되돌아간다.
      hasUsablePass: hasUsablePass ?? this.hasUsablePass,
      nextBooking: nextBooking ?? this.nextBooking,
      homeworkItems: homeworkItems ?? this.homeworkItems,
      // 항목만 갈아끼우는 낙관적 토글이 **날짜를 잃으면 안 된다** — 이 값이 흔들리면
      // 쓰기 가드가 어제 목록을 오늘로 오인해 통과시킨다(homeworkDate 주석).
      homeworkDate: homeworkDate ?? this.homeworkDate,
      // 낙관적 토글의 copyWith가 이 플래그를 떨어뜨리면 잠금이 첫 setState에
      // 풀린다 — 명시하지 않으면 반드시 현재 값을 이어받는다.
      homeworkChecksFailed: homeworkChecksFailed ?? this.homeworkChecksFailed,
    );
  }
}
