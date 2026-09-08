/// 회원탈퇴(API계약 v2.11) 도메인 — 확인 화면이 고지할 내용과 서버 응답 모델.
///
/// 문구를 위젯이 아니라 여기 모은 이유: 이 목록은 **서버가 실제로 하는 일과 한 줄씩 대응**해야
/// 한다. 서버는 지우지 않는데 화면이 "지웁니다"라고 말하는 순간, 그건 UI 문구 실수가 아니라
/// 개인정보 처리에 대한 거짓 고지다. 한 자리에 모아 두면 서버 계약이 바뀔 때 같이 움직인다
/// (P14 인쇄 안내문·P15 삭제 확인 문구가 서버와 어긋나 있던 것과 같은 종류의 결함 예방).
library;

import 'package:rise_member/features/auth/presentation/auth_state.dart' show JoinRequestTrace;

/// 이 화면이 다루는 계정의 종류 — **무엇이 지워지는지가 달라진다**(P56 A1).
///
/// 서버 `DeleteMyAccount`는 principal의 `member_id` 유무로 두 경로를 탄다(계약 v2.27):
/// 회원 레코드가 있으면 7단계 파기·가명화, 없으면 축소판(`deleteUnlinkedAccount` —
/// Firebase 계정·가입 요청·로그인 매핑만). 앱은 어느 경로가 돌지 **호출 전에** 알고
/// 그에 맞는 고지를 해야 한다. 대기실 계정에 "체형사진·인바디·수업 기록이 모두 삭제되고
/// 회원권 내역은 5년 보관돼요"라고 말하면 그 사람에게는 전부 없는 것에 대한 고지다.
enum AccountDeletionScope {
  /// 연결된 회원(셸 안 마이 탭) — 회원 데이터 파기 + 법정 보존 고지.
  member,

  /// 대기실 계정 — 서버가 미연결을 **확답**한 상태(`MemberNotLinkedFailure` /
  /// 매칭 없음 / 본인 아님 / 대기·거절). 지워지는 것은 인증 계정과 보낸 가입 요청뿐이다.
  /// matched(번호로 회원을 찾았고 이름 확인 전)는 **여기 속하지 않는다** — 아래 [unknown].
  unlinked,

  /// 대기실인데 서버가 어느 경로를 돌지 **앱이 모름**. 둘이 있다([AccountDeletionUnknownReason]):
  /// - 연결 여부를 확인하지 못함(`CenterConfirmStage.connectionUnknown`) — 이미 연결된
  ///   회원이 네트워크 실패로 대기실에 선 경우일 수 있다.
  /// - 번호로 회원을 찾음(`CenterConfirmStage.matched`) — 이미 연결됐던 회원이 기기 변경·
  ///   재인증으로 다시 여기 선 경우일 수 있다(principal에 member_id가 남아 있다).
  /// 어느 쪽이든 그때 삭제하면 서버는 회원 경로(전체 파기 + 5년 보존)를 돈다. 그래서
  /// **최악(회원) 쪽 고지를 그대로** 보여주고 그 사실을 배너로 밝힌다. 과소 고지는 거짓이지만
  /// 과다 고지는 거짓이 아니다.
  unknown,
}

/// [AccountDeletionScope.unknown]에서 **왜 모르는지** — 배너 첫 줄이 이것으로 갈린다.
/// 고지 본문(회원 목록·보존 카드)은 둘 다 같다. 사실이 다른 건 첫 줄뿐이다.
enum AccountDeletionUnknownReason {
  /// GET /v1/me가 실패해 연결 여부를 물어보지 못했다.
  connectionCheckFailed,

  /// 번호로 등록된 회원을 찾았고 이름 확인 전 — 이 계정에 이미 연결돼 있었는지 앱은 모른다.
  phoneMatched,
}

/// unknown scope 배너 문장. "보낸 가입 요청"은 어느 이유에서든 단정하지 않는다("있다면") —
/// 연결 여부를 모른다 = 가입 요청 유무도 모른다(P63).
String connectionUnknownBannerText(AccountDeletionUnknownReason reason) => switch (reason) {
      AccountDeletionUnknownReason.connectionCheckFailed => '연결 상태를 확인하지 못했어요.\n'
          '이 번호가 이미 센터에 연결된 회원이라면 아래 내용대로 모두 삭제되고, '
          '아직 연결 전이라면 로그인 계정과, 보낸 가입 요청이 있다면 그것만 삭제돼요.',
      AccountDeletionUnknownReason.phoneMatched => '이 번호로 등록된 회원이 있어요 — '
          '이미 이 계정에 연결돼 있었다면 아래 내용대로 모두 삭제돼요.\n'
          '아직 연결 전이라면 로그인 계정과, 보낸 가입 요청이 있다면 그것만 삭제돼요.',
    };

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

/// 대기실(미연결) 계정을 지울 때 **파기**되는 것 — 서버 `deleteUnlinkedAccount`의 세 단계
/// (② Firebase 계정 → ⑤ 가입 요청 → ⑦ 로그인 매핑)와 한 줄씩 대응한다(계약 v2.27).
/// 회원 레코드가 없으므로 [withdrawalPurgedItems]의 나머지(사진·기록·예약)는 애초에 없다.
///
/// 가입 요청 행은 [JoinRequestTrace]로 갈린다(P63). ⑤는 그 uid의 요청 문서를 **상태 무관
/// 전부** 지우는데, 문서의 모양이 상태마다 다르다 — pending은 이름·전화번호 원본을 품고,
/// rejected·approved는 센터가 처리하며 이미 비워져 {상태, 요청 시각}만 남았다(v2.28). 거절된
/// 계정에 "이름·전화번호를 지운다"고 쓰면 지워질 이름이 있는 것처럼 말하는 셈이고, 물어본 적이
/// 없는 계정에 "보낸 가입 요청"을 단정하면 없는 것을 지운다고 말하는 셈이다. 모르면 "있다면".
///
/// 한계: unknown은 과소·과다 어느 쪽도 단정하지 않으므로, 실제로 무엇을 지웠는지는 완료 안내가
/// 서버의 `purged.join_requests` 건수로 말한다([AccountDeletionSummary.unlinkedCompletionMessage]).
List<String> unlinkedDeletionPurgedItems(JoinRequestTrace trace) => [
      switch (trace) {
        JoinRequestTrace.unknown => '보낸 가입 요청이 있다면 그 요청 (이름·전화번호)',
        JoinRequestTrace.pending => '보낸 가입 요청 (이름·전화번호)',
        JoinRequestTrace.settled => '가입 요청 기록 (처리 상태·요청 시각)',
      },
      '앱 로그인 계정 (인증한 전화번호)',
    ];

/// 대기실 계정 삭제 화면 상단의 경고 상자 — 회원 문구의 "이전 기록은 복구되지 않아요"는 기록이
/// 있는 사람에게 하는 말이라 쓰지 않는다. 재인증 뒤 무엇부터 다시 시작하는지는 trace마다 다르다.
/// "이 화면부터"처럼 읽는 자리를 가리키는 말은 쓰지 않는다 — 읽는 자리는 삭제 화면이다.
String unlinkedDeletionWarning(JoinRequestTrace trace) => switch (trace) {
      JoinRequestTrace.unknown => '삭제하면 되돌릴 수 없어요.\n'
          '보낸 가입 요청이 있다면 함께 지워지고, 같은 번호로 다시 인증하면 센터 연결 화면부터 다시 시작해요.',
      JoinRequestTrace.pending => '삭제하면 되돌릴 수 없어요.\n'
          '같은 번호로 다시 인증하면 가입 요청부터 다시 보내야 해요.',
      JoinRequestTrace.settled => '삭제하면 되돌릴 수 없어요.\n'
          '가입 요청 기록도 함께 지워지고, 같은 번호로 다시 인증하면 가입 요청을 새로 보내야 해요.',
    };

/// 마지막 재확인 다이얼로그 본문 — 여기서 처음 알리는 사실은 없다(화면이 이미 말했다).
/// 지워지는 것만 trace대로 다시 말한다.
String unlinkedDeletionConfirmText(JoinRequestTrace trace) => switch (trace) {
      JoinRequestTrace.unknown => '인증 계정을 삭제해요. 보낸 가입 요청이 있다면 함께 삭제돼요. 되돌릴 수 없어요.\n\n'
          '같은 번호로 다시 인증하면 센터 연결 화면부터 다시 시작해요.',
      JoinRequestTrace.pending => '보낸 가입 요청과 인증 계정을 삭제해요. 되돌릴 수 없어요.\n\n'
          '같은 번호로 다시 인증하면 가입 요청부터 다시 보내야 해요.',
      JoinRequestTrace.settled => '가입 요청 기록과 인증 계정을 삭제해요. 되돌릴 수 없어요.\n\n'
          '같은 번호로 다시 인증하면 가입 요청을 새로 보내야 해요.',
    };

/// 대기실 계정 삭제가 **건드리지 않는 것**. 5년 보존 목록([withdrawalRetainedItems])은
/// 회원권·결제·계약이 있어야 생기는 기록이라 이 계정에는 없다 — 그 카드를 그대로 보여주면
/// 없는 기록을 보관한다고 말하는 셈이다. 대신 실제로 남을 수 있는 것 하나를 밝힌다:
/// 센터 데스크가 따로 등록해 둔 회원 정보는 앱 계정과 별개의 자료라 이 삭제의 범위 밖이다
/// (서버는 uid 키의 자료만 지운다 — 회원 문서는 대표가 데스크에서 만든 것이고 이 계정에
/// 연결된 적이 없다). 지우려면 센터에 직접 요청해야 한다는 다음 행동까지 말한다.
const unlinkedDeletionRetentionNote =
    '센터 데스크에 따로 등록된 회원 정보(회원 카드 등)는 앱 계정과 별개라 여기서 지워지지 않아요 — '
    '삭제를 원하면 센터에 직접 요청해주세요.';

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
///
/// **한 가지 예외를 숨기지 않는다**(P56에서 교정). 종전 문구는 "보존되는 기록에서도 이름과
/// 전화번호는 함께 지워져요"라고 단정했는데, **서명한 계약서는 예외다** — P53 결정 3이
/// 분석 끝에 현행 유지로 결론냈다: 봉인이 `sha256(version + canonical_json(vars))`라
/// 이름 한 글자만 바꿔도 **서명 계약의 사후 변조 검출이 영구히 불가능해지고**, 당사자가
/// 빈칸인 처분문서는 5년 보존의 목적 자체를 잃는다. 즉 못 지우는 게 아니라 **지우면 안 되는
/// 자리**다. 그 사실을 화면이 말하지 않으면 이 파일 헤더가 경고한 바로 그 거짓 고지가 된다.
const withdrawalRetentionNote =
    '이용 내역·결제 기록에서는 이름과 전화번호가 지워져요 — 금액·회차·날짜만 남아요. '
    '다만 서명한 계약서는 문서 그대로 5년간 보관돼요(법정 보존). 그 안의 이름·연락처는 '
    '위·변조를 확인하기 위한 것이라 지울 수 없어요.';

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
    this.joinRequests = 0,
    this.memberId = '',
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
      // v2.27 미연결 응답의 두 칸(P63). 키 없음(구서버) → 0 / '' — 던지지 않는다.
      joinRequests: at(purged, 'join_requests'),
      memberId: json['member_id'] as String? ?? '',
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

  /// 서버가 실제로 지운 가입 요청 문서 수(v2.27 `purged.join_requests`) — 미연결 완료 안내의 근거.
  final int joinRequests;

  /// 서버가 **어느 경로를 돌았나**(v2.27): 회원 경로면 회원 id, 미연결 경로면 빈 문자열.
  /// 연결 여부를 모른 채 삭제한 계정([AccountDeletionScope.unknown])의 완료 안내가 이 값으로
  /// 회원 문구와 미연결 문구를 고른다 — 앱이 몰랐던 사실을 서버가 답으로 알려준다.
  final String memberId;

  /// 서버 응답이 미연결 경로였다(`member_id` 빈 값). 구서버·빈 바디(`{}`)도 여기 떨어지므로,
  /// 세션에 회원 id가 있던 회원 scope는 이 값을 보지 않고 [completionMessage]를 쓴다.
  bool get ranUnlinkedPath => memberId.isEmpty;

  /// 완료 안내 한 줄. 남은 회차가 있으면 **그 사실을 먼저 말한다** — 회원이 지금 알아야 할
  /// 유일한 행동 가능한 정보이고, 앱에서는 이제 확인할 방법이 없기 때문이다.
  String get completionMessage {
    if (remainingSessions > 0) {
      return '탈퇴가 완료됐어요. 남은 $remainingSessions회의 정산은 센터에 문의해주세요.';
    }
    return '탈퇴가 완료됐어요. 그동안 이용해주셔서 감사합니다.';
  }

  /// 미연결 경로 삭제의 완료 안내 — "탈퇴"라 쓰지 않는다. 회원이 된 적이 없는 사람에게
  /// "이용해주셔서 감사합니다"는 빈말이고, 서버가 실제로 한 일을 그대로 말하는 편이 §36 삭제
  /// 요구에 대한 답이다. **"보낸 가입 요청"은 서버가 실제로 지웠을 때만 말한다**(P63) —
  /// 사전 고지는 "있다면"으로 헤지했더라도 완료 안내는 건수를 알고 있으므로 단정할 수 있다.
  ///
  /// [trace]가 settled면 지운 것은 이름·번호가 이미 비워진 껍데기다 — 사전 고지가 '가입 요청
  /// 기록'이라 불렀던 것을 완료 안내가 '보낸 가입 요청'으로 바꿔 부르면 한 화면이 두 말을 한다.
  /// (settled 뒤 재요청으로 pending이 하나 더 있던 경우는 앱이 알 수 없다 — 재요청 성공은
  /// serverJoinStatus를 pending으로 세우므로 trace가 settled인 채 여기 오지 않는다.)
  String unlinkedCompletionMessage(JoinRequestTrace trace) {
    if (joinRequests <= 0) return '계정을 삭제했어요.';
    return trace == JoinRequestTrace.settled
        ? '계정과 가입 요청 기록을 삭제했어요.'
        : '계정과 보낸 가입 요청을 삭제했어요.';
  }
}
