import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/features/auth/presentation/center_contact_provider.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/session/session_gone_view.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/features/auth/presentation/auth_view_model.dart';
import 'package:rise_member/features/my/domain/my_models.dart';
import 'package:rise_member/features/my/presentation/account_deletion_screen.dart';
import 'package:rise_member/features/my/presentation/my_view_model.dart';
import 'package:rise_member/features/my/presentation/widgets/center_coaches_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/consent_toggles.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_detail_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/contract_sign_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/contracts_row.dart';
import 'package:rise_member/features/my/presentation/widgets/legal_links_card.dart';
import 'package:rise_member/features/my/presentation/widgets/payments_card.dart';
import 'package:rise_member/features/my/presentation/widgets/hold_request_sheet.dart';
import 'package:rise_member/features/my/presentation/widgets/ledger_list.dart';
import 'package:rise_member/features/my/presentation/widgets/pass_list.dart';

/// 마이 탭 — 회원권 2개 · 원장 · 일시정지 신청 · 계약 · 동의 · 센터(목업 t-my).
class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myViewModelProvider);
    final selectedLedgerPassId = ref.watch(selectedLedgerPassIdProvider);

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(title: const Text('마이')),
      // **로그아웃·회원탈퇴·약관은 `async.when` 바깥이다**(P56 B4). 이 세 줄은 회원 데이터를
      // 한 글자도 안 쓴다. 종전엔 `data` 브랜치 안에 있어서 요약 로드가 한 번 실패하면 넷이
      // 동시에 사라졌다 — 로그아웃도, 탈퇴도, 법정 고지도. 서버가 지속 403을 주는 계정(권한
      // 상실·탈퇴 잔여 인덱스)은 401이 아니라 세션도 안 비워지고(api_result_guard는 401만
      // 로그아웃 신호로 본다), 회원은 재시도 버튼 하나뿐인 화면에 갇혀 **재설치가 유일한
      // 탈출구**였다. 로딩 중에도 보인다 — dio 타임아웃 20초 동안 스피너만 보고 있을 이유가 없다.
      //
      // 새로고침은 상태와 무관하게 늘 열려 있다(에러 상태의 [다시 시도]와 같은 일을 한다).
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          // 홀딩 상한(policy.holdLimitLabel)이 이 탭에 노출되므로 정책 동반 재조회.
          ref.invalidate(centerPolicyProvider);
          // 스태프 캐시도 동반 — 회원권 목록의 담당 코치 이름·"(퇴사)" 표기가
          // 이 캐시에서 나온다(staff_directory: 출처 단일화). 캐시만 버리면
          // 화면은 그대로이므로 아래 refresh()와 **쌍으로** 있어야 한다.
          ref.invalidate(staffMapProvider);
          ref.read(myViewModelProvider.notifier).refresh();
        },
        child: ListView(
          // 콘텐츠가 화면보다 짧아도 pull-to-refresh 당김이 동작하게.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          children: [
            ...async.when(
              loading: () => const [_LoadingBlock()],
              // 세션 소멸은 에러가 아니라 **전환 중**이다 — 재시도 버튼을 그리지 않는다(P64).
              // 아래 로그아웃·탈퇴 행은 when 바깥이라 그대로 보인다(전환 뷰에 갇혔을 때의
              // 또 하나의 탈출구).
              error: (e, _) => [
                if (e is SessionGoneFailure)
                  const SizedBox(height: 120, child: SessionGoneView())
                else
                  RiseErrorView(
                    message: e is Failure ? e.message : null,
                    // 홀딩 상한 문구가 이 탭에 있으므로 재시도 때 정책도 재조회
                    // — 실패 폴백/구정책 고착 방지(center_policy_provider 주석 참조).
                    onRetry: () {
                      ref.invalidate(centerPolicyProvider);
                      ref.invalidate(staffMapProvider);
                      ref.invalidate(myViewModelProvider);
                    },
                  ),
              ],
              data: (summary) => _summaryCards(context, ref, summary, selectedLedgerPassId),
            ),
            const LegalLinksCard(),
            const _CenterCard(),
          ],
        ),
      ),
    );
  }

  /// 회원 데이터가 있어야 그릴 수 있는 카드들 — 회원권·원장·결제·계약·동의.
  List<Widget> _summaryCards(
    BuildContext context,
    WidgetRef ref,
    MySummary summary,
    String? selectedLedgerPassId,
  ) {
    final ledgerPass = summary.passes.isEmpty ? null : _ledgerPass(summary, selectedLedgerPassId);
    return [
      PassList(
        passes: summary.passes,
        onHoldTap: () => _showHold(context, summary),
      ),
      if (ledgerPass != null) ...[
        // 패스 2개 이상 — 칩으로 원장(이용 내역·환불 예상액) 대상 패스 전환.
        if (summary.passes.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              children: [
                for (final p in summary.passes)
                  RiseChip(
                    // "어떤 패스의 원장을 볼지" 고르는 칩 — 코치 이름은
                    // 패스 구분용 꼬리표라 퇴사 표기는 붙이지 않는다
                    // (마이 탭 앵커는 위 PassList 행. pass_list.dart 주석).
                    // 빈 조각(미해석 이름·빈 상품명)은 joinDot이 버린다.
                    label: CoachLabel.joinDot([p.product, p.trainerName]),
                    selected: p.id == ledgerPass.id,
                    onTap: () => ref.read(selectedLedgerPassIdProvider.notifier).select(p.id),
                  ),
              ],
            ),
          ),
        LedgerList(
          passLabel: ledgerPass.product,
          entries: summary.ledgerByPass[ledgerPass.id] ?? const [],
          failed: summary.ledgerFailedFor(ledgerPass.id),
        ),
        // 환불 예상액은 회원 앱에서 보여주지 않는다(P39) — 상시 노출은
        // 환불 유도로 읽히고, 앱 숫자가 앵커가 되어 데스크 협의 금액과
        // 다르면 분쟁의 씨앗이 된다. 견적은 어드민(RefundQuoteModal,
        // POST /v1/passes/{id}/refund-quote)에서 데스크 상담과 함께 본다.
      ],
      PaymentsCard(
        payments: summary.payments,
        failed: summary.paymentsFailed,
      ),
      ContractsRow(
        contracts: summary.contracts,
        consent: summary.consent,
        contractsFailed: summary.contractsFailed,
        consentFailed: summary.consentFailed,
        // 환불된 거래의 계약은 서명이 서버에서 400 — 계약 목록만으론
        // 알 수 없어(status는 아직 sent) 패스 쪽 사실을 함께 넘긴다.
        refundedPassIds: {
          for (final p in summary.passes)
            if (p.status == 'refunded') p.id,
        },
        onConsentTap: () => showConsentToggles(
          context,
          consent: summary.consent,
          // 조회 실패면 시트가 읽기 전용으로 뜬다 — 이 인자를 빠뜨리면
          // 기본값 저장이 실제 동의를 철회한다(consent_toggles 주석).
          consentUnknown: summary.consentFailed,
        ),
        onSignTap: (contract) => showContractSignSheet(
          context,
          contract: contract,
          // 체결 완료 단계의 [계약서 보기](P44) — 서명 시트가 닫힌 **뒤**
          // 살아 있는 이 화면의 context로 상세를 연다(시트 자신의 context는
          // pop과 함께 죽는다). 인자는 재조회 반영본(서명 이미지·체결 정보).
          onViewSigned: (updated) => showContractDetailSheet(
            context,
            contract: updated,
            penaltyRate: updated.penaltyRate,
          ),
        ),
        onDetailTap: (contract) => showContractDetailSheet(
          context,
          contract: contract,
          penaltyRate: contract.penaltyRate,
        ),
      ),
    ];
  }

  PassDetail _primaryPass(MySummary summary) {
    for (final p in summary.passes) {
      if (p.isActive) return p;
    }
    return summary.passes.first;
  }

  /// 원장 카드 대상 패스 — 칩 선택값이 유효하면 그 패스, 아니면 대표 패스.
  PassDetail _ledgerPass(MySummary summary, String? selectedId) {
    if (selectedId != null) {
      for (final p in summary.passes) {
        if (p.id == selectedId) return p;
      }
    }
    return _primaryPass(summary);
  }

  void _showHold(BuildContext context, MySummary summary) {
    if (summary.passes.isEmpty) return;
    showHoldRequestSheet(
      context,
      passes: summary.passes,
      initialPassId: _primaryPass(summary).id,
    );
  }
}

/// 요약 로딩 자리 — 스피너를 리스트 안에 둔다(전체 화면 `Center`가 아니다). 아래에
/// 약관·센터 카드가 이미 그려져 있어야 하기 때문이다(build 주석).
class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 72),
      child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
    );
  }
}

class _CenterCard extends ConsumerWidget {
  const _CenterCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "+ 다른 센터 가입 요청" 행은 탭 핸들러 없는 데드엔드라 제거(UX 여정 검수)
    // — 다른 센터 가입은 로그인 플로우의 가입 요청 경로가 담당한다.
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '센터'),
          RiseRow(
            // 서버 상호(어드민 "센터 신원") 우선, 미등록이면 임시 상수(P56 L10).
            child: Text(ref.watch(centerDisplayNameProvider)),
            trailing: const RiseBadge('현재', variant: RiseBadgeVariant.brand),
          ),
          // 코치 소개(P40) — 담당 코치 프로필은 홈·예약에서 열리지만, "이 센터에
          // 어떤 코치들이 있는지"는 여기가 유일한 진입점이다(데이터는 staffMap 캐시).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showCenterCoachesSheet(context),
            child: const RiseRow(
              minHeight: 44,
              // "센터" 접두 — 예약 탭의 "코치 소개"(담당 코치 1명 프로필)와 대상이
              // 달라서, 같은 라벨이면 "다른 코치들은 어디 갔지"가 된다.
              child: Text('센터 코치 소개'),
              trailing: RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.muted),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _logout(context, ref),
            child: const RiseRow(
              minHeight: 44,
              child: Text('로그아웃', style: TextStyle(color: AppColors.muted)),
              trailing: RiseIcon(RiseIcons.logout, size: 14, color: AppColors.muted),
            ),
          ),
          // 회원탈퇴(계약 v2.11 · App Store Guideline 5.1.1(v) — 계정 생성을 지원하는 앱은
          // **앱 안에서** 계정 삭제를 제공해야 한다). 로그아웃 바로 아래에 두되 danger 색으로
          // 구분한다 — 두 행이 같은 무게로 보이면 오탭이 되돌릴 수 없는 결과를 낳는다.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openAccountDeletion(context),
            child: const RiseRow(
              showDivider: false,
              minHeight: 44,
              child: Text('회원탈퇴', style: TextStyle(color: AppColors.danger)),
              trailing: RiseIcon(RiseIcons.chevronRight, size: 14, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  /// 탭 셸 밖의 전체 화면으로 올린다(QrScanScreen과 같은 방식) — 딥링크가 생기면 안 되는
  /// 화면이라 go_route로 만들지 않았다. rootNavigator라 하단 탭바 위로 덮인다.
  void _openAccountDeletion(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => const AccountDeletionScreen()),
    );
  }

  /// P06 세션 복원의 짝 — Firebase 로그아웃 + 앱 세션 clear 후 로그인 스택으로.
  ///
  /// **인증 상태도 함께 버린다.** `authViewModelProvider`는 `keepAlive`라
  /// 로그아웃해도 살아남는데, 거기엔 직전 회원의 **전화번호와 매칭 결과**가 들어
  /// 있다. 안 지우면 다음 사람이 로그인 화면에서 **남의 번호가 채워진 걸** 보고,
  /// 그대로 누르면 인증 문자가 **그 사람 폰으로 간다.** 남아 있던
  /// `joinRequestedAt` 때문에 보낸 적 없는 "센터 승인을 기다리는 중" 화면이 뜨기도
  /// 한다(한 기기를 두 회원이 쓰는 센터 태블릿·가족 공용폰).
  ///
  /// `restartWithNewPhone()`이 정확히 그 정리를 하는 함수인데 이 경로만 부르지
  /// 않고 있었다 — Firebase 로그아웃까지 그쪽이 하므로 중복도 없다.
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authViewModelProvider.notifier).restartWithNewPhone();
    } catch (_) {
      // Firebase 미초기화/미로그인(dev 헤더 모드)이어도 로컬 세션은 정리한다.
    }
    ref.read(sessionProvider.notifier).clear(reason: SessionEndReason.signedOut);
    // 리스너(`app.dart`)와 **같은 값**으로 간다 — 하드코딩 '/login'은 지금은 같지만 착지 규칙이
    // 바뀌면 두 곳이 갈린다. 리스너가 이미 보냈다면 같은 자리로 가는 무해한 중복이다.
    if (context.mounted) context.go(sessionEndRoute(SessionEndReason.signedOut));
  }
}
