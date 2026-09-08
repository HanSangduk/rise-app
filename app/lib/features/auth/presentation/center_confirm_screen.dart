import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:rise_member/features/auth/presentation/center_contact_provider.dart';
import 'package:rise_member/features/auth/presentation/widgets/lobby_auto_check.dart';
import 'package:rise_member/features/auth/presentation/widgets/lobby_progress.dart';
import 'package:rise_member/features/my/presentation/widgets/center_coaches_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rise_member/core/widgets/rise_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/config/legal_links.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/features/auth/domain/auth_models.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/legal_document_link.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/booking/presentation/widgets/trainer_profile_sheet.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/presentation/account_deletion_screen.dart';

/// 로그인 3단계 — 센터 자동 매칭 + 이름확인 1탭 (목업 step-center, P48).
/// "네, OO 본인이에요"가 핵심 CTA: 오타 번호로 남의 계정에 잘못 연결되는 걸
/// 막는 유일한 확인 장치이므로 이름을 크게 강조해서 보여준다.
///
/// CTA는 `member != null`이 아니라 [CenterConfirmStage]로 분기한다. 예전엔 CTA
/// 블록 전체가 member 게이트 안에 있어서, "본인이 아니에요"를 누르거나 가입 요청을
/// 보내는 순간 버튼과 링크가 통째로 사라졌다 — 이 화면은 AppBar도 뒤로가기도 없고
/// 라우터 스택이 1장이라(전부 context.go) 시스템 백은 앱을 종료한다. 즉 안내 문구만
/// 남은 막다른 길이었다. 그래서 **모든 상태에서 "번호 다시 인증하기"가 상시 노출**된다.
class CenterConfirmScreen extends ConsumerWidget {
  const CenterConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authViewModelProvider);
    final member = state.match?.member;
    final stage = state.centerConfirmStage;
    // 담당 코치 아바타·직함(P05) — 인증 단계에서 이미 로드된 스태프 캐시를 재사용
    // (best-effort: 미로드/실패면 기존처럼 이름만 표시).
    final trainerId = member?.trainerId;
    final trainer = trainerId == null ? null : ref.watch(staffMapProvider).value?[trainerId];
    // 대기실이 보여줄 센터(P69 H3) — 서버 `join_request.center_id` → 로컬 기록 → 기본 센터(null).
    // `AuthState.joinCenterId`가 그 우선순위를 이미 합쳐 들고 있다.
    final lobbyCenterId = state.joinCenterId.isEmpty ? null : state.joinCenterId;
    final autoEnabled = ref.watch(lobbyAutoCheckIntervalProvider) != null;
    // 쇼룸 요소(코치 줄·미리보기)는 요청 전후의 세 단계에서만 — rejected 직후의 쇼룸은 어긋난 톤이고,
    // matched는 이름 확인이 본체, connectionUnknown은 이미 연결된 회원일 수 있다(plan B §2).
    final showroom = switch (stage) {
      CenterConfirmStage.pendingApproval ||
      CenterConfirmStage.notFound ||
      CenterConfirmStage.declined =>
        true,
      _ => false,
    };
    // 코치 줄은 `/v1/staff`가 돌려주는 센터(Principal = me.center_id)와 요청 센터가 같을 때만 —
    // 미연결 uid의 Principal은 기본 센터 폴백이라, 2호점 신청자에게 1호점 코치를 소개하면 남의 센터다.
    final coachRowAllowed =
        showroom && (state.joinCenterId.isEmpty || state.joinCenterId == state.centerId);

    // 이 화면도 라우터 스택 1장 — 막지 않으면 시스템 백이 앱을 끈다. 백은 화면 내
    // 탈출구("번호 다시 인증하기")와 같은 목적지로 보내되, 인증을 통째로
    // 되돌리는 동작이라 오탭 한 번에 실행되지 않게 한 번 되묻는다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmRestart(context, ref);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // **스크롤되는 세로 배치**(P56 A1·B5). 종전엔 고정 `Column`이었다 — 320×568(가장
        // 좁은 현역 폰)에서 대기 카드 + 연락 카드 + CTA + 안내문만으로 이미 빠듯했고,
        // 하단 링크 한 줄을 더하자 34px가 넘쳤다. 글자 배율 1.35에서는 그 전부터 넘쳤을
        // 자리다. `Spacer`가 남는 높이를 먹으려면 Column이 뷰포트만큼은 커야 하므로
        // `ConstrainedBox(minHeight) + IntrinsicHeight`로 "최소 뷰포트, 넘치면 스크롤"을
        // 만든다(Flutter의 표준 관용구). 내용이 뷰포트보다 짧을 때의 그림은 종전과 같다.
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 34, 20, 34),
              child: ConstrainedBox(
                // 34+34 = 세로 패딩만큼을 뺀 높이가 Column의 하한이다.
                constraints: BoxConstraints(minHeight: math.max(0, viewport.maxHeight - 68)),
                child: IntrinsicHeight(
                  child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // **제목·부제·본문을 `stage` 하나가 정한다**(P55).
                //
                // 종전엔 판별자가 다섯이었다: 제목은 고정 문자열, 부제는 `stage`,
                // 상단 카드는 `member != null`/`matchDeclined`/`connectionUnknown`의
                // else 체인, 하단 카드는 `joinRequestedAt`. 그래서 **요청 대기 중**일 때
                // else 폴백인 `_NotFoundCard`("아래에서 센터를 찾아 가입 요청해보세요")가
                // 대기 카드와 **동시에** 그려졌다 — 람이 실사용자 화면으로 가져온 그 모순이다.
                // 게다가 그 문구가 가리키는 '아래' 카드는 하필 대기 중일 때만 사라진다.
                // 판별자를 하나로 줄이면 그 조합 자체가 만들어지지 않는다.
                Text(
                  switch (stage) {
                    CenterConfirmStage.matched => '센터를 찾았어요',
                    CenterConfirmStage.pendingApproval => '가입 요청을 보냈어요',
                    // "취소"라 쓰지 않는다 — 취소할 연결이 없었다. 이 단계는 "본인이 아니에요"로
                    // 연결을 **하지 않은** 것이고, "취소했어요"는 끊긴 계정으로 읽힌다(P63).
                    CenterConfirmStage.declined => '이 번호로는 연결하지 않았어요',
                    CenterConfirmStage.connectionUnknown => '연결 상태를 확인하지 못했어요',
                    // "센터 선택"이라 쓰지 않는다 — 고를 목록이 없다. 화면 이름이
                    // 기능을 앞지른 것이 이 화면 문제의 절반이었다.
                    CenterConfirmStage.rejected => '센터에서 연결하지 않았어요',
                    CenterConfirmStage.notFound => '아직 연결된 센터가 없어요',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                // **제목+부제는 사실만**(P63) — 서버가 아는 만큼만 말한다. 원인 가설("번호가
                // 다르거나 등록 전")은 연락 카드 힌트 한 자리에서만 헤지해서 말한다. 종전 부제
                // "달라서 자동 연결이 안 됐어요"는 FindMemberByPhone이 빈 값을 냈다는 사실을
                // 원인으로 단정한 문장이었다.
                Text(
                  switch (stage) {
                    CenterConfirmStage.matched => '전화번호로 등록된 회원 정보를 확인했어요',
                    // "자동으로"라 쓰지 않는다(P69 C1) — 자동 확인은 확인 상태 줄이 자기 자리에서
                    // 말하고, 백그라운드 승인은 앱을 다시 열 때 안다. 부제는 서버가 아는 사실만.
                    CenterConfirmStage.pendingApproval => '센터가 승인하면 연결돼요',
                    CenterConfirmStage.declined => '이 번호로 찾은 회원이 본인이 아니라고 하셨어요',
                    CenterConfirmStage.connectionUnknown => '네트워크가 돌아오면 다시 확인해주세요',
                    // "다른 센터로 보낸 요청"이라 쓰지 않는다 — v1은 단일 센터라 그 선택지가 없다
                    // (계약 v2.27 center_id 규약). 성립하는 가설은 번호 하나뿐이다.
                    CenterConfirmStage.rejected => '요청에 적힌 번호가 등록된 번호와 다를 수 있어요',
                    CenterConfirmStage.notFound => '인증한 번호로 등록된 회원을 찾지 못했어요',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                ...switch (stage) {
                  // 매칭됨 — 이름 확인이 본체. "제가 아니에요"(가입 요청)는 부차 경로로 남긴다.
                  CenterConfirmStage.matched => [
                    _MatchedCenterCard(
                      memberName: member!.name,
                      trainerName: state.trainerName,
                      trainer: trainer,
                    ),
                    const SizedBox(height: 10),
                    _NotMeCard(
                      onTap: state.busy ? null : () => _showJoinRequestSheet(context),
                    ),
                  ],
                  // 요청 대기 — **빈 상태와 완전히 분리된 화면**이다. "찾지 못했어요"
                  // 경고를 여기 띄우지 않는다(그게 종전의 모순이었다).
                  // 종전 `_PendingApprovalCard`("승인됐는지 아래 버튼으로 확인할 수 있어요" + 두
                  // 버튼)는 없앴다(P69 H2) — 그 정보는 스텝퍼(어디까지 갔나)와 확인 상태 줄(언제
                  // 확인했나·지금 확인)이 흡수한다. "다시 요청"은 서버가 pending을 확답하지 않은
                  // 상태에서만 남는다([AuthState.canRetryJoinRequest] — 확답 뒤 재요청은 100% 409).
                  CenterConfirmStage.pendingApproval => [
                    LobbyAutoCheck(onConnected: () => _goHome(context)),
                    LobbyProgress(
                      step: state.lobbyStep ?? LobbyStep.waiting,
                      availableWidth: viewport.maxWidth - 40,
                      requestedAt: state.joinRequestedAt,
                      requestConfirmed: state.joinRequestTrace == JoinRequestTrace.pending,
                    ),
                    const SizedBox(height: 12),
                    CheckStatusLine(
                      lastCheckedAt: state.lastCheckedAt,
                      lastCheckFailedAt: state.lastCheckFailedAt,
                      checking: state.checkingConnection,
                      busy: state.busy,
                      onCheck: () => _check(context, ref),
                      autoEnabled: autoEnabled,
                    ),
                    if (state.canRetryJoinRequest) ...[
                      const SizedBox(height: 8),
                      _RetryJoinButton(
                        // 재요청 시각이 바뀌면 카운트다운을 새로 시작하도록 상태를 재생성.
                        key: ValueKey(state.joinRequestedAt),
                        requestedAt: state.joinRequestedAt ?? DateTime.now(),
                        busy: state.busy,
                        onRetry: () => _showJoinRequestSheet(context),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _CenterCard(hint: _Hints.pending, centerId: lobbyCenterId),
                  ],
                  // 연결 여부를 모르는 상태에서는 가입 요청을 권하지 않는다 — 이미
                  // 연결된 회원일 수 있고, 그 요청은 대표 화면에 중복 줄을 만든다.
                  // 자동 확인은 여기서도 돈다(앱 재개·네트워크 복귀가 곧 재확인이다).
                  CenterConfirmStage.connectionUnknown => [
                    LobbyAutoCheck(onConnected: () => _goHome(context)),
                    const _ConnectionUnknownCard(),
                  ],
                  // **본인 아님·거절·빈 상태는 연락 카드 한 장이다**(P63). 종전엔 세 단계마다
                  // 안내 카드가 따로 있었는데(_DeclinedCard·_RejectedCard·_NotFoundCard), 그 카드가
                  // 하는 말은 제목·부제·연락 카드·CTA가 이미 한 말의 반복이었다 — notFound는
                  // "등록 번호가 다를 수 있다"를 세 자리에서 말했다. 원인 가설과 다음 행동은
                  // 연락 카드 힌트 **한 자리**에서만 말한다.
                  //
                  // 주 행동은 여전히 "센터에 알리기"다. 미연결의 압도적 다수 원인이 "센터를 못
                  // 골라서"가 아니라 **등록 번호가 다르거나 아직 등록 전**이고, 그건 전화 한 통이
                  // 승인 큐보다 빠르다. 가입 요청 입구를 카드로 **또** 두지 않는다 — 주 버튼이
                  // 이미 같은 행동을 한다.
                  // 거절 — 서버가 결론을 냈다. 대기 화면을 계속 보여주면 오지 않을 승인을
                  // 기다리게 된다. 서버가 거절 시 이름·번호를 지우므로 센터가 먼저 연락할
                  // 방법도 없다 — 다음 행동을 사용자 손에 돌려준다.
                  //
                  // notFound·declined는 스텝퍼 `● 가입 요청`이 "당신은 2단계 앞에 서 있다"로 CTA를
                  // 설명한다. 확인 상태 줄은 없다 — 확인할 요청이 없다.
                  CenterConfirmStage.declined => [
                    LobbyProgress(
                      step: state.lobbyStep ?? LobbyStep.requested,
                      availableWidth: viewport.maxWidth - 40,
                    ),
                    const SizedBox(height: 14),
                    _CenterCard(hint: _Hints.declined, centerId: lobbyCenterId),
                  ],
                  // rejected는 ✗ 스텝퍼가 징벌적으로 읽혀 결과 행 한 줄로 대신한다(plan B Q5).
                  CenterConfirmStage.rejected => [
                    _RequestResultRow(requestedAt: state.joinRequestedAt),
                    const SizedBox(height: 10),
                    _CenterCard(hint: _Hints.rejected, centerId: lobbyCenterId),
                  ],
                  CenterConfirmStage.notFound => [
                    LobbyProgress(
                      step: state.lobbyStep ?? LobbyStep.requested,
                      availableWidth: viewport.maxWidth - 40,
                    ),
                    const SizedBox(height: 14),
                    _CenterCard(hint: _Hints.notFound, centerId: lobbyCenterId),
                  ],
                },
                if (coachRowAllowed) const _CoachPreviewRow(),
                if (showroom) ...[
                  const SizedBox(height: 10),
                  _AfterConnectPreview(
                    // 작은 화면·큰 배율에서는 접힌다(plan B §4) — 데이터가 없으면 사라지고, 공간이
                    // 없으면 접힌다. 절대 넘치지 않는다.
                    compact: viewport.maxHeight < 600 ||
                        MediaQuery.textScalerOf(context).scale(1) >= 1.3,
                  ),
                ],
                const Spacer(),
                if (state.error != null) ...[
                  Text(
                    state.error!.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
                  ),
                  const SizedBox(height: 8),
                ],
                _CtaBlock(
                  stage: stage,
                  memberName: member?.name,
                  busy: state.busy,
                  checking: state.checkingConnection,
                  onConfirm: (confirm) => _confirm(context, ref, confirm),
                  onRestart: () => _restart(context, ref),
                  onCheck: () => _check(context, ref),
                  onRequestJoin: () => _showJoinRequestSheet(context),
                ),
                const SizedBox(height: 10),
                // 종전 문구의 뒷부분("한 계정으로 여러 센터 이용 가능 — 홈 상단에서
                // 전환")은 **두 겹으로 거짓이었다**(P55): 홈 상단 전환 어포던스는
                // P54에서 제거됐고, 서버 `UserIndex`는 uid당 1건이라 다센터 소속
                // 자체가 구조적으로 불가능하다. 지운다 — 없는 기능을 약속하지 않는다.
                //
                // "연결되면 예약·운동 기록·체형 사진을…"은 미리보기(`_AfterConnectPreview`)가 같은
                // 말을 아이콘으로 하므로 미리보기가 보이는 단계에서는 뺀다(같은 문장 두 번 금지, P63).
                // "바로 홈으로"의 "바로"도 뺐다(P69 C1) — 확인 주기만큼 늦는다.
                if (switch (stage) {
                  CenterConfirmStage.matched => '번호가 잘못 등록됐을 때 남의 계정에 연결되지 않도록 이름을 한 번 확인해요.',
                  CenterConfirmStage.pendingApproval => '앱을 껐다 켜도 이 화면으로 돌아와요. 연결되면 홈으로 들어가요.',
                  _ => showroom ? null : '연결되면 예약·운동 기록·체형 사진을 여기서 볼 수 있어요.',
                } case final note?) ...[
                  Text(note, textAlign: TextAlign.center, style: AppTypography.note),
                  const SizedBox(height: 4),
                ],
                // 법정 고지 + 계정 삭제 진입(P56 A1·B5) — **모든 stage에서** 보인다.
                //
                // 약관·방침: 이 화면은 이름을 수집하고(가입 요청 시트) 그 전 화면이 전화번호를
                // 수집했는데, 그 근거 문서로 가는 링크가 로그인 전 화면 어디에도 없었다. 마이 탭
                // 약관 카드는 셸 안이라 연결된 회원만 닿는다 — 정작 방침을 읽어야 할 시점은
                // 수집 **전**이다(개인정보보호법 §15②). 문서는 회원 데이터를 한 글자도 안 쓴다.
                //
                // 계정 삭제: 대기실 계정이 자기 이름·전화번호를 지울 **유일한 문**이다(§36).
                // 서버는 P55에서 열렸는데(`deleteUnlinkedAccount`) 앱 진입점이 셸 안 마이 탭
                // 하나라 미연결 계정은 닿을 수 없었다. pending부터 rejected까지 전부 같은 문이고,
                // matched·connectionUnknown만 고지가 다르다(`_openAccountDeletion` — 둘 다 서버가
                // 어느 경로를 돌지 앱이 모른다).
                _LobbyFooterLinks(
                  busy: state.busy,
                  onDeleteAccount: () => _openAccountDeletion(context, state),
                ),
              ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 대기실 계정의 삭제 확인 화면(P56 A1) — 셸 밖이라 `rootNavigator` 여부는 무의미하지만
  /// 마이 탭 진입(`my_screen._openAccountDeletion`)과 같은 방식으로 연다(전체 화면 push,
  /// 라우트 아님 — 딥링크가 생기면 안 되는 화면).
  ///
  /// scope 판정: 서버가 미연결을 **확답**한 stage(pending·declined·rejected·notFound)는
  /// `unlinked` — 지워지는 것은 인증 계정과 보낸 가입 요청뿐이다. `connectionUnknown`은
  /// 이미 연결된 회원이 네트워크 실패로 여기 선 것일 수 있어 `unknown` — 확인 화면이 회원
  /// 쪽 고지를 그대로 보여주고 그 사실을 배너로 밝힌다(과소 고지는 거짓, 과다 고지는 아니다).
  ///
  /// **matched도 `unknown`이다**(P63 검증 반영). 이 단계는 "번호로 회원을 찾았고 아직 이름
  /// 확인 전"이지 "미연결 확답"이 아니다 — 이미 연결된 회원이 기기를 바꾸거나 '번호 다시
  /// 인증하기'로 재인증하면 같은 uid로 여기 다시 서고, principal에는 member_id가 있어 서버는
  /// **회원 경로(전체 파기 + 5년 보존)**를 돈다. 그 사람에게 unlinked 고지("인증 계정과 가입
  /// 요청만")는 과소 고지다. 배너 문장만 connectionUnknown과 다르다(모르는 이유가 다르다).
  ///
  /// 가입 요청 흔적([AuthState.joinRequestTrace])은 **진입 시점 값을 넘긴다**(P63) — 삭제 화면이
  /// provider를 watch하면 삭제 성공 직후 `restartWithNewPhone()`이 상태를 비우는 순간 고지가
  /// 다시 그려진다. 회원이 읽고 동의한 문장은 그대로 남아야 한다.
  void _openAccountDeletion(BuildContext context, AuthState state) {
    final stage = state.centerConfirmStage;
    final scope = switch (stage) {
      CenterConfirmStage.matched || CenterConfirmStage.connectionUnknown => AccountDeletionScope.unknown,
      _ => AccountDeletionScope.unlinked,
    };
    final reason = stage == CenterConfirmStage.matched
        ? AccountDeletionUnknownReason.phoneMatched
        : AccountDeletionUnknownReason.connectionCheckFailed;
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => AccountDeletionScreen(
          scope: scope,
          joinRequestTrace: state.joinRequestTrace,
          unknownReason: reason,
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, bool confirm) async {
    final ok = await ref.read(authViewModelProvider.notifier).confirmMatch(confirm);
    if (ok && context.mounted) context.go('/home');
  }

  /// 연결이 확인됐다 — 수동 확인([_check])과 자동 확인([LobbyAutoCheck])이 같은 경로로 홈에 간다.
  void _goHome(BuildContext context) {
    if (context.mounted) context.go('/home');
  }

  /// "지금 확인" — 대표 승인 여부를 읽기만 한다(가입 요청과 달리 대표 화면에
  /// 아무 줄도 더 쌓지 않는다). 실패해도 대기 상태는 그대로 유지된다.
  /// 스낵바는 **수동 확인에만** — 자동 틱이 30초마다 토스트를 띄우면 소음이다.
  Future<void> _check(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(authViewModelProvider.notifier).checkConnection();
    if (!context.mounted) return;
    switch (result) {
      case ConnectionCheck.connected:
        _goHome(context);
      case ConnectionCheck.notYet:
        // 실패가 아니다 — 조회는 성공했고 답이 "아직"일 뿐이라 중립색. "승인되면 바로 연결돼요"는
        // 뺐다(P69 C1) — 확인 주기만큼 늦고, 백그라운드에선 다음에 열 때 안다.
        messenger.showSnackBar(riseSnackBar('아직 승인 전이에요'));
      case ConnectionCheck.failed:
        break; // 사유는 화면 인라인 문구(state.error)로 이미 보인다.
    }
  }

  /// 상시 탈출구 — Firebase 로그아웃 + 플로우 상태 초기화 후 전화번호 입력으로.
  /// (라우터 redirect는 앱 시작 1회만 도는 래치라 이 이동과 충돌하지 않는다.)
  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    await ref.read(authViewModelProvider.notifier).restartWithNewPhone();
    if (context.mounted) context.go('/login');
  }

  /// 시스템 백 전용 — 같은 탈출구를 쓰되, 되돌릴 수 없는 동작이라 확인을 받는다.
  Future<void> _confirmRestart(BuildContext context, WidgetRef ref) async {
    final leave = await showDialog<bool>(
      context: context,
      // 루트 Navigator에 띄운다 — 기본값(false)이면 셸 내부 Navigator에 올라가
      // **하단 탭바가 시트와 스크림 위에 남는다**(실기기 점검에서 발견, P09).
      // 모달이 뜬 채로 다른 탭을 누를 수 있어 확정 전 화면을 벗어나게 된다.
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('번호 입력으로 돌아갈까요?'),
        content: const Text(
          '지금 인증한 번호는 로그아웃돼요. 승인을 기다리는 중이라면 같은 번호로 '
          '다시 인증했을 때 대기 상태로 돌아와요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('머무르기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('돌아가기'),
          ),
        ],
      ),
    );
    if ((leave ?? false) && context.mounted) await _restart(context, ref);
  }

  void _showJoinRequestSheet(BuildContext context) {
    // 이 화면은 셸 밖(로그인 흐름)이라 `useRootNavigator`가 무의미했지만,
    // 래퍼를 쓰면 하단 인셋 처리가 다른 시트와 같아진다(P54).
    //
    // 제출 중 잠금 신호(P56 M1) — 요청이 날아가는 동안 시트를 쓸어 내리면 409("이미 보낸
    // 요청이 있어요")도 네트워크 실패도 갈 곳이 없고, 회원은 또 보낸다(rise_sheet.dart 헤더).
    final submitting = ValueNotifier(false);
    showRiseSheet<void>(
      context,
      submitting: submitting,
      builder: (_) => _JoinRequestSheet(submitting: submitting),
    );
  }
}

/// 대기실 하단 링크 줄 — 약관 · 개인정보처리방침 · 계정 삭제. 근거는 build의 주석.
///
/// 작게(11px 밑줄 링크) 두는 이유: 이 화면의 본론은 센터 연결이고, 이 줄은 언제든 닿아야
/// 하되 본론과 경쟁하면 안 된다. 다만 **터치 영역은 44dp**를 지킨다([_UnderlineLink]).
/// 삭제 링크만 danger 색 — 되돌릴 수 없는 동작이 문서 링크와 같은 무게로 보이면 안 된다
/// (마이 탭 로그아웃/회원탈퇴 행의 색 분리와 같은 이유).
class _LobbyFooterLinks extends StatelessWidget {
  const _LobbyFooterLinks({required this.busy, required this.onDeleteAccount});

  /// 이 플로우의 요청이 진행 중 — 삭제 진입만 잠근다(문서 링크는 상태와 무관).
  final bool busy;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    const dot = Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.muted));
    // Wrap: 글자 배율 1.35·320dp 폭에서 세 링크가 한 줄에 안 들어가면 줄바꿈된다.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _UnderlineLink(
          label: '이용약관',
          onTap: () => openLegalDocument(context, LegalLinks.terms),
        ),
        dot,
        _UnderlineLink(
          label: '개인정보처리방침',
          onTap: () => openLegalDocument(context, LegalLinks.privacy),
        ),
        dot,
        _UnderlineLink(
          label: '계정 삭제',
          color: AppColors.danger,
          onTap: busy ? null : onDeleteAccount,
        ),
      ],
    );
  }
}

/// 상태별 CTA — 어떤 분기로 들어와도 최소 하나의 진행 경로와
/// [_CtaBlock._restartLabel]("번호 다시 인증하기")이 함께 남는다(빈 CTA 블록이 나올 수 없는 구조).
class _CtaBlock extends StatelessWidget {
  const _CtaBlock({
    required this.stage,
    required this.memberName,
    required this.busy,
    required this.checking,
    required this.onConfirm,
    required this.onRestart,
    required this.onCheck,
    required this.onRequestJoin,
  });

  final CenterConfirmStage stage;
  final String? memberName;

  /// 이 플로우의 어떤 요청이든 진행 중 — 모든 CTA를 함께 잠근다.
  final bool busy;

  /// 그중 "연결 확인"이 진행 중일 때만 — 라벨을 "확인 중…"으로 바꾼다.
  final bool checking;

  final void Function(bool confirm) onConfirm;
  final VoidCallback onRestart;
  final VoidCallback onCheck;
  final VoidCallback onRequestJoin;

  @override
  Widget build(BuildContext context) {
    if (stage == CenterConfirmStage.matched && memberName != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiseButton(
            label: busy ? '확인 중…' : '네, $memberName 본인이에요 — 시작하기',
            expand: true,
            onPressed: busy ? null : () => onConfirm(true),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _UnderlineLink(label: '본인이 아니에요', onTap: busy ? null : () => onConfirm(false)),
              const Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              _UnderlineLink(label: _restartLabel, onTap: busy ? null : onRestart),
            ],
          ),
        ],
      );
    }

    // 연결 여부를 모르는 상태(앱 시작 복원 실패) — 번호를 다시 넣게 하는 건
    // 이미 연결됐을지 모르는 사용자에게 인증을 처음부터 시키는 일이다.
    // 재확인을 주 버튼으로 올리고, 번호 재시도는 링크로 남긴다.
    if (stage == CenterConfirmStage.connectionUnknown) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiseButton(
            label: checking ? '확인 중…' : '연결됐는지 다시 확인',
            expand: true,
            onPressed: busy ? null : onCheck,
          ),
          const SizedBox(height: 10),
          Center(
            child: _UnderlineLink(label: _restartLabel, onTap: busy ? null : onRestart),
          ),
        ],
      );
    }

    // 승인 대기 중엔 "기다리기"가 정상 경로다 — 번호 재시도는 링크로 낮춘다.
    // (대기 카드 안에 [연결됐는지 확인]·[다시 요청]이 이미 있다.)
    if (stage == CenterConfirmStage.pendingApproval) {
      return Center(
        child: _UnderlineLink(label: _restartLabel, onTap: busy ? null : onRestart),
      );
    }

    // 빈 상태·본인 아님 — **주 버튼을 탈출에서 진행으로 뒤집는다**(P55).
    //
    // 종전엔 번호 재인증 링크([_restartLabel])가 primary였다. 그런데 번호를 다시 넣는 것은
    // "이 번호가 틀렸다"고 이미 아는 사람의 행동이고, 대부분의 사용자에게 실제
    // 다음 행동은 **센터에 알리거나 가입을 요청하는 것**이다. 정작 그 경로는 회색
    // 행 한 줄에 숨어 있었다 — 우선순위가 뒤집혀 있었다.
    //
    // rejected는 "다시 보내기"다(P69 C2) — 서버가 rejected 뒤 재요청을 허용한다(v2.27). 첫 요청과
    // 같은 라벨이면 회원은 자기 요청이 사라진 줄 안다.
    final rejected = stage == CenterConfirmStage.rejected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiseButton(
          label: busy ? '처리 중…' : (rejected ? '가입 요청 다시 보내기' : '가입 요청 보내기'),
          expand: true,
          onPressed: busy ? null : onRequestJoin,
        ),
        const SizedBox(height: 10),
        Center(
          child: _UnderlineLink(label: _restartLabel, onTap: busy ? null : onRestart),
        ),
      ],
    );
  }

  /// 옛 라벨("다른 번호 다시 시도")을 쓰지 않는다(P63) — 이 링크는 데스크가 번호를 고친 뒤 **같은 번호를 다시
  /// 인증하는** 경로도 겸한다(번호 매칭 `join/match`는 코드 인증 직후에만 돌고, 이 화면의
  /// 재확인 버튼은 매칭을 다시 하지 않는다). 연락 카드 힌트가 이 라벨로 안내한다.
  static const _restartLabel = '번호 다시 인증하기';
}

/// 연락 카드의 단계별 힌트(P63) — "왜 데스크가 도움이 되는지"는 이 카드 한 자리에서만 말한다.
/// 부제(사실)와 분리된 **가설 층**이라 "~일 수 있어요/~이면"으로 헤지한다.
///
/// notFound·declined의 "같은 번호를 다시 인증하면"은 실제 경로다: 번호 매칭은 코드 인증 직후
/// `_matchAfterSignIn`에서만 돌고, 세션 복원도 대기실의 재확인 버튼도 매칭을 다시 하지 않는다.
/// 종전 힌트가 약속하던 "다음 확인부터 연결"은 이 화면에 없는 동작이었다.
abstract final class _Hints {
  // "고치거나 등록한 뒤" — notFound의 원인 가설은 둘(번호 다름 / 등록 전)인데 종전 문장은 "고친
  // 뒤"만 말해 등록 전인 사람에게 고칠 번호가 있는 것처럼 읽혔다. "이름 확인 한 번으로"는 재인증
  // 뒤 실제로 오는 화면(matched의 "네, OO 본인이에요")이다 — 승인 큐를 거치지 않는다는 사실.
  static const notFound =
      '센터에 등록된 번호가 다르거나 아직 등록 전이면 자동 연결이 안 돼요. '
      '데스크에서 번호를 고치거나 등록한 뒤 같은 번호를 다시 인증하면 이름 확인 한 번으로 연결돼요.';
  static const rejected = '데스크에 확인한 뒤 다시 요청할 수 있어요.';
  // "다른 센터 회원이면"이라 쓰지 않는다 — v1은 단일 센터다(rejected 부제와 같은 이유).
  // 재인증 단계를 빼먹지 않는다 — 데스크가 고쳐도 이 화면의 어떤 버튼도 매칭을 다시 하지
  // 않으므로(`join/match`는 코드 인증 직후에만), 고친 뒤의 행동까지 말해야 문장이 닫힌다.
  static const declined =
      '내 번호가 다른 회원에게 등록된 것 같다면 데스크에서 고쳐드려요 — '
      '고친 뒤 같은 번호를 다시 인증하면 연결돼요. '
      '아직 회원이 아니라면 아래에서 가입 요청할 수 있어요.';
  // "문의할 수 있어요"가 아니라 "문의해주세요" — 연락 카드에 전화·주소가 비어 있어도(오늘
  // 프로덕션) 참인 문장이어야 한다. "할 수 있어요"는 이 카드에 수단이 있다는 뜻으로 읽힌다.
  static const pending = '승인이 늦으면 센터 데스크에 문의해주세요.';
}

class _UnderlineLink extends StatelessWidget {
  const _UnderlineLink({required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback? onTap;

  /// 활성 색(기본 muted). 되돌릴 수 없는 동작(계정 삭제)은 danger로 구분한다.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 로그인 플로우의 최종 탈출구("번호 다시 인증하기", "본인이 아니에요") — 글자 상자만
    // 누르면 ≈15dp였다. 투명 히트 영역을 GestureDetector 안쪽에 두고 opaque로 받는다.
    // 높이는 **44dp 하한을 명시**한다 — 종전 세로 패딩 14×2 + 11px 글자는 43dp 남짓이라
    // 글꼴·배율에 따라 44에 못 미쳤다(touch_target_test의 기준).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: onTap == null ? AppColors.line : (color ?? AppColors.muted),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 가입 요청 시트 — 예약 확정 시트와 같은 Stateful 패턴:
/// 제출 중 표시·이중 탭 방지·에러는 시트 뒤가 아니라 시트 안에 인라인 표시.
class _JoinRequestSheet extends ConsumerStatefulWidget {
  const _JoinRequestSheet({required this.submitting});

  /// 제출 중 신호 — [showRiseSheet]의 잠금과 같은 객체(P56 M1).
  final ValueNotifier<bool> submitting;

  @override
  ConsumerState<_JoinRequestSheet> createState() => _JoinRequestSheetState();
}

class _JoinRequestSheetState extends ConsumerState<_JoinRequestSheet> {
  final _nameController = TextEditingController();

  /// 저장소는 [widget.submitting] 하나다(rise_sheet.dart `submitting` 절).
  bool get _submitting => widget.submitting.value;
  String? _error;

  /// 회원이 고른 센터. **비어 있으면 서버가 기본 센터로 폴백한다**(계약 v2.33) — 고를 것이
  /// 1곳 이하일 때 이 값이 그대로 비고, 그게 종전 동작이다.
  String _centerId = '';

  @override
  void dispose() {
    _nameController.dispose();
    widget.submitting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 이름 입력 시 키보드가 올라오면 작은 화면에서 overflow — 스크롤로 흡수.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('가입 요청', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            '이름·연락처로 가입 요청 → 센터에서 승인하면 연결돼요 (코드 입력 없음)',
            style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          // 센터 선택 — **고를 것이 2곳 이상일 때만 나타난다**(계약 v2.33). 한 곳뿐이면
          // 선택지가 없는 선택 화면이 되고, 회원에게 "고를 수 있다"는 거짓 인상만 준다.
          _CenterPicker(
            selected: _centerId,
            enabled: !_submitting,
            onSelect: (id) => setState(() {
              _centerId = id;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: '이름 입력 (연락처는 인증한 번호로 전송돼요)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          RiseButton(
            label: _submitting ? '요청 중…' : '가입 요청 보내기',
            expand: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '이름을 입력해주세요');
      return;
    }
    // 고를 센터가 둘 이상인데 안 골랐으면 보내지 않는다. 여기서 막지 않으면 요청이 기본
    // 센터 큐로 조용히 가고, 신청자는 자기가 고른 적 없는 센터의 승인을 기다리게 된다.
    final centers = ref.read(joinCentersProvider).asData?.value ?? const <CenterDirectory>[];
    if (centers.length >= 2 && _centerId.isEmpty) {
      setState(() => _error = '센터를 선택해주세요');
      return;
    }
    setState(() {
      widget.submitting.value = true;
      _error = null;
    });
    final notifier = ref.read(authViewModelProvider.notifier);
    final outcome = await notifier.requestJoin(name, centerId: _centerId);
    if (!mounted) return;
    if (outcome != JoinRequestOutcome.failed) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      // 409 `join_pending`은 실패가 아니라 "이미 pending이 있다"는 서버 확답(P69 C2) — 뷰모델이
      // pending으로 승격했으므로 시트는 성공처럼 닫고 문구만 다르게 말한다. "자동으로"는 쓰지
      // 않는다(P69 C1).
      messenger.showSnackBar(riseSnackBar(
        outcome == JoinRequestOutcome.alreadyPending
            ? '이미 보낸 요청이 있어요 — 센터가 확인하면 연결돼요'
            : '가입 요청 완료 — 센터가 승인하면 연결돼요',
        kind: RiseSnackKind.ok,
      ));
    } else {
      // 에러는 시트 안에서 보여주고, 시트 뒤 화면(state.error 표시부)에는 남기지 않는다.
      final message = ref.read(authViewModelProvider).error?.message ?? '요청에 실패했어요';
      notifier.clearError();
      setState(() {
        widget.submitting.value = false;
        _error = message;
      });
    }
  }
}

/// 센터 선택 — 가입 요청을 어느 센터로 보낼지 고른다(계약 v2.33).
///
/// **목록이 2곳 미만이면 아무것도 그리지 않는다.** 고를 것이 없는 선택 UI는 방해일 뿐이고,
/// 서버는 센터를 비워 보내면 기본 센터로 폴백하므로 그때의 동작은 종전과 같다. 조회 실패도
/// 같은 취급이다 — 목록을 못 받았다고 가입 요청 자체를 막지 않는다(`joinCentersProvider`가
/// 실패를 빈 목록으로 접는다).
///
/// 상호가 빈 센터는 앱 기본 라벨로 그린다 — 그런 센터를 목록에서 빼면 고를 방법 자체가
/// 사라지기 때문에 서버가 빈 이름으로라도 실어 보낸다(v2.33).
class _CenterPicker extends ConsumerWidget {
  const _CenterPicker({
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final String selected;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centers = ref.watch(joinCentersProvider).asData?.value ?? const <CenterDirectory>[];
    if (centers.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        const Text('어느 센터에 요청할까요?',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final c in centers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: enabled ? () => onSelect(c.id) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: c.id == selected ? AppColors.brandLight : Colors.transparent,
                  border: Border.all(
                    color: c.id == selected ? AppColors.brand : AppColors.line,
                    width: c.id == selected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.hasName ? c.name : AppConfig.centerFullName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          if (c.address.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(c.address,
                                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ],
                        ],
                      ),
                    ),
                    if (c.id == selected)
                      const Icon(Icons.check_circle, size: 18, color: AppColors.brand),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MatchedCenterCard extends ConsumerWidget {
  const _MatchedCenterCard({required this.memberName, this.trainerName, this.trainer});
  final String memberName;
  final String? trainerName;

  /// 스태프 캐시에서 보강한 담당 코치(P05) — 아바타·직함 표시용(best-effort).
  final StaffDto? trainer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 상호는 서버 값(어드민 "센터 신원")이 우선 — 없을 때만 임시 상수(P56 L10).
    final centerName = ref.watch(centerDisplayNameProvider);
    // 캐시의 이름이 ""면 state의 이름으로 넘어가야 한다(??는 ""를 통과시킨다).
    // 둘 다 미해석(null·""·공백)이면 null — 예전엔 공백뿐인 이름이 non-null로
    // 살아남아 "담당    코치" + 빈 이니셜 아바타(TrainerAvatar는 isEmpty만 본다)가 됐다.
    final coachName = CoachLabel.nameOrNull(trainer?.name) ?? CoachLabel.nameOrNull(trainerName);
    // 스태프 캐시를 못 받았으면 퇴사 여부를 알 수 없다 → 현직으로 본다
    // (계약 v2.0 승격 규약과 같은 방향 — 모르는 걸 퇴사로 단정하지 않는다).
    final coachInactive = trainer?.isInactive ?? false;
    // 직함 · 연차 한 줄 — 매칭 카드의 신뢰도 보강(빈 프로필이면 줄 생략).
    final coachSubtitle = trainer == null
        ? ''
        : [
            if (trainer!.profile.title.isNotEmpty) trainer!.profile.title,
            if (trainer!.profile.careerYears > 0) '${trainer!.profile.careerYears}년차',
          ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        border: Border.all(color: AppColors.brand, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  centerName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const RiseBadge('자동 매칭', variant: RiseBadgeVariant.ok),
            ],
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
              children: [
                TextSpan(
                  text: memberName,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const TextSpan(text: ' 님으로 등록되어 있어요'),
              ],
            ),
          ),
          if (coachName != null) ...[
            const SizedBox(height: 8),
            // 담당 코치 아바타(소) + 직함(P05) — 탭하면 프로필 시트.
            InkWell(
              onTap: () => showTrainerProfileSheet(
                context,
                staff: trainer ?? StaffDto(uid: '', name: coachName),
                // 스태프 캐시를 못 받아 이름만 채운 폴백이면 "미등록"이 아니라
                // "미로드"다 — 예약 탭과 같은 규약으로 시트가 재시도 안내를 한다
                // (예전엔 플래그를 안 넘겨 온보딩에서만 문구가 갈렸다).
                profileUnavailable: trainer == null,
              ),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Row(
                children: [
                  TrainerAvatar(
                    name: coachName,
                    photoUrl: trainer?.profile.photoUrl ?? '',
                    colorHex: trainer?.color,
                    size: 26,
                    inactive: coachInactive,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // 온보딩 화면의 **퇴사 표기 앵커**(코치 언급이 여기 한 줄뿐).
                          // 계약상 퇴사 전 Member.trainer_id 이관이 강제되므로 정상
                          // 흐름에선 나오지 않지만, 첫 화면부터 사실과 다른 담당을
                          // 소개하는 건 되돌리기 가장 어려운 오해라 방어한다.
                          CoachLabel.tag('담당 $coachName 코치', inactive: coachInactive),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        if (coachSubtitle.isNotEmpty)
                          Text(
                            coachSubtitle,
                            style: const TextStyle(fontSize: 10, color: AppColors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 연결 여부를 확인하지 못한 상태(앱 시작 복원이 GET /v1/me에 실패) —
/// "찾지 못했어요"와 다른 카드를 쓴다. 저쪽은 서버가 낸 결론이지만 이쪽은
/// 아직 아무것도 모르는 상태라, 가입 요청이 아니라 재확인으로 유도해야 한다.
///
/// 본문은 **한 문장**이다(P63). 종전 세 문장 중 둘("불러오지 못했어요"·"네트워크가 돌아오면")은
/// 제목·부제의 반복이었고 실패 사유는 인라인 error가 따로 말한다. 카드를 없애지 않는 이유는
/// 이 단계엔 연락 카드가 없어 이 카드가 유일한 본문이기 때문이다(제목만 있는 화면은 빈 여백).
/// 남은 문장은 안심 문장이라 경고 아이콘을 두지 않는다 — 경고 신호 옆에 "그대로 홈으로
/// 들어가요"가 붙으면 신호와 말이 어긋난다(정보성 아이콘이 [RiseIcons]에 없어 아이콘 없음).
class _ConnectionUnknownCard extends StatelessWidget {
  const _ConnectionUnknownCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Text(
        '이미 연결된 회원이라면 다시 확인했을 때 그대로 홈으로 들어가요.',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
      ),
    );
  }
}

/// "다시 요청"(P69 C2) — **서버가 pending을 확답하지 않은 대기 화면에서만** 남는 버튼.
///
/// 종전 `_PendingApprovalCard`의 두 버튼 중 하나였다. 서버가 pending을 들고 있으면 재요청은 100%
/// 409라 함정이었고, 지금은 그 상태에선 버튼 자체가 없다([AuthState.canRetryJoinRequest]). 남는
/// 경우는 로컬 기록만 있는 `unknown`(코드 인증 직후·서버가 요청을 안 실어 줌) — 눌러서 409를
/// 받으면 뷰모델이 pending으로 승격하고, 진짜 요청이 없었다면 접수된다. 30초 쿨다운은 대표 큐
/// 보호용으로 그대로(유한 타이머라 위젯 테스트의 settle을 막지 않는다).
class _RetryJoinButton extends StatefulWidget {
  const _RetryJoinButton({
    super.key,
    required this.requestedAt,
    required this.onRetry,
    this.busy = false,
  });

  final DateTime requestedAt;
  final VoidCallback onRetry;

  /// 이 플로우의 어떤 요청이든 진행 중이면 잠근다(연타 방지).
  final bool busy;

  @override
  State<_RetryJoinButton> createState() => _RetryJoinButtonState();
}

class _RetryJoinButtonState extends State<_RetryJoinButton> {
  static const _cooldown = Duration(seconds: 30);

  Timer? _timer;
  late int _remainingSeconds = _computeRemaining();

  int _computeRemaining() {
    final elapsed = DateTime.now().difference(widget.requestedAt);
    final left = _cooldown - elapsed;
    return left.isNegative ? 0 : left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
  }

  @override
  void initState() {
    super.initState();
    if (_remainingSeconds > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _remainingSeconds = _computeRemaining());
        if (_remainingSeconds <= 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _remainingSeconds > 0 || widget.busy;
    return Align(
      alignment: Alignment.centerLeft,
      child: RiseButton(
        label: _remainingSeconds > 0 ? '다시 요청 ($_remainingSeconds초 후)' : '다시 요청',
        style: RiseButtonStyleKind.outline,
        small: true,
        onPressed: locked ? null : widget.onRetry,
      ),
    );
  }
}

/// rejected의 결과 행(P69 H2·M4) — 스텝퍼 대신 한 줄. ✗ 스텝퍼는 징벌적으로 읽힌다.
/// 요청 시각이 있으면 "9/8 12:05 보낸 요청 · …", 없으면 축약형.
class _RequestResultRow extends StatelessWidget {
  const _RequestResultRow({this.requestedAt});
  final DateTime? requestedAt;

  @override
  Widget build(BuildContext context) {
    final at = requestedAt;
    return Text(
      at == null
          ? '보낸 요청을 센터가 연결하지 않았어요'
          : '${LobbyProgress.requestedAtLabel(at)} 보낸 요청 · 센터가 연결하지 않았어요',
      style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
    );
  }
}

/// 센터 카드(P55 → P69 H3) — 상호 · 주소(탭 → 지도) · 수업 시간 · 전화 · 힌트.
///
/// **왜 전화가 이 화면의 실용 핵심인가**: 미연결의 압도적 다수 원인은 "센터를 못 골라서"가
/// 아니라 **어드민에 등록된 번호와 인증한 번호가 다르거나 아직 등록 전**이다. 전화 한 통이면
/// 데스크가 번호를 고치고, 같은 번호를 다시 인증하면 `join/match`가 붙는다 — 승인 큐를
/// 거치지 않는 가장 빠른 경로다(매칭은 코드 인증 직후에만 돌므로 "다음 재확인"이 아니라
/// **재인증**이다). 가입 요청은 대표가 큐를 보고 승인해야 하니 오히려 느리다.
///
/// [hint]는 단계별 한 문장([_Hints], P63) — 부제(사실)와 분리된 가설 층.
///
/// **데이터가 없으면 그 줄이 사라진다.** 주소·수업 시간·전화 모두 서버 값이 있을 때만 그린다 —
/// 없는 번호를 지어내거나 죽은 버튼을 두지 않는다. 상호+힌트뿐이어도 카드 프레임은 유지한다
/// (테스트 앵커 안정 — 오케스트레이터 결정).
///
/// [centerId]는 요청한 센터(v2.33·v2.34) — 있으면 `?center=`로 그 센터를 묻고, 고를 센터가 2곳
/// 이상이면 상단에 "요청한 센터" 라벨을 단다. null이면 기본 센터(홈 헤더와 같은 인스턴스).
class _CenterCard extends ConsumerWidget {
  const _CenterCard({required this.hint, required this.centerId});

  /// 왜 데스크가 도움이 되는지 — 단계별 한 문장.
  final String hint;
  final String? centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(centerContactProvider(centerId)).value ?? const CenterContact();
    // 목록 조회는 요청한 센터가 있을 때만 건다 — 라벨 하나 때문에 모든 대기실이 GET /v1/join/centers를
    // 부를 이유가 없다(조건부 watch는 build마다 의존이 다시 계산된다).
    final multiCenter = centerId != null &&
        (ref.watch(joinCentersProvider).asData?.value.length ?? 0) >= 2;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (multiCenter) ...[
            const Text(
              '요청한 센터',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            // 서버 상호(어드민 "센터 신원") — 미등록이면 임시 상수(P56 L10).
            contact.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          if (contact.hasAddress) ...[
            const SizedBox(height: 6),
            // 탭하면 지도 — 주소 한 줄은 읽는 것보다 찾아가는 데 쓴다.
            InkWell(
              onTap: () => _openMap(context, contact.address),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: RiseIcon(RiseIcons.mapPin, size: 13, color: AppColors.muted),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        contact.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.line,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (contact.hasHours) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const RiseIcon(RiseIcons.clock, size: 13, color: AppColors.muted),
                const SizedBox(width: 6),
                // "운영시간"이 아니라 "수업" — 데스크 응대 시간과 다를 수 있다(plan B §3).
                Text(
                  '수업 ${contact.hoursLabel}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
          ),
          if (contact.hasPhone) ...[
            const SizedBox(height: 10),
            RiseButton(
              label: '센터에 전화 (${contact.phone})',
              expand: true,
              style: RiseButtonStyleKind.outline,
              onPressed: () => _call(context, contact.phone),
            ),
          ],
        ],
      ),
    );
  }

  /// 전화 앱이 없거나 거절하면 **조용히 실패하지 않는다** — 아무 반응 없는 버튼은
  /// 앱이 고장 난 것으로 보인다(`legal_links_card`의 `_open`과 같은 규약).
  Future<void> _call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse('tel:$normalized'));
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    messenger.showSnackBar(riseSnackBar('전화 앱을 열지 못했어요 — 번호: $phone', kind: RiseSnackKind.danger));
  }

  /// 지도 앱 — 플랫폼 스킴(Android `geo:`, iOS `maps://`) 먼저, 안 열리면 웹 지도로 폴백.
  /// 그래도 실패하면 주소를 스낵바에 남긴다(`_call`과 같은 규약) — 복사해서라도 찾아갈 수 있게.
  Future<void> _openMap(BuildContext context, String address) async {
    final messenger = ScaffoldMessenger.of(context);
    final q = Uri.encodeComponent(address);
    final candidates = <Uri>[
      if (defaultTargetPlatform == TargetPlatform.android) Uri.parse('geo:0,0?q=$q'),
      if (defaultTargetPlatform == TargetPlatform.iOS) Uri.parse('maps://?q=$q'),
      Uri.parse('https://maps.google.com/?q=$q'),
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // 다음 후보로.
      }
    }
    messenger.showSnackBar(riseSnackBar('지도를 열지 못했어요 — 주소: $address', kind: RiseSnackKind.danger));
  }
}

/// 코치 한 줄(P69 M1) — 아바타 ≤4 + "코치 N명" → 코치 소개 시트(마이 탭과 같은 시트, 네트워크 0).
///
/// **현직만** 센다(퇴사자는 이름 해석에만 남는다 — `staff_directory.dart` 규약). 0명이면 줄 자체가
/// 없다 — "코치 0명"은 센터를 깎아내리는 문장. 로딩·실패도 줄 없음(스피너 없음 — 부가 정보).
/// 센터 일치 조건은 호출부가 판정한다(`coachRowAllowed`).
class _CoachPreviewRow extends ConsumerWidget {
  const _CoachPreviewRow();

  static const _maxAvatars = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final map = ref.watch(staffMapProvider).value;
    if (map == null) return const SizedBox.shrink();
    // 관장 먼저 → 이름순(`center_coaches_sheet`와 같은 순서 — 줄과 시트의 첫 얼굴이 같아야 한다).
    int rank(StaffDto s) => s.role == 'owner' ? 0 : 1;
    final coaches = map.values.where((s) => !s.isInactive).toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.name.compareTo(b.name);
      });
    if (coaches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () => showCenterCoachesSheet(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                for (final c in coaches.take(_maxAvatars)) ...[
                  TrainerAvatar(
                    name: c.name,
                    photoUrl: c.profile.photoUrl,
                    colorHex: c.color,
                    size: 26,
                  ),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '코치 ${coaches.length}명',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
                const RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "연결되면 이 앱에서" 미리보기(P69 M3) — 예약 · QR 출석 · 운동 기록 · 체형 사진.
///
/// 네 가지 모두 셸 안에 실재하는 기능이다(없는 기능 약속 금지, P56). 다만 예약은 회원권이 있어야
/// 하므로 "바로/언제든" 같은 부사를 쓰지 않는다 — 그 조건은 홈의 빈 상태 뷰가 그때 말한다.
/// [compact]면 한 줄 링크로 접히고 시트가 같은 네 가지를 보여준다(320×568·배율 1.3+).
class _AfterConnectPreview extends StatelessWidget {
  const _AfterConnectPreview({required this.compact});
  final bool compact;

  static const title = '연결되면 이 앱에서';
  static const linkLabel = '연결되면 할 수 있는 것';
  static const items = <(String, String)>[
    (RiseIcons.calendar, '예약'),
    (RiseIcons.qrScan, 'QR 출석'),
    (RiseIcons.chart, '운동 기록'),
    (RiseIcons.camera, '체형 사진'),
  ];

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return InkWell(
        onTap: () => showRiseSheet<void>(context, builder: (_) => const _AfterConnectSheet()),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(linkLabel, style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ),
                RiseIcon(RiseIcons.chevronRight, size: 13, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          title,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (icon, label) in items)
              Expanded(
                child: Column(
                  children: [
                    RiseIcon(icon, size: 20, color: AppColors.brand),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// [_AfterConnectPreview]의 접힌 형태가 여는 시트 — 같은 네 가지를 세로로.
class _AfterConnectSheet extends StatelessWidget {
  const _AfterConnectSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            _AfterConnectPreview.title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final (icon, label) in _AfterConnectPreview.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  RiseIcon(icon, size: 20, color: AppColors.brand),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 매칭 카드 아래의 부차 경로 — "제가 아니에요"(가입 요청 시트).
///
/// 종전 제목 '제가 아니거나 다른 센터예요'의 "다른 센터"는 v1에 없는 선택지다(단일 센터 —
/// 계약 v2.27 center_id 규약, rejected 부제·declined 힌트와 같은 이유로 금지). 부제 '가입 요청을
/// 따로 보낼 수 있어요'는 그대로 — 이 카드가 실제로 하는 일이다.
class _NotMeCard extends StatelessWidget {
  const _NotMeCard({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '제가 아니에요',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '가입 요청을 따로 보낼 수 있어요',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
