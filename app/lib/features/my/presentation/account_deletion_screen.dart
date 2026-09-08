import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/features/auth/presentation/auth_state.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/my/domain/account_deletion.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';

/// 회원탈퇴 / 계정 삭제 확인 화면(API계약 v2.11·v2.27 · App Store Guideline 5.1.1(v)).
///
/// **다이얼로그가 아니라 전체 화면인 이유**: 이 결정은 되돌릴 수 없고, 회원이 읽어야 할 것이
/// 두 문단이 아니라 두 목록이다(무엇이 지워지는지 / 무엇이 왜 남는지). 다이얼로그에 넣으면
/// 스크롤되는 경고문이 되고, 스크롤되는 경고문은 읽히지 않는다.
///
/// 확인은 **두 겹**이다: 화면의 체크박스로 "읽었다"를, 마지막 다이얼로그로 "실행한다"를
/// 따로 받는다. 이 저장소의 파괴적 동작 규약(consent_toggles·inbody 삭제)이 "화면이 먼저
/// 결과를 예고하고 다이얼로그는 재확인"이라, 탈퇴는 그중 가장 무거운 쪽에 맞춘다.
///
/// 라우트가 아니라 `Navigator.push`인 이유는 QrScanScreen과 같다 — 탭 셸 밖의 일회성 화면이라
/// 딥링크로 들어올 자리가 없고, 오히려 링크가 생기면 안 되는 화면이다.
///
/// **[scope]로 세 종류의 계정을 다룬다**(P56 A1). 종전엔 이 화면의 진입점이 셸 안 마이 탭
/// 하나뿐이라, 센터에 연결되지 않은 계정 — 가입 요청 시트에 이름을 직접 적어 서버에 넘긴
/// 사람 — 은 자기 이름·전화번호를 지울 문이 앱 안에 없었다(개인정보보호법 §36). P55가
/// 서버 쪽 경로(`deleteUnlinkedAccount`)를 열어 두고 앱 문은 안 냈던 자리다. 대기실
/// (`center_confirm_screen`)이 이제 [AccountDeletionScope.unlinked]·[AccountDeletionScope.unknown]
/// 으로 이 화면을 연다 — 고지 목록·문구·완료 안내가 scope마다 다르다(같은 화면을 그대로
/// 쓰면 회원권도 사진도 없는 사람에게 "체형사진이 삭제되고 회원권 내역은 5년 보관돼요"라고
/// 말하게 된다 — 없는 것에 대한 고지는 고지가 아니라 소음이다).
class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({
    super.key,
    this.scope = AccountDeletionScope.member,
    this.joinRequestTrace = JoinRequestTrace.unknown,
    this.unknownReason = AccountDeletionUnknownReason.connectionCheckFailed,
  });

  /// 어떤 계정을 지우는가 — 고지·문구·완료 안내가 이 값에 따라 갈린다.
  final AccountDeletionScope scope;

  /// 대기실 계정의 가입 요청 흔적(P63) — [AccountDeletionScope.unlinked]에서만 읽는다.
  /// 삭제되는 정보 행·경고 상자·확인 다이얼로그가 이 값으로 갈린다.
  ///
  /// **진입 시점의 스냅샷**이다 — `authViewModelProvider`를 watch하지 않는다. 삭제 성공 직후
  /// [_signOut]이 `restartWithNewPhone()`으로 auth 상태를 통째로 비우는데, 화면이 provider를
  /// 보고 있으면 그 순간 목록·경고가 unknown 문구로 다시 그려진다(스낵바 직전 깜빡임).
  /// 고지는 회원이 읽고 동의한 그 문장 그대로 남아야 한다.
  final JoinRequestTrace joinRequestTrace;

  /// [AccountDeletionScope.unknown]에서 왜 모르는지 — 배너 첫 줄만 갈린다(P63 검증 반영).
  /// 다른 scope에서는 읽지 않는다.
  final AccountDeletionUnknownReason unknownReason;

  @override
  ConsumerState<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  bool _acknowledged = false;
  bool _submitting = false;

  AccountDeletionScope get _scope => widget.scope;
  bool get _unlinked => _scope == AccountDeletionScope.unlinked;
  JoinRequestTrace get _trace => widget.joinRequestTrace;

  @override
  Widget build(BuildContext context) {
    // 잔여 회차는 **서버가 준 값**만 쓴다(마이 탭이 이미 받아 둔 요약). 못 읽었으면 숫자를
    // 지어내지 않고 그 사실을 말한다 — 이 저장소의 "모르는 것을 아는 것처럼 말하지 않는다"
    // 규약(v2.1 3상태 규약과 같은 근거).
    //
    // 회원 scope에서만 읽는다. 대기실 계정은 세션이 없어 `myViewModelProvider`가
    // AuthFailure로 서 있다 — 그 실패를 "남은 회차를 확인하지 못했어요"로 옮기면 회원권이
    // 없는 사람에게 있을지도 모른다고 말하는 셈이다(unknown scope는 정말 모르는 것이라
    // 아래 `_RemainingUnknownBox`가 맞는 말이 된다).
    final summary = _scope == AccountDeletionScope.member
        ? ref.watch(myViewModelProvider).asData?.value
        : null;

    // 제출 중에는 이 화면을 벗어날 수 없다(P56 M2). DELETE가 날아가는 동안 시스템 백·AppBar
    // 뒤로가기로 화면이 pop되면 서버는 계정을 지웠는데 `!mounted`가 로그아웃·`/login` 이동·
    // 완료 안내를 **셋 다** 삼킨다 — 앱은 지워진 계정의 세션을 든 채 마이 탭에 남고, 이후
    // 모든 새로고침이 403이라 재설치가 유일한 탈출구가 된다. AppBar 뒤로가기도
    // `Navigator.maybePop`이라 같은 PopScope에 걸린다. [돌아가기] 버튼은 제출 중 비활성.
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: AppColors.page,
        // "회원탈퇴"는 회원에게만 맞는 말이다 — 대기실 계정(과 연결 여부를 모르는 계정)에는
        // 스토어 심사 용어이자 개인정보보호법의 용어인 "계정 삭제"를 쓴다.
        appBar: AppBar(
          title: Text(_scope == AccountDeletionScope.member ? '회원탈퇴' : '계정 삭제'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            children: [
              if (_scope == AccountDeletionScope.unknown)
                _ConnectionUnknownBanner(reason: widget.unknownReason),
              _WarningBox(
                text: _unlinked
                    ? unlinkedDeletionWarning(_trace)
                    : '탈퇴하면 되돌릴 수 없어요.\n같은 번호로 다시 가입해도 이전 기록은 복구되지 않아요.',
              ),
              // 조회에 실패했으면 **모른다고 말한다.** 상자를 그냥 빼면 "남은 회차 없음"과
              // 구별되지 않고, 회원은 정산할 게 있다는 사실을 되돌릴 수 없게 된 뒤에야 안다
              // (계약 v2.1의 3상태 규약 — 값 있음 / 없음 / 미상을 뭉개지 않는다).
              // 대기실 계정은 회원권 자체가 없으므로 이 상자를 그리지 않는다.
              if (!_unlinked)
                if (summary != null)
                  _RemainingBox(summary: summary)
                else
                  const _RemainingUnknownBox(),
              _PurgedCard(
                items: _unlinked ? unlinkedDeletionPurgedItems(_trace) : withdrawalPurgedItems,
              ),
              if (_unlinked) const _UnlinkedRetentionCard() else const _RetainedCard(),
              const SizedBox(height: 4),
              _AcknowledgeRow(
                value: _acknowledged,
                label: _unlinked
                    ? '위 내용을 모두 확인했고, 계정 삭제에 동의해요'
                    : '위 내용을 모두 확인했고, 탈퇴에 동의해요',
                onChanged: _submitting ? null : (v) => setState(() => _acknowledged = v),
              ),
              const SizedBox(height: 10),
              RiseButton(
                label: _submitting ? '처리 중…' : _primaryLabel,
                expand: true,
                // 이중 잠금: 체크 전에는 버튼이 잠기고, 눌린 뒤에도 _submit이 다시 확인한다
                // (이 저장소의 파괴적 동작 규약 — 비활성 버튼만 믿지 않는다).
                onPressed: (_acknowledged && !_submitting) ? _submit : null,
              ),
              const SizedBox(height: 8),
              RiseButton(
                label: '돌아가기',
                expand: true,
                style: RiseButtonStyleKind.outline,
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 실행 버튼·다이얼로그 확정 버튼의 라벨 — 회원은 "탈퇴", 나머지는 "삭제".
  String get _primaryLabel => _scope == AccountDeletionScope.member ? '탈퇴하기' : '삭제하기';

  Future<void> _submit() async {
    if (!_acknowledged || _submitting) return; // 이중 잠금
    if (!await _confirm()) return;
    if (!mounted) return;

    setState(() => _submitting = true);
    final result = await ref.read(myViewModelProvider.notifier).deleteAccount();
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        // 성공 뒤에는 이 계정으로 아무것도 부를 수 없다 — 세션을 정리하고 즉시 로그인으로.
        // 스낵바 메신저는 화면이 사라지기 **전에** 잡아 둔다(hold_request_sheet와 같은 순서).
        final messenger = ScaffoldMessenger.of(context);
        // 완료 안내는 **서버가 실제로 한 일**을 말한다(P63). 회원 scope는 세션에 회원 id가
        // 있었으니 회원 경로가 확정이고(구서버의 빈 응답도 회원 문구로 떨어져야 한다), 나머지
        // 둘은 서버 응답의 `member_id`로 어느 경로가 돌았는지를 안다 — 연결 여부를 모른 채
        // 열린 unknown scope도 여기서는 사실을 말할 수 있다. 미연결 문구의 "보낸 가입 요청"은
        // `purged.join_requests`가 1 이상일 때만 붙는다.
        final message = switch (_scope) {
          AccountDeletionScope.member => value.completionMessage,
          AccountDeletionScope.unlinked ||
          AccountDeletionScope.unknown =>
            value.ranUnlinkedPath ? value.unlinkedCompletionMessage(_trace) : value.completionMessage,
        };
        await _signOut();
        if (!mounted) return;
        // 여기서 직접 이동한다 — 대기실 scope(unlinked·unknown)는 세션이 없어 `app.dart`의 세션
        // 리스너가 돌지 않는다(null → null). 회원 scope에서는 리스너가 이미 보냈을 수 있고,
        // 그때는 같은 자리로 가는 무해한 중복이다. 값은 리스너와 같은 규칙에서 가져온다.
        context.go(sessionEndRoute(SessionEndReason.deleted));
        messenger.showSnackBar(riseSnackBar(message));
      case Err(:final failure):
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(riseSnackBar(failure.message, kind: RiseSnackKind.danger));
    }
  }

  /// 마지막 재확인. 여기서 처음 알리는 사실은 하나도 없다 — 화면이 이미 전부 말했고,
  /// 이 다이얼로그는 "지금 실행한다"만 묻는다.
  Future<bool> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(_unlinked ? '정말 삭제할까요?' : '정말 탈퇴할까요?'),
        content: Text(
          _unlinked
              // 대기실 계정 — 지워지는 건 둘뿐이고 그것만 말한다. 회원 문구의 "체형사진·
              // 인바디·수업 기록"은 이 사람에게 없는 것이라 여기서 되풀이하면 소음이다.
              // 가입 요청 쪽 문장은 화면 목록과 같은 trace를 따른다(같은 사람에게 두 말 금지).
              ? unlinkedDeletionConfirmText(_trace)
              : '탈퇴하면 되돌릴 수 없어요.\n\n'
                  '체형사진·인바디·수업 기록이 모두 삭제되고, 같은 번호로 다시 가입해도 복구되지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('그대로 두기'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_primaryLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false; // 배리어 탭 = 취소
  }

  /// 성공 뒤 로컬 정리 — Firebase 로그아웃 + 인증 플로우 상태 + 로컬 대기 기록 + 앱 세션.
  ///
  /// **인증 플로우 상태까지 버린다**(my_screen `_logout`과 같은 이유). `authViewModelProvider`는
  /// keepAlive라 방금 지운 계정의 전화번호·매칭 결과·대기 상태가 그대로 남고, 로그인 화면에
  /// 그 번호가 채워진 채 뜬다 — 한 기기를 두 회원이 쓰는 센터 태블릿·가족 공용폰에서 다음
  /// 사람이 남의 번호로 인증 문자를 보내게 된다. `restartWithNewPhone()`이 Firebase 로그아웃과
  /// 상태 초기화를 함께 한다(종전엔 `FirebaseAuth.signOut()`만 불러 상태가 남았다).
  ///
  /// **로컬 "가입 요청 보냄" 기록도 지운다.** 서버가 가입 요청을 파기했으므로(v2.27 ⑤) 이
  /// 기록은 이제 거짓이고, 남겨 두면 같은 번호로 다시 인증했을 때 보낸 적 없는 "승인 대기 중"
  /// 화면이 뜬다(session_restore가 번호를 대조해 복원한다). 회원 scope에서는 이미 비어 있어
  /// 무해하다(연결 시 `confirmMatch`가 지운다).
  ///
  /// **세션 clear는 mounted와 무관하게 한다**(P64 검증 반영). 서버는 이미 계정을 지웠다 —
  /// await 사이에 화면이 내려갔다고 세션을 남기면 지워진 계정의 세션을 든 채 셸에 남고, 이후
  /// 모든 요청이 403이다. notifier·저장소를 await **앞에서** 잡아 두는 이유다(unmount 뒤 `ref`는
  /// 못 쓴다). 재검증이 먼저 비웠다면 `clear()`가 재진입을 무시한다.
  Future<void> _signOut() async {
    final auth = ref.read(authViewModelProvider.notifier);
    final joinStore = ref.read(joinRequestStoreProvider);
    final session = ref.read(sessionProvider.notifier);
    try {
      await auth.restartWithNewPhone();
    } catch (_) {
      // dev 헤더 모드·Firebase 미초기화여도 로컬 정리는 계속한다(_logout과 같은 관용).
    }
    try {
      await joinStore.clear();
    } catch (_) {
      // 로컬 저장소 실패가 로그인 이동을 막으면 안 된다 — 다음 기동의 번호 대조가 한 번 더 막는다.
    }
    session.clear(reason: SessionEndReason.deleted);
  }
}

/// 연결 여부를 모르는 채 열린 경우([AccountDeletionScope.unknown])의 첫 줄.
///
/// 이 화면 아래는 **회원 쪽 고지 그대로**다. 이미 연결된 회원이 네트워크 실패로 대기실에
/// 섰거나(connectionUnknown) 재인증으로 매칭 카드에 다시 선 것일 수 있고(matched), 그때
/// 삭제하면 서버는 회원 경로(전체 파기)를 돈다 — 그 가능성을 숨기고 "가입 요청만 지워져요"
/// 라고 하면 그 사람의 사진·기록에 대한 거짓 고지가 된다. 반대로 아직 연결 전인 사람은 없는
/// 것에 대한 고지를 읽게 되지만, 과다 고지는 거짓이 아니다. 첫 줄은 [reason]대로 사실만 말한다.
class _ConnectionUnknownBanner extends StatelessWidget {
  const _ConnectionUnknownBanner({required this.reason});

  final AccountDeletionUnknownReason reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeWarnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.35)),
      ),
      // 문장은 도메인 파일(`connectionUnknownBannerText`)에 — 모르는 이유가 둘이라 여기서 bool로
      // 고를 수 없고, 서버가 실제로 하는 일과 한 줄씩 대응해야 하는 문장은 한 자리에 모은다.
      child: Text(
        connectionUnknownBannerText(reason),
        style: const TextStyle(fontSize: 12, height: 1.6, color: AppColors.badgeWarnFg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 비가역 경고 — 문장은 호출자가 정한다(회원 문구는 build, 대기실 문구는 도메인 파일의
/// `unlinkedDeletionWarning` — 가입 요청 흔적에 따라 세 갈래라 여기서 bool로 고를 수 없다).
class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeDanBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          height: 1.6,
          color: AppColors.badgeDanFg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 남은 회차 고지. 서버는 잔여가 있어도 탈퇴를 막지 않으므로(Guideline 5.1.1(v)),
/// **막는 대신 알린다** — 회원이 탈퇴 전에 정산할 기회를 갖는 유일한 지점이다.
class _RemainingBox extends StatelessWidget {
  const _RemainingBox({required this.summary});
  final MySummary summary;

  @override
  Widget build(BuildContext context) {
    final remaining = summary.passes
        .where((p) => p.isActive || p.isScheduled)
        .fold<int>(0, (sum, p) => sum + p.remaining);
    if (remaining <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeWarnBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warn.withValues(alpha: 0.35)),
      ),
      child: Text(
        '아직 $remaining회가 남아 있어요.\n'
        '탈퇴해도 자동으로 환불되지 않아요 — 정산은 센터와 따로 진행해야 해요.',
        style: const TextStyle(
          fontSize: 12,
          height: 1.6,
          color: AppColors.badgeWarnFg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 회원권 조회에 실패했을 때. **원인을 지목하지 않는다** — "남은 회차가 없어요"라고 말하면
/// 모르는 것을 아는 것처럼 말하게 되고, 그게 이 화면에서 가장 비싼 거짓말이다.
class _RemainingUnknownBox extends StatelessWidget {
  const _RemainingUnknownBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.badgeMutBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: const Text(
        '남은 회차를 확인하지 못했어요.\n'
        '남은 회차가 있다면 탈퇴해도 자동으로 환불되지 않아요 — 먼저 센터에 확인해주세요.',
        style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.badgeMutFg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 파기 목록 — 어떤 목록을 그릴지는 호출자(scope)가 정한다. 목록 자체는 도메인 파일에
/// 있다(서버가 실제로 하는 일과 한 줄씩 대응 — account_deletion.dart 헤더).
class _PurgedCard extends StatelessWidget {
  const _PurgedCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '삭제되는 정보'),
          for (var i = 0; i < items.length; i++)
            RiseRow(
              showDivider: i != items.length - 1,
              child: Text(items[i], style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _RetainedCard extends StatelessWidget {
  const _RetainedCard();

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '법에 따라 보관되는 정보'),
          for (var i = 0; i < withdrawalRetainedItems.length; i++)
            RiseRow(
              showDivider: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(withdrawalRetainedItems[i].item, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    withdrawalRetainedItems[i].reason,
                    style: const TextStyle(fontSize: 10, height: 1.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 9),
            child: Text(
              withdrawalRetentionNote,
              style: TextStyle(fontSize: 10, height: 1.6, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// 대기실 계정의 "남는 것" 카드 — 5년 보존 목록([_RetainedCard])을 그리지 않는다. 그 목록은
/// 회원권·결제·계약이 있어야 생기는 기록이고 이 계정에는 없다. 대신 이 삭제의 **범위 밖**에
/// 있는 것(센터 데스크가 따로 등록한 정보)과 그것을 지우는 다음 행동을 말한다.
class _UnlinkedRetentionCard extends StatelessWidget {
  const _UnlinkedRetentionCard();

  @override
  Widget build(BuildContext context) {
    return const RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(title: '여기서 지워지지 않는 정보'),
          Text(
            unlinkedDeletionRetentionNote,
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _AcknowledgeRow extends StatelessWidget {
  const _AcknowledgeRow({required this.value, required this.label, required this.onChanged});
  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: value,
                activeColor: AppColors.brand,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
