// 순수 도메인 — 일시정지(홀딩) 신청의 **사전 판정**. Flutter/외부 의존 0, codegen 0.
//
// 이 파일은 서버 거부 규칙의 미러다. 원본은 두 곳이고, 판정 순서까지 그대로 옮긴다:
//  · `backend/internal/api/service.go` `HoldPass` — `pass.Status != active` 거부
//    ("이용 가능한 상태의 패스만 일시정지할 수 있어요"), 그 뒤 member 경로에서만
//    `ValidateHoldWindow` → `ValidateNewHold` 순으로 호출.
//  · `backend/internal/domain/pass.go` — `ValidateHoldWindow`(구간 검증)와
//    `ValidateNewHold`(정책 상한), `HoldDurationDays`(양끝 포함 일수).
//
// **순서가 서버와 같아야 하는 이유**는 [BookingRules.evaluate]와 같다: 두 제약이 겹칠 때
// 앱이 먼저 말하는 이유와 서버가 먼저 거부할 이유가 어긋나면, 안내를 따라 고쳐도 다른
// 이유로 다시 거부당한다.
//
// 최종 검증은 언제나 서버가 한다 — 여기 판정은 "서버가 확실히 거부할 신청"을 제출 전에
// 막아 헛걸음을 없애는 용도다. 그래서 **서버가 통과시킬 신청을 앱이 막아서는 안 된다**:
// 애매하면 통과시키고 서버 응답을 보여준다(무제한 판정을 서버와 같은 `> 0` 가드로 두는
// 이유도 이것 — 앱이 독자적으로 더 엄하게 굴면 정상 신청이 막힌다).

import 'package:rise_member/features/my/domain/my_models.dart';

/// 일시정지 신청 한 건에 대한 사전 판정 결과.
sealed class HoldRequestState {
  const HoldRequestState();
}

/// 서버가 받아줄 신청 — [days]는 이번 정지 일수(양끝 포함, 유효기간이 그만큼 늘어난다).
final class HoldAllowed extends HoldRequestState {
  const HoldAllowed(this.days);

  /// 이번 신청의 정지 일수(= 서버 `HoldDurationDays`, 양끝 포함).
  final int days;
}

/// 서버가 400으로 거부할 신청 — [message]는 화면에 그대로 띄우는 문구다.
///
/// 문구 규약: 존댓말·담백하게 **원인 + 다음 행동**. 서버가 같은 상황에 돌려주는
/// 메시지(`api/util.go` friendlyDomainMessages)와 **같은 의미**를 쓰되, 앱은 어느
/// 상한에 걸렸는지·얼마나 남았는지를 알고 있으므로 그 실값을 함께 말한다
/// (서버는 "일시정지 가능 횟수/일수를 초과했어요(센터 정책)" 한 문장으로 합쳐 보낸다).
/// 상한 수치는 **정책 실값만** 쓴다 — 모르는 값을 지어내지 않는다.
sealed class HoldRejected extends HoldRequestState {
  const HoldRejected();

  String get message;
}

/// 패스 상태가 active가 아님 — 서버 400 "이용 가능한 상태의 패스만 일시정지할 수 있어요".
final class HoldPassNotActive extends HoldRejected {
  const HoldPassNotActive(this.status, {this.validFrom});

  /// 원본 status(scheduled|expired|refunded|…) — 라벨을 그에 맞게 고르기 위해.
  final String status;

  /// scheduled일 때의 시작일(= 언제부터 가능한지) — 없으면 날짜 없이 안내한다.
  final DateTime? validFrom;

  @override
  String get message => switch (status) {
    'scheduled' =>
      validFrom == null
          ? '아직 시작 전인 회원권이에요 — 시작한 뒤에 일시정지할 수 있어요'
          : '${validFrom!.month}/${validFrom!.day}부터 시작하는 회원권이에요 — 시작한 뒤에 일시정지할 수 있어요',
    'expired' => '만료된 회원권은 일시정지할 수 없어요 — 이용 중인 회원권을 골라주세요',
    'refunded' => '환불된 회원권은 일시정지할 수 없어요 — 이용 중인 회원권을 골라주세요',
    // 미지의 status도 라벨을 지어내지 않는다(ContractItem.statusLabel과 같은 규약).
    _ => '이용 중인 회원권만 일시정지할 수 있어요',
  };
}

/// 종료일이 시작일보다 앞섬 — 서버 `HoldDurationDays` → ErrInvalidHoldRange(400).
final class HoldRangeReversed extends HoldRejected {
  const HoldRangeReversed();

  @override
  String get message => '종료일은 시작일보다 빠를 수 없어요';
}

/// 시작일이 센터(KST) 오늘보다 앞섬 — 서버 `ValidateHoldWindow`의 `next.From < today`.
final class HoldStartsInPast extends HoldRejected {
  const HoldStartsInPast(this.today);

  /// 센터(KST) 오늘 — 기기 로컬 날짜가 아니다([DateFmt.todayKst]).
  final DateTime today;

  @override
  String get message =>
      '지난 날짜는 정지할 수 없어요 — ${today.month}/${today.day} 이후로 골라주세요';
}

/// 시작일이 회원권 유효기간을 지남 — 서버 `ValidateHoldWindow`의 `next.From > validUntil`
/// (만료된 패스를 홀딩으로 부활시키는 것을 막는 규칙).
final class HoldStartsAfterValidUntil extends HoldRejected {
  const HoldStartsAfterValidUntil(this.validUntil);

  final DateTime validUntil;

  @override
  String get message =>
      '이 회원권은 ${validUntil.month}/${validUntil.day}까지예요 — 그 안의 날짜로 시작일을 골라주세요';
}

/// 기존 홀딩 구간과 겹침 — 서버 `ValidateHoldWindow`의 겹침 검사(같은 날 이중 연장 금지).
final class HoldOverlapsExisting extends HoldRejected {
  const HoldOverlapsExisting(this.hold);

  /// 겹친 기존 구간.
  final PassHold hold;

  @override
  String get message =>
      '${hold.from.month}/${hold.from.day}~${hold.to.month}/${hold.to.day}에 '
      '이미 일시정지가 있어요 — 겹치지 않는 날짜로 골라주세요';
}

/// 횟수 상한 초과 — 서버 `ValidateNewHold`의 `len(existing)+1 > maxCount`.
///
/// [used]는 이 패스의 기존 홀딩 **전부**다(조기 종료된 것 포함) — pass.go 주석
/// "조기 종료(Resume)된 홀딩도 횟수 상한에 포함된다". 재개 확인 다이얼로그가
/// 말하는 "최대 N회 중 M회를 썼어요"와 같은 값이어야 한다.
final class HoldCountExceeded extends HoldRejected {
  const HoldCountExceeded({required this.used, required this.maxCount});

  final int used;
  final int maxCount;

  @override
  String get message =>
      '일시정지는 회원권당 최대 $maxCount회예요 — 이미 $used회를 썼어요. '
      '더 필요하면 센터에 문의해주세요';
}

/// 총 일수 상한 초과 — 서버 `ValidateNewHold`의 `nextDays + Σexisting > maxTotalDays`.
final class HoldTotalDaysExceeded extends HoldRejected {
  const HoldTotalDaysExceeded({
    required this.usedDays,
    required this.requestedDays,
    required this.maxTotalDays,
  });

  /// 기존 홀딩 일수 합(양끝 포함).
  final int usedDays;

  /// 이번 신청 일수(양끝 포함).
  final int requestedDays;
  final int maxTotalDays;

  /// 이번에 아직 쓸 수 있는 일수(음수는 0으로 — 상한을 이미 넘긴 데이터 방어).
  int get remainingDays =>
      usedDays >= maxTotalDays ? 0 : maxTotalDays - usedDays;

  @override
  String get message => remainingDays == 0
      ? '일시정지는 회원권당 총 $maxTotalDays일까지예요 — 이미 $usedDays일을 써서 남은 날이 없어요. '
            '더 필요하면 센터에 문의해주세요'
      : '일시정지는 회원권당 총 $maxTotalDays일까지예요 — 이미 $usedDays일을 썼어요. '
            '이번 신청은 $requestedDays일이라 $remainingDays일 이내로 줄여주세요';
}

/// 신청 **전에** 보여주는 "얼마나 남았는가" 요약 — 표시 전용 파생 값.
///
/// [HoldRules.evaluate]와 같은 입력·같은 무제한 판정([HoldRules.countUnlimited]·
/// [HoldRules.daysUnlimited])에서 나온다 — 표시와 판정이 갈리면 "남았다고 써 있는데
/// 거부당한다"가 되기 때문에 판정([HoldRules.evaluate])과 같은 파일에 붙여 둔다.
///
/// 헤드라인은 **구속 조건(min)을 반영한다**: 일수가 10일 남아도 횟수가 0회면 실효
/// 잔여는 0이다 — 그때 "남은 일시정지 10일"을 크게 띄우면 거짓말이 된다.
final class HoldAllowance {
  const HoldAllowance._({
    required this.usedCount,
    required this.usedDaysTotal,
    required this.maxCount,
    required this.maxTotalDays,
  });

  final int usedCount;
  final int usedDaysTotal;

  /// 정책 원값 — 0 이하는 무제한(서버 `> 0` 가드 미러).
  final int maxCount;
  final int maxTotalDays;

  bool get countCapped => !HoldRules.countUnlimited(maxCount);
  bool get daysCapped => !HoldRules.daysUnlimited(maxTotalDays);

  /// 잔여 횟수 — 무제한이면 null(없는 상한으로 숫자를 지어내지 않는다).
  /// 음수는 0으로 클램프([HoldTotalDaysExceeded.remainingDays]와 같은 데이터 방어).
  int? get remainingCount =>
      countCapped ? (usedCount >= maxCount ? 0 : maxCount - usedCount) : null;

  /// 잔여 일수 — 무제한이면 null.
  int? get remainingDays => daysCapped
      ? (usedDaysTotal >= maxTotalDays ? 0 : maxTotalDays - usedDaysTotal)
      : null;

  /// 어느 상한이든 실효 잔여가 0인가 — 서버가 어떤 날짜를 넣어도 거부할 상태.
  bool get exhausted => remainingCount == 0 || remainingDays == 0;

  /// 요약 첫 줄 — "남은 것" 중심. 무제한 축은 숫자를 만들지 않는다.
  String get headline {
    if (exhausted) return '남은 일시정지가 없어요';
    if (!countCapped && !daysCapped) {
      return '지금까지 $usedCount회 · $usedDaysTotal일 쉬었어요';
    }
    if (!daysCapped) return '남은 일시정지 $remainingCount회';
    if (!countCapped) return '남은 일시정지 $remainingDays일';
    // 이력 0회면 "남은"보다 "사용 가능"이 자연스럽다 — 아직 아무것도 안 썼으니까.
    return usedCount == 0
        ? '일시정지 $remainingDays일 · $remainingCount회 사용 가능'
        : '남은 일시정지 $remainingDays일 · $remainingCount회';
  }

  /// 요약 둘째 줄 — 상한·사용량 근거. 필요 없는 상태(이력 0회 등)는 null.
  String? get detail {
    if (exhausted) {
      // 서버 판정 순서(횟수 → 일수)와 같은 순서로 원인을 말한다.
      return remainingCount == 0
          ? '최대 $maxCount회를 모두 썼어요 — 더 필요하면 센터에 문의해주세요'
          : '총 $maxTotalDays일을 모두 썼어요 — 더 필요하면 센터에 문의해주세요';
    }
    if (!countCapped && !daysCapped) return '횟수·일수 제한 없음';
    if (!daysCapped) return '일수 제한 없음 · 최대 $maxCount회 중 $usedCount회 사용';
    if (!countCapped) return '횟수 제한 없음 · 총 $maxTotalDays일 중 $usedDaysTotal일 사용';
    if (usedCount == 0) return null; // 헤드라인이 상한 전체를 이미 말했다.
    return '최대 $maxCount회/$maxTotalDays일 중 $usedCount회 · $usedDaysTotal일 사용';
  }
}

/// 순수 함수 — 서버 `HoldPass`(member 경로)의 거부 규칙 미러. 파일 상단 주석 참조.
abstract final class HoldRules {
  /// 이 패스로 일시정지를 신청할 수 있는가 — 서버 `HoldPass`는 **active만** 받는다.
  ///
  /// scheduled(시작 전)를 후보로 올리면 안 된다: 유효기간이 남아 신청 화면에는
  /// 멀쩡해 보이지만 서버가 400을 준다. refunded도 마찬가지다 — 환불 플로우가
  /// 실제로 만드는 상태고(`RefundPass`), 유효기간은 그대로 남아 있어 화면상
  /// "살아 있는" 회원권처럼 보인다.
  static bool canRequestFor(PassDetail pass) => pass.isActive;

  /// 일시정지 신청 대상 후보만 추린다 — 없으면 **빈 목록**이다.
  ///
  /// "비면 원본으로 폴백"은 하지 않는다: 폴백은 서버가 거부할 패스를 다시 후보로
  /// 올려 살아 있는 버튼을 만든다(이 결함의 원래 모습). 후보가 없으면 화면이
  /// 그 사실을 말해야 한다.
  static List<PassDetail> candidates(List<PassDetail> passes) =>
      passes.where(canRequestFor).toList();

  /// 홀딩 일수(양끝 포함) — 서버 `HoldDurationDays` 미러(09-01~09-10 = 10일).
  ///
  /// UTC 자정으로 정규화해서 뺀다: 기기 로컬 타임존에 서머타임이 있으면
  /// `DateTime.difference`가 23/25시간 구간에서 하루를 흘린다(서버 `time.Parse`는
  /// UTC 고정이라 그런 흔들림이 없다). 역전 구간이면 0 이하가 나오므로 호출측이
  /// 먼저 [evaluate]로 걸러야 한다.
  static int durationDays(DateTime from, DateTime to) {
    final f = DateTime.utc(from.year, from.month, from.day);
    final t = DateTime.utc(to.year, to.month, to.day);
    return t.difference(f).inDays + 1;
  }

  /// 기존 홀딩 일수 합 — 서버 `ValidateNewHold`의 Σ`HoldDurationDays(h)`.
  /// 역전된 구간(저장 데이터가 깨진 경우)은 서버와 같이 **건너뛴다**.
  static int usedDays(List<PassHold> holds) {
    var total = 0;
    for (final h in holds) {
      final d = durationDays(h.from, h.to);
      if (d <= 0) continue;
      total += d;
    }
    return total;
  }

  /// 횟수 상한이 무제한인가 — 서버 `ValidateNewHold`의 `maxCount > 0` 가드 미러.
  /// 계약 v1.3에서 무제한은 -1이지만, 서버가 `> 0`으로만 판정하므로 0 이하 전부를
  /// 같은 뜻으로 본다(앱이 서버보다 엄해지지 않게).
  static bool countUnlimited(int maxHoldsPerPass) => maxHoldsPerPass <= 0;

  /// 총 일수 상한이 무제한인가 — 서버 `maxTotalDays > 0` 가드 미러.
  static bool daysUnlimited(int maxHoldTotalDays) => maxHoldTotalDays <= 0;

  /// 이 신청을 서버가 받아줄지 — 거부면 이유와 문구를 함께 돌려준다.
  ///
  /// [today]는 **센터(KST) 오늘**을 넣는다(`DateFmt.todayKst()`) — 서버 `today()`가
  /// KST 고정이라 기기 로컬 날짜로 재면 해외 체류 시 하루씩 어긋난다.
  /// [maxHoldsPerPass]·[maxHoldTotalDays]는 센터 정책 실값(GET /v1/center)이며,
  /// 화면에 상한을 표기할 때도 **같은 값**을 써야 한다([allowance]).
  static HoldRequestState evaluate({
    required PassDetail pass,
    required DateTime from,
    required DateTime to,
    required DateTime today,
    required int maxHoldsPerPass,
    required int maxHoldTotalDays,
  }) {
    // 1) HoldPass가 가장 먼저 보는 것 — 상태.
    if (!canRequestFor(pass)) {
      return HoldPassNotActive(pass.status, validFrom: pass.validFrom);
    }
    final f = _dateOnly(from);
    final t = _dateOnly(to);
    final d0 = _dateOnly(today);

    // 2) ValidateHoldWindow — HoldDurationDays(next) → 과거 → 유효기간 밖 → 겹침.
    if (t.isBefore(f)) {
      return const HoldRangeReversed();
    }
    if (f.isBefore(d0)) {
      return HoldStartsInPast(d0);
    }
    final validUntil = _dateOnly(pass.validUntil);
    if (f.isAfter(validUntil)) {
      return HoldStartsAfterValidUntil(validUntil);
    }
    for (final h in pass.holds) {
      // 서버: `next.From <= h.To && h.From <= next.To` (양끝 포함).
      if (!f.isAfter(_dateOnly(h.to)) && !_dateOnly(h.from).isAfter(t)) {
        return HoldOverlapsExisting(h);
      }
    }

    // 3) ValidateNewHold — 횟수 상한 → 총 일수 상한.
    final used = pass.holds.length;
    if (!countUnlimited(maxHoldsPerPass) && used + 1 > maxHoldsPerPass) {
      return HoldCountExceeded(used: used, maxCount: maxHoldsPerPass);
    }
    final requestedDays = durationDays(f, t);
    if (!daysUnlimited(maxHoldTotalDays)) {
      final priorDays = usedDays(pass.holds);
      if (priorDays + requestedDays > maxHoldTotalDays) {
        return HoldTotalDaysExceeded(
          usedDays: priorDays,
          requestedDays: requestedDays,
          maxTotalDays: maxHoldTotalDays,
        );
      }
    }
    return HoldAllowed(requestedDays);
  }

  /// 잔여 요약 — [evaluate]와 같은 입력에서 [HoldAllowance]를 만든다.
  static HoldAllowance allowance({
    required PassDetail pass,
    required int maxHoldsPerPass,
    required int maxHoldTotalDays,
  }) {
    return HoldAllowance._(
      usedCount: pass.holds.length,
      usedDaysTotal: usedDays(pass.holds),
      maxCount: maxHoldsPerPass,
      maxTotalDays: maxHoldTotalDays,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
