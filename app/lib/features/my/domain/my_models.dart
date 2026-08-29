// 순수 도메인 — 마이 탭(회원권·이용내역·계약·동의). Flutter/외부 의존 0, codegen 0.

import 'package:rise_member/core/utils/date_format.dart';

/// Pass.holds 한 건 — 일시정지 구간(양끝 포함, 날짜 단위).
class PassHold {
  const PassHold({required this.from, required this.to, this.reason});

  final DateTime from;
  final DateTime to;
  final String? reason;

  /// [day]가 구간(from~to, 날짜 단위, 양끝 포함) 안인가.
  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    return !d.isBefore(f) && !d.isAfter(t);
  }
}

class PassDetail {
  const PassDetail({
    required this.id,
    required this.product,
    required this.trainerId,
    this.trainerName,
    this.trainerInactive = false,
    required this.status,
    required this.remaining,
    required this.totalSessions,
    required this.paidAmount,
    required this.validFrom,
    required this.validUntil,
    this.holds = const [],
  });

  final String id;
  final String product;
  final String trainerId;
  final String? trainerName;

  /// 담당 코치가 퇴사(Staff.status=inactive)했는가 — 계약 v2.0. 만료·환불된 과거
  /// 패스는 퇴사 선행 조건에 걸리지 않으므로 마이 탭에서 실제로 마주칠 수 있다.
  final bool trainerInactive;
  final String status; // active|scheduled|expired|refunded
  final int remaining;
  final int totalSessions;
  final int paidAmount;
  final DateTime validFrom;
  final DateTime validUntil;
  final List<PassHold> holds;

  bool get isActive => status == 'active';
  bool get isScheduled => status == 'scheduled';

  /// 오늘이 포함된 일시정지 구간(없으면 null) — "일시정지 중" 배지·재개 버튼 노출용.
  /// "오늘"은 서버와 같은 센터(KST) 기준 — 기기 로컬 날짜로 재면 해외 체류 시
  /// 구간 양끝에서 하루씩 어긋난다(서버는 `today()`가 KST 고정).
  PassHold? get activeHold {
    final today = DateFmt.todayKst();
    for (final h in holds) {
      if (h.contains(today)) return h;
    }
    return null;
  }
}

/// API계약_v1.md Ledger.reason — 서버가 내보내는 9종(`backend/internal/domain/ledger.go`)
/// + **미지 값 보존**.
///
/// enum이 아니라 값 객체인 이유: 모르는 reason을 아홉 중 하나로 접으면 원장 행이
/// **그럴듯하게 틀린** 라벨을 단다(예전엔 미지 값이 전부 '수업 완료'로 떨어졌다 —
/// 금전·회차 기록에서 가장 위험한 종류의 오표기다). [ContractItem.statusLabel]의
/// `_ => status` 폴백과 같은 규약으로, 모르면 wire 값을 그대로 보여주고 라벨을
/// 지어내지 않는다. 서버가 10번째 reason을 앱 릴리스보다 먼저 내보내도 안전하다.
final class LedgerReason {
  const LedgerReason._(this.wire, this._label);

  /// 서버 wire 값 원문(`issue`·`noshow_waived`·…). 미지 값도 그대로 들고 있다.
  final String wire;

  /// 아는 값이면 한국어 라벨, 모르면 null(→ [label]이 [wire]로 폴백).
  final String? _label;

  static const issue = LedgerReason._('issue', '발급');
  static const complete = LedgerReason._('complete', '수업 완료');
  static const noshow = LedgerReason._('noshow', '노쇼');
  static const noshowWaived = LedgerReason._('noshow_waived', '노쇼 · 최초 1회 유예');
  static const revert = LedgerReason._('revert', '취소 복구');
  static const refund = LedgerReason._('refund', '환불');
  static const hold = LedgerReason._('hold', '일시정지');
  static const resume = LedgerReason._('resume', '재개');

  /// 서버 의미는 **담당 트레이너 이관**이다 — `ledger.go`의
  /// `ReasonTransfer = "transfer" // 트레이너 이관(P18)`, 생성 지점은 코치 인수인계
  /// (`api/service_staff.go`가 delta 0 감사 기록을 남긴다). "양도"로 쓰면 회원이
  /// **회원권을 남에게 넘긴 것**으로 읽는다 — 앱 용어(트레이너=코치)에 맞춰 옮겼다.
  static const transfer = LedgerReason._('transfer', '담당 코치 이관');

  /// 서버가 내보내는 전체 집합 — [fromWire] 조회용이자 라벨 커버리지 테스트의 기준.
  static const known = <LedgerReason>[
    issue,
    complete,
    noshow,
    noshowWaived,
    revert,
    refund,
    hold,
    resume,
    transfer,
  ];

  static LedgerReason fromWire(String value) {
    for (final r in known) {
      if (r.wire == value) return r;
    }
    return LedgerReason._(value, null);
  }

  /// 아는 reason인가 — 미지 값은 라벨을 지어내지 않고 원문을 노출한다.
  bool get isKnown => _label != null;

  /// 원장 행에 찍히는 표시 문구. 미지 값은 wire 원문, wire마저 비면 '기타'
  /// (빈 문자열이면 "8/14 (금)  -1"처럼 사유가 통째로 사라져 더 못 읽는다).
  String get label => _label ?? (wire.isEmpty ? '기타' : wire);

  @override
  bool operator ==(Object other) => other is LedgerReason && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => 'LedgerReason($wire)';
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.passId,
    required this.delta,
    required this.reason,
    this.refBookingId,
    this.by,
    required this.at,
  });

  final String id;
  final String passId;
  final int delta;
  final LedgerReason reason;
  final String? refBookingId;
  final String? by;
  final DateTime at;
}

/// API계약 v1.1 — Contract(전자계약). status: draft|sent|signed|voided.
/// v1.5: voided = 패스 환불로 거래가 해지돼 서명 대상에서 빠진 계약(종단 상태) —
/// 서명·발송이 서버에서 400이므로 UI도 탭을 열지 않는다.
class ContractItem {
  const ContractItem({
    required this.id,
    required this.passId,
    required this.product,
    required this.paidAmount,
    required this.status,
    this.sentAt,
    this.signedAt,
    this.pdfPath,
    this.penaltyRate,
  });

  final String id;
  final String passId;
  final String product; // 예: "PT 20회"
  final int paidAmount;
  final String status; // draft|sent|signed|voided
  final DateTime? sentAt;
  final DateTime? signedAt;
  final String? pdfPath;

  /// 계약 생성 시점에 스냅샷된 위약금율(0~1). 이후 센터가 정책을 올려도 이 계약의
  /// 환불 정산에는 소급되지 않는다(domain/contract.go). **null은 0%가 아니라 "모름"**
  /// (v1.5 이전 레거시 계약) — 상세 화면은 그때 행을 아예 뺀다.
  final double? penaltyRate;

  bool get isSigned => status == 'signed';

  /// 환불로 무효 처리된 계약(v1.5) — 서명 유도 대상에서 제외.
  bool get isVoided => status == 'voided';

  // 미지의 status는 wire 값 그대로 폴백 — 새 상태가 추가돼도 행이 깨지지 않는다.
  String get statusLabel => switch (status) {
        'draft' => '작성 중',
        'sent' => '서명 대기',
        'signed' => '서명 완료',
        'voided' => '무효(환불)',
        _ => status,
      };
}

class ConsentState {
  const ConsentState({
    required this.general,
    required this.sensitive,
    this.signedAt,
    this.revokedAt,
  });

  final bool general;
  final bool sensitive;
  final DateTime? signedAt;
  final DateTime? revokedAt;

  ConsentState copyWith({bool? general, bool? sensitive}) => ConsentState(
        general: general ?? this.general,
        sensitive: sensitive ?? this.sensitive,
        signedAt: signedAt,
        revokedAt: revokedAt,
      );
}

/// 결제 1건(분할 포함) — 회원이 보는 관점.
///
/// 서버는 `GET /v1/payments?member=`로 본인 분할 내역을 그대로 내려주는데 앱에 이를
/// 그리는 화면이 없었다. 분할로 결제한 회원이 "2차가 언제 얼마인지"를 확인할 방법이
/// 앱 안에 하나도 없던 셈이다.
class PaymentItem {
  const PaymentItem({
    required this.id,
    required this.passId,
    required this.method,
    required this.total,
    required this.installments,
  });

  final String id;
  final String passId;
  final String method; // card|cash|transfer
  final int total;
  final List<InstallmentItem> installments;

  String get methodLabel => switch (method) {
        'card' => '카드',
        'cash' => '현금',
        'transfer' => '계좌이체',
        _ => method, // 모르는 값은 wire 값 그대로 — 새 수단이 생겨도 행이 깨지지 않는다
      };

  /// 분할이 아니라 한 번에 낸 결제인가 — 회차 카드를 통째로 접기 위한 판정.
  bool get isLumpSum => installments.length <= 1;

  /// 아직 낼 돈 — 서버 `Payment.Outstanding()`과 **같은 규칙**(미납이고 종결되지 않은 회차).
  /// 두 값이 갈리면 앱은 "미납 30만원"이라 하고 데스크는 "완납"이라 한다.
  int get outstanding {
    var sum = 0;
    for (final i in installments) {
      if (i.isOpen) sum += i.amount;
    }
    return sum;
  }
}

/// 분할납부 회차.
class InstallmentItem {
  const InstallmentItem({
    required this.due,
    required this.amount,
    this.paidAt,
    this.waivedAt,
  });

  /// 납부 예정일. 서버가 "YYYY-MM-DD" 문자열로 준다.
  final String due;
  final int amount;
  final DateTime? paidAt;

  /// 청구 종결 시각(v1.5) — 패스 환불로 더 이상 수납하지 않는 회차.
  /// **삭제가 아니라 표식**이라 목록에는 남지만 미납 합계에서는 빠진다.
  final DateTime? waivedAt;

  /// 서버 `Installment.open()` — 미납이고 종결되지 않음.
  bool get isOpen => paidAt == null && waivedAt == null;

  String get statusLabel {
    if (waivedAt != null) return '청구 종결';
    if (paidAt != null) return '납부 완료';
    return '납부 예정';
  }
}

class MySummary {
  const MySummary({
    required this.passes,
    required this.ledgerByPass,
    required this.contracts,
    required this.consent,
    this.payments = const [],
    this.paymentsFailed = false,
    this.contractsFailed = false,
    this.ledgerFailedPassIds = const {},
    this.consentFailed = false,
  });

  final List<PassDetail> passes;

  /// passId → 원장 목록(최신순).
  final Map<String, List<LedgerEntry>> ledgerByPass;
  final List<ContractItem> contracts;

  /// 내 결제 내역(분할 포함). 조회 실패는 [paymentsFailed]로 구분한다 —
  /// 빈 목록을 "결제 없음"으로 위장하면 미납이 있는 회원에게 없다고 말하게 된다.
  final List<PaymentItem> payments;
  final bool paymentsFailed;

  /// 서버가 알려준 동의 상태. [consentFailed]가 true면 **이 값은 모른다는 뜻**이지
  /// "미동의"가 아니다 — 기본값(false/false)을 그대로 저장하면 실제 동의가 철회된다.
  final ConsentState consent;

  /// 계약 목록 조회 실패 여부 — best-effort 폴백(빈 목록)을 "계약 없음"으로
  /// 위장하지 않고 UI가 실패 문구로 구분 표시하기 위한 플래그.
  final bool contractsFailed;

  /// 원장 조회에 실패한 패스 id들 — 빈 목록([ledgerByPass]의 `[]`)을 "아직 내역이
  /// 없어요"로 위장하지 않기 위한 플래그. 원장은 패스별로 따로 조회하므로
  /// 계약(단일 플래그)과 달리 **패스 단위**로 실패를 기억한다.
  final Set<String> ledgerFailedPassIds;

  /// 동의 상태 조회 실패 여부 — [consent]가 하드코딩 기본값(false/false)이라는 뜻.
  ///
  /// 이 플래그가 true인 동안 **저장(PUT /v1/members/{id})을 막아야 한다**: 서버는
  /// sensitive true→false 전이를 철회로 보고 revoked_at을 기록하고, 그 순간
  /// 인바디·체형사진 저장이 잠긴다(backend normalizeConsentTransition ·
  /// Consent.SensitiveConsentValid). 조회 한 번 실패한 화면 값을 그대로 되돌려
  /// 보내면 회원이 토글을 건드리지 않았는데도 실제 동의가 철회된다.
  final bool consentFailed;

  bool ledgerFailedFor(String passId) => ledgerFailedPassIds.contains(passId);
}
