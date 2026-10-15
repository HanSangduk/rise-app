import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';

/// center_confirm 화면이 실제로 그려야 하는 상태 — CTA 분기의 단일 기준.
///
/// "member가 null이 아닌가"로 분기하면 거부·요청 후에 CTA 블록이 통째로 사라져
/// 탈출구 없는 화면이 된다. 화면은 항상 이 4가지 중 하나로 확정된다.
enum CenterConfirmStage {
  /// 번호로 회원을 찾음 — "네, OO 본인이에요"가 주 CTA.
  matched,

  /// 가입 요청을 보낸 뒤 — "승인 대기 중"이 주 상태.
  pendingApproval,

  /// "본인이 아니에요"로 매칭을 거부한 뒤.
  declined,

  /// 앱 시작 복원이 연결 여부를 **확인하지 못함**(네트워크 등).
  /// [notFound]와 반드시 구분한다 — "찾지 못했어요"는 서버가 확답한 결론이지만
  /// 이쪽은 물어보지도 못한 상태라, 같은 화면을 보여주면 이미 연결된 회원에게
  /// 가입 요청을 권하게 된다(대표 화면에 같은 사람이 한 줄 더 쌓인다).
  connectionUnknown,

  /// 센터가 가입 요청을 **거절**함(계약 v2.27). 서버가 결론을 내려준 상태이지
  /// "아직 안 봤다"가 아니다 — 대기 화면을 계속 보여주면 사용자는 오지 않을
  /// 승인을 영원히 기다린다. 서버가 거절 시 이름·번호를 지우므로 센터가 다시
  /// 연락할 방법도 없다 — 다음 행동을 사용자에게 넘겨야 한다.
  rejected,

  /// 이 번호로 등록된 회원을 찾지 못함.
  notFound,
}

/// 계정 삭제 고지가 말할 **가입 요청의 흔적** — 서버 `deleteUnlinkedAccount` ⑤가 실제로
/// 지울 문서의 모양(P63, 계약 v2.27·v2.28).
///
/// **`none`(요청 없음)은 만들지 않는다.** 앱은 "요청이 없다"를 알 수 없다 — 코드 인증 직후의
/// 대기실은 GET /v1/me를 부른 적이 없고(`_matchAfterSignIn`은 로컬 기록만 본다), 부른 뒤라도
/// 서버는 `join_request` 키 부재로 "없음"과 "조회 실패"를 구분해 주지 않는다. 그 둘을 "없음"으로
/// 뭉개면 기기를 바꿔 로그인한 사람이 서버에 이름·번호 원본을 둔 채 "인증 계정만 지워져요"를
/// 읽게 된다 — 과소 고지는 거짓이다. 모르면 모른다고("있다면") 말한다.
enum JoinRequestTrace {
  /// 서버에 물어본 적이 없거나 답이 없었다 — 요청이 있을 수도 있다.
  unknown,

  /// 이름·전화번호 원본을 품은 pending 문서가 있다 — **서버 확답만**(requestJoin 성공 응답·
  /// GET /v1/me·콜드스타트 반영). 로컬 기록(joinRequestedAt) 단독은 여기 오지 못한다: 코드
  /// 인증 직후 경로는 서버를 묻지 않으므로, 그 사이 센터가 거절했거나 지운 요청도 "보낸 가입
  /// 요청 (이름·전화번호)"로 열거하게 된다 — 없는 이름을 지운다고 말하는 과잉 고지다.
  pending,

  /// rejected·approved — 센터가 처리하며 이름·번호를 비웠고, 처리 상태와 요청 시각만 남았다.
  /// (approved는 계약 v2.27의 드문 부분 잔여 상태. 그때 회원 레코드는 이 삭제의 범위 밖이다.)
  settled,
}

/// 대기실 스텝퍼(`LobbyProgress`)의 **현재 단계** — 번호 인증 → 가입 요청 → 센터 확인 → 연결.
///
/// stage([CenterConfirmStage])와 1:1이 아니다: matched(이름 확인이 본체)·rejected(✗ 스텝퍼는
/// 징벌적으로 읽힌다)·connectionUnknown(단계를 모른다)은 스텝퍼를 그리지 않으므로 `null`이다
/// ([AuthState.lobbyStep]).
enum LobbyStep {
  /// 다음 할 일이 "가입 요청" — notFound·declined. 스텝퍼가 CTA를 설명한다.
  requested,

  /// 요청을 보냈고 센터 확인을 기다린다 — pendingApproval.
  waiting,

  /// 승인됐는데 인덱스 쓰기만 실패한 `approved` 잔여(계약 v2.27) — 연결이 진행 중이다.
  connecting,
}

/// 로그인 플로우 UI State — freezed 미사용(회원 앱 컨벤션: freezed는 DTO 전용).
/// 3개 화면(전화번호/인증번호/센터확인)이 공유.
class AuthState {
  const AuthState({
    this.phone = '',
    this.code = '',
    this.submitting = false,
    this.resending = false,
    this.checkingConnection = false,
    this.autoChecking = false,
    this.connectionUnknown = false,
    this.error,
    this.match,
    this.trainerName,
    this.matchDeclined = false,
    this.joinRequestedAt,
    this.serverJoinStatus,
    this.joinCenterId = '',
    this.centerId = '',
    this.lastCheckedAt,
    this.lastCheckFailedAt,
    this.verificationId,
    this.resendToken,
  });

  final String phone;
  final String code;

  /// 주 액션(발송/확인/본인확인/가입요청) 진행 중.
  final bool submitting;

  /// 인증번호 **재전송** 진행 중 — [submitting]과 분리해야 재전송 중에
  /// 확인 버튼이 "확인 중…"이라고 거짓말하지 않는다.
  final bool resending;

  /// "연결됐는지 확인"(GET /v1/me 재조회) 진행 중 — 같은 이유로 [submitting]과 분리.
  /// 연타 방지는 [busy]가 겸한다.
  final bool checkingConnection;

  /// 앱 시작 복원이 연결 여부를 확인하지 못한 채 이 화면에 세웠다(네트워크 등).
  /// "미연결"로 단정하지 않기 위한 플래그 — 재확인이 정상 경로다.
  /// 서버가 확답을 주는 순간(연결됨/아직) 곧바로 내려간다.
  final bool connectionUnknown;

  final Failure? error;
  final JoinMatch? match;

  /// Firebase codeSent가 준 검증 세션 — 코드 확인 시 필수.
  final String? verificationId;

  /// 재전송 시 forceResendingToken으로 전달(Android 전용, iOS는 null).
  final int? resendToken;

  /// GET /v1/staff로 보강한 표시용 트레이너 이름(best-effort).
  final String? trainerName;

  /// "본인이 아니에요"로 매칭을 거부한 상태 — 매칭 카드 대신 안내 카드를 보여준다.
  final bool matchDeclined;

  /// 가입 요청(POST /v1/join/request) 성공 시각 — center_confirm 화면을
  /// "승인 대기 중" 카드로 고정하고 30초 뒤에야 "다시 요청"을 허용한다(중복 제출 방지).
  /// 로컬에도 영속되어(JoinRequestStore) 앱 재실행 시 이 상태로 복귀한다.
  final DateTime? joinRequestedAt;

  /// 서버가 들고 있는 가입 요청 상태(계약 v2.27): `pending` | `rejected` | `approved`.
  /// null = 서버에 요청이 없거나 아직 못 물어봤다. [centerConfirmStage] 주석 참조.
  final String? serverJoinStatus;

  /// 가입 요청을 보낸 센터 — 대기실 센터 카드가 **어느 센터의** 연락처·수업 시간을 보여줄지.
  ///
  /// 출처 우선순위: 서버(`GET /v1/me.join_request.center_id`, v2.34 / 409 `center_id`) →
  /// 로컬 기록([JoinRequestRecord.centerId], 구서버 폴백) → ''(기본 센터, 종전 동작).
  /// 한 칸으로 합쳐 두되 **비어 있지 않은 서버 값만 덮어쓴다** — 서버가 키를 안 주는
  /// 구서버·조회 실패에서 로컬 폴백이 지워지면 2호점 신청자가 1호점 연락처를 본다.
  final String joinCenterId;

  /// Principal 센터(`GET /v1/me.center_id`). 미연결 uid는 기본 센터 폴백이라 이 값은 "내 센터"가
  /// 아니라 "`/v1/staff`가 돌려주는 목록의 센터"다 — 코치 줄은 [joinCenterId]가 비었거나 이 값과
  /// 같을 때만 그린다(다른 센터 신청자에게 기본 센터 코치를 소개하면 남의 센터 쇼룸). 아직
  /// `/v1/me`를 부른 적 없으면 ''.
  final String centerId;

  /// 마지막으로 **성공한** 연결 확인(GET /v1/me가 답한 시각 — connected/notYet). 확인 상태 줄의
  /// "마지막 확인 12:14"가 이 값이다. 실패한 호출의 시각을 여기 넣으면 그 문장이 거짓이 된다.
  final DateTime? lastCheckedAt;

  /// 마지막으로 **실패한** 연결 확인(네트워크 등). [lastCheckedAt]보다 뒤면 "12:14 확인 못 함".
  final DateTime? lastCheckFailedAt;

  /// **자동 확인 틱**이 도는 중(P72 C10). [checkingConnection]과 갈라 둔 이유는 [busy]다:
  /// 종전엔 자동 틱도 `checkingConnection`을 켰고, 그게 `busy`를 통해 화면의 **모든** 컨트롤을
  /// 동시에 잠갔다 — 30초마다 "번호 다시 인증하기"(모든 stage의 유일한 탈출구)·"본인이
  /// 아니에요"·"계정 삭제"가 함께 회색이 됐다. 사용자가 시작한 적 없는 동작이고, 느린 회선에선
  /// 그 잠금이 5~10초씩 이어져 "확인 중"이 아니라 "얼었다"로 읽힌다.
  ///
  /// 뷰모델의 재진입 방지는 [anyCheckInFlight]가 겸한다 — 잠그는 범위만 좁혔지 같은 조회가
  /// 두 번 나가지는 않는다.
  final bool autoChecking;

  /// 연결 확인이 수동이든 자동이든 날아가는 중 — 뷰모델의 중복 호출 가드가 이것을 본다.
  bool get anyCheckInFlight => checkingConnection || autoChecking;

  /// 발송/확인/재전송/**수동** 연결확인 중 — 화면 컨트롤을 함께 잠그는 기준.
  /// 자동 틱([autoChecking])은 여기 들어오지 않는다.
  bool get busy => submitting || resending || checkingConnection;

  /// 대기 화면에 "다시 요청" 버튼을 둘지(P69 C2).
  ///
  /// 서버가 pending을 **확답**한 상태에서 재요청은 100% 409다 — 그 버튼은 함정이다. 로컬 기록만
  /// 있는 `unknown`(코드 인증 직후·서버가 요청을 안 실어 준 경우)에서만 열어 둔다. 눌러서 409를
  /// 받으면 뷰모델이 pending으로 승격하므로 막다른 길이 아니다. rejected의 재요청은 CTA 블록의
  /// 몫이라 여기 포함하지 않는다.
  bool get canRetryJoinRequest =>
      centerConfirmStage == CenterConfirmStage.pendingApproval &&
      joinRequestTrace == JoinRequestTrace.unknown;

  /// 스텝퍼의 현재 단계 — 그리지 않는 stage는 null([LobbyStep] 주석).
  LobbyStep? get lobbyStep => switch (centerConfirmStage) {
        CenterConfirmStage.matched ||
        CenterConfirmStage.rejected ||
        CenterConfirmStage.connectionUnknown =>
          null,
        // approved 잔여(계약 v2.27)는 어느 stage에 있든 "연결 중" — 승인은 끝났고 인덱스만 남았다.
        _ when serverJoinStatus == 'approved' => LobbyStep.connecting,
        CenterConfirmStage.pendingApproval => LobbyStep.waiting,
        CenterConfirmStage.declined || CenterConfirmStage.notFound => LobbyStep.requested,
      };

  /// center_confirm 화면 분기. 매칭이 살아 있으면 그게 가장 빠른 경로이므로
  /// 승인 대기보다 우선한다(대기 카드는 아래 슬롯에 그대로 함께 노출).
  ///
  /// [CenterConfirmStage.connectionUnknown]은 "아는 게 없을 때"의 폴백이라
  /// 실제 근거가 있는 세 분기보다 뒤에 온다 — 대기 기록이 있으면 대기 카드가
  /// 이기고(그 카드에 재확인 버튼이 있다), 아무 근거도 없을 때만 재확인 화면이 뜬다.
  /// 화면 전체를 정하는 **단일 판별자**(P55). 제목·부제·본문·CTA가 모두 이것 하나를 본다.
  ///
  /// 종전엔 화면이 판별자를 다섯 개 쓰다가 "찾지 못했어요"와 "승인 대기 중"을
  /// 동시에 그렸다. 계산을 여기 한 곳에 모으면 그 조합이 만들어지지 않는다.
  ///
  /// **서버 상태가 로컬 기록을 이긴다**(계약 v2.27). 종전엔 `joinRequestedAt`(기기
  /// SharedPreferences)만 봤고, 기기를 바꾸면 근거가 사라져 "요청한 적 없음"으로
  /// 떨어져 사용자가 같은 요청을 또 보냈다 — 그 중복이 대표 어드민을 죽이던 재료다.
  CenterConfirmStage get centerConfirmStage {
    if (match?.member != null) return CenterConfirmStage.matched;
    if (serverJoinStatus == 'rejected') return CenterConfirmStage.rejected;
    // 서버가 pending을 들고 있으면 로컬 기록이 없어도 대기 화면이다.
    if (serverJoinStatus == 'pending' || joinRequestedAt != null) {
      return CenterConfirmStage.pendingApproval;
    }
    if (matchDeclined) return CenterConfirmStage.declined;
    if (connectionUnknown) return CenterConfirmStage.connectionUnknown;
    return CenterConfirmStage.notFound;
  }

  /// 삭제 고지의 **단일 판별자**(P63) — stage가 아니라 요청 상태로 판정한다. stage는 화면을
  /// 정하는 값이라 matched·connectionUnknown 같은 "요청과 무관한" 분기를 갖고, 그 분기에서
  /// 요청 유무를 읽어내면 없는 사실을 지어내게 된다. 판정 순서는 [centerConfirmStage]와 같다
  /// (서버 상태가 로컬 기록을 이긴다).
  ///
  /// [centerConfirmStage]와 달리 **로컬 기록만으로는 pending을 단정하지 않는다**. 화면은 로컬
  /// 기록으로 대기 카드를 세워도 된다(재확인 버튼이 있고, 틀려도 손해가 없다) — 그러나 고지는
  /// 지워질 문서의 모양을 말하는 자리라, 서버가 확답한 적 없는 pending은 unknown("있다면")이다.
  JoinRequestTrace get joinRequestTrace {
    if (serverJoinStatus == 'rejected' || serverJoinStatus == 'approved') {
      return JoinRequestTrace.settled;
    }
    if (serverJoinStatus == 'pending') return JoinRequestTrace.pending;
    return JoinRequestTrace.unknown;
  }

  AuthState copyWith({
    String? phone,
    String? code,
    bool? submitting,
    bool? resending,
    bool? checkingConnection,
    bool? autoChecking,
    bool? connectionUnknown,
    Failure? error,
    bool clearError = false,
    JoinMatch? match,
    bool clearMatch = false,
    String? trainerName,
    bool? matchDeclined,
    DateTime? joinRequestedAt,
    String? serverJoinStatus,
    bool clearServerJoinStatus = false,
    String? joinCenterId,
    String? centerId,
    DateTime? lastCheckedAt,
    DateTime? lastCheckFailedAt,
    String? verificationId,
    int? resendToken,
    bool clearVerification = false,
  }) {
    return AuthState(
      phone: phone ?? this.phone,
      code: code ?? this.code,
      submitting: submitting ?? this.submitting,
      resending: resending ?? this.resending,
      checkingConnection: checkingConnection ?? this.checkingConnection,
      autoChecking: autoChecking ?? this.autoChecking,
      connectionUnknown: connectionUnknown ?? this.connectionUnknown,
      error: clearError ? null : (error ?? this.error),
      // `match ?? this.match`만으로는 null 클리어가 불가능(본인 아님 거부가 무반응이 되는 버그)
      // → clearError와 동일한 명시적 플래그 패턴.
      match: clearMatch ? null : (match ?? this.match),
      trainerName: trainerName ?? this.trainerName,
      matchDeclined: matchDeclined ?? this.matchDeclined,
      joinRequestedAt: joinRequestedAt ?? this.joinRequestedAt,
      // 서버가 "요청 없음"(키 부재 → null)이라 답했을 때 옛 'pending'이 남으면 삭제 고지가
      // 지운 적 없는 요청을 단정한다 — clearMatch와 같은 명시적 플래그로만 지운다.
      serverJoinStatus: clearServerJoinStatus ? null : (serverJoinStatus ?? this.serverJoinStatus),
      // 빈 문자열은 "모른다"이지 "지운다"가 아니다 — 서버가 키를 안 주는 응답(구서버·요청 없음)이
      // 로컬 폴백(기록의 센터)을 덮어쓰지 않게 비어 있지 않은 값만 받는다.
      joinCenterId: (joinCenterId == null || joinCenterId.isEmpty) ? this.joinCenterId : joinCenterId,
      centerId: (centerId == null || centerId.isEmpty) ? this.centerId : centerId,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastCheckFailedAt: lastCheckFailedAt ?? this.lastCheckFailedAt,
      // verificationId와 resendToken은 codeSent 한 번의 산물이라 항상 한 쌍으로 무효화한다
      // (번호가 바뀌면 둘 다 옛 번호의 것 — 하나만 지우면 반쪽짜리 세션이 남는다).
      verificationId: clearVerification ? null : (verificationId ?? this.verificationId),
      resendToken: clearVerification ? null : (resendToken ?? this.resendToken),
    );
  }
}
