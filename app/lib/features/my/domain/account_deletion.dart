/// 회원탈퇴(API계약 v2.11) 도메인 — 확인 화면이 고지할 내용과 서버 응답 모델.
///
/// 문구를 위젯이 아니라 여기 모은 이유: 이 목록은 **서버가 실제로 하는 일과 한 줄씩 대응**해야
/// 한다. 서버는 지우지 않는데 화면이 "지웁니다"라고 말하는 순간, 그건 UI 문구 실수가 아니라
/// 개인정보 처리에 대한 거짓 고지다. 한 자리에 모아 두면 서버 계약이 바뀔 때 같이 움직인다
/// (P14 인쇄 안내문·P15 삭제 확인 문구가 서버와 어긋나 있던 것과 같은 종류의 결함 예방).
library;

/// 탈퇴 시 **파기**되는 것. 서버 `store.PurgeCounts` + 가명화 대상과 대응한다.
const withdrawalPurgedItems = <String>[
  '이름·전화번호 등 회원 정보',
  '체형사진(원본 파일까지 삭제)',
  '인바디 기록',
  '수업 기록과 코치 메모',
  'Home Work 수행 기록',
  '방문·체크인 기록',
  '고정 스케줄과 앞으로의 예약',
  '앱 로그인 계정',
];

/// 탈퇴해도 **보존**되는 것과 그 이유.
///
/// 이유를 함께 적는 것이 이 목록의 핵심이다 — App Store Guideline 5.1.1(v)는 법적 목적의
/// 보관을 허용하되 그 필요를 **구체적으로 고지**할 것을 요구한다. "일부 정보는 보관됩니다"로는
/// 그 요건도, 회원의 알 권리도 충족되지 않는다.
const withdrawalRetainedItems = <({String item, String reason})>[
  (item: '회원권 발급·차감 내역', reason: '전자상거래법상 계약에 관한 기록 — 5년'),
  (item: '결제·환불 기록', reason: '전자상거래법상 대금결제에 관한 기록 — 5년'),
  (item: '전자계약서', reason: '전자상거래법상 계약에 관한 기록 — 5년'),
  (item: '지난 수업 예약 이력', reason: '위 내역이 어느 수업의 것인지 가리키는 기록'),
];

/// 보존 기록에서 신원이 어떻게 지워지는지 — 회원이 "그럼 5년간 내 이름이 남는 거냐"에
/// 답을 얻지 못하면 위 목록은 오히려 불안만 남긴다.
const withdrawalRetentionNote =
    '보존되는 기록에서도 이름과 전화번호는 함께 지워져요. 금액·회차·날짜만 남고 누구의 것인지는 알 수 없어요.';

/// AccountDeletionSummary — `DELETE /v1/me` 응답(계약 v2.11).
///
/// 건수를 그대로 들고 오는 이유: 완료 안내가 "삭제되었습니다"라는 단정 대신 **서버가 실제로
/// 한 일**을 말할 수 있어야 한다. 특히 [remainingSessions]는 0이 아닐 수 있다 — 서버가 잔여
/// 회차를 이유로 탈퇴를 막지 않기 때문이고(Guideline 5.1.1(v)), 그렇다면 남은 회차의 정산이
/// 어떻게 되는지를 마지막 화면이 사실대로 말해야 한다.
class AccountDeletionSummary {
  const AccountDeletionSummary({
    this.bodyPhotos = 0,
    this.inbody = 0,
    this.workoutLogs = 0,
    this.hwChecks = 0,
    this.cancelledBookings = 0,
    this.remainingSessions = 0,
    this.retainedPasses = 0,
    this.retainedPayments = 0,
    this.retainedContracts = 0,
  });

  /// 서버 응답(JSON)에서 만든다. **모든 필드가 옵셔널**이다 — 구서버(필드 부재)나 응답 형태
  /// 변경으로 파싱이 던지면, 실제로는 이미 지워진 계정을 두고 앱이 실패 화면을 띄우게 된다.
  /// 탈퇴는 되돌릴 수 없으므로 "성공했는데 실패로 보이는" 쪽이 훨씬 나쁘다(v2.9 `source`
  /// 옵셔널 규약과 같은 근거 — 파싱 실패 1건이 기록 탭 셋을 죽인 전례).
  factory AccountDeletionSummary.fromJson(Map<String, dynamic> json) {
    final purged = json['purged'] as Map<String, dynamic>? ?? const {};
    final retained = json['retained'] as Map<String, dynamic>? ?? const {};
    int at(Map<String, dynamic> m, String key) => (m[key] as num?)?.toInt() ?? 0;
    return AccountDeletionSummary(
      bodyPhotos: at(purged, 'body_photos'),
      inbody: at(purged, 'inbody'),
      workoutLogs: at(purged, 'workout_logs'),
      hwChecks: at(purged, 'hw_checks'),
      cancelledBookings: at(json, 'cancelled_bookings'),
      remainingSessions: at(json, 'remaining_sessions'),
      retainedPasses: at(retained, 'passes'),
      retainedPayments: at(retained, 'payments'),
      retainedContracts: at(retained, 'contracts'),
    );
  }

  final int bodyPhotos;
  final int inbody;
  final int workoutLogs;
  final int hwChecks;
  final int cancelledBookings;
  final int remainingSessions;
  final int retainedPasses;
  final int retainedPayments;
  final int retainedContracts;

  /// 완료 안내 한 줄. 남은 회차가 있으면 **그 사실을 먼저 말한다** — 회원이 지금 알아야 할
  /// 유일한 행동 가능한 정보이고, 앱에서는 이제 확인할 방법이 없기 때문이다.
  String get completionMessage {
    if (remainingSessions > 0) {
      return '탈퇴가 완료됐어요. 남은 $remainingSessions회의 정산은 센터에 문의해주세요.';
    }
    return '탈퇴가 완료됐어요. 그동안 이용해주셔서 감사합니다.';
  }
}
