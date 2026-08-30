import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/empty_passes_view.dart';
import 'package:rise_member/features/consult/presentation/widgets/consult_request_cta.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/core/widgets/time_boundary_builder.dart';
import 'package:rise_member/features/home/domain/home_models.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';
import 'package:rise_member/features/home/presentation/qr_scan_screen.dart';
import 'package:rise_member/features/home/presentation/widgets/home_coach_card.dart';
import 'package:rise_member/features/home/presentation/widgets/homework_checklist_card.dart';
import 'package:rise_member/features/home/presentation/widgets/next_booking_card.dart';
import 'package:rise_member/features/home/presentation/widgets/pass_switcher_chips.dart';
import 'package:rise_member/features/home/presentation/widgets/remaining_ring.dart';

/// 홈 탭 — 패스 스위처 칩 · 다음 예약 · Home Work 체크리스트 · 잔여 링(목업 t-home).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeViewModelProvider);
    final session = ref.watch(sessionProvider);
    final checkedInBookingId = ref.watch(checkedInBookingIdProvider);
    final policy = ref.watch(centerPolicyProvider).value ?? CenterPolicy.fallback;

    // 가진 회원권이 **전부 만료·환불**인 상태. 회원권 0개(EmptyPassesFailure)와 달리
    // 서버 응답은 정상이라 AsyncError가 아니다 — 던지지 않는 이유는
    // [HomeSummary.hasUsablePass] 주석 참조(예약 탭이 같은 요약을 받아 만료·환불
    // 패스를 PassNotUsable로 직접 안내하고 있다).
    //
    // 홈은 대신 **헤더 배지와 본문을 통째로 뺀다**. 그리는 순간 환불된 회원권이
    // 잔여 링 + 담당 코치 + 다음 예약까지 갖춘 "이용 중인 회원권"으로 보인다 —
    // 스위처 칩의 "(환불)" 한 조각으로는 그 인상을 뒤집지 못한다.
    final summary = async.value;
    // **에러일 땐 이 분기로 가지 않는다.** riverpod은 새로고침 중에도 직전 값을
    // 유지하므로(`async.value`), 이 조건만 보면 만료 상태에서 새로고침이 실패해도
    // `noUsablePass`가 계속 참이라 **아래 `async.when`에 영영 도달하지 못한다** —
    // 회원은 새로고침을 눌러도 아무 반응이 없는 화면을 본다(앱이 멈춘 걸로 읽힌다).
    final noUsablePass =
        summary != null && !summary.hasUsablePass && !async.hasError;

    // 부분 실패 알림 — 화면을 치우지 않고 스낵바로만 알리는 자리들이 여기 모인다.
    //  · Home Work 토글: 낙관적 UI가 조용히 되돌아가는 것
    //  · 회원권 칩 전환: 보고 있던 홈을 유지한 채 "안 바뀌었다"만 알리는 것
    //
    // 문구를 실패 종류로 가르지 않는 이유: 회원에게 필요한 건 "무엇이 안 됐나"이고
    // 그건 서버 메시지가 이미 말한다. 종전엔 "체크 저장에 실패했어요"로 고정돼
    // 있어서, 칩 전환 실패에도 하지도 않은 체크 얘기가 나왔다.
    ref.listen(homeworkToggleErrorProvider, (_, failure) {
      if (failure == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        riseSnackBar(failure.message, kind: RiseSnackKind.danger),
      );
      ref.read(homeworkToggleErrorProvider.notifier).clear();
    });

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          children: [
            _HomeHeader(
              memberName: session?.memberName,
              // 헤더는 async.when 밖이라 본문만 갈아끼우면 "PT 20회 · 잔여 8" 배지와
              // "담당 정혜린 코치"가 빈 상태 위에 그대로 떠 있는다.
              summary: noUsablePass ? null : summary,
            ),
            Expanded(
              child: noUsablePass
                  ? EmptyPassesView(
                      title: '이용 가능한 회원권이 없어요',
                      // 회원이 아는 사실("나 회원권 있었는데")과 화면이 말하는 것을
                      // 잇는다 — 이유를 말하지 않으면 앱이 고장 난 것으로 읽힌다.
                      message: '만료·환불된 회원권만 남아 있어요\n센터에서 재등록하면 다시 이용할 수 있어요',
                      // 재등록 요청(v2.20) — 이 문구가 데드엔드였던 시절의 끝.
                      action: const ConsultRequestCta(),
                      onRefresh: () {
                        ref.invalidate(centerPolicyProvider);
                        ref.invalidate(staffMapProvider);
                        ref.invalidate(homeViewModelProvider);
                      },
                    )
                  : async.when(
                    loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
                    error: (e, _) => e is EmptyPassesFailure
                        // 회원권 0개는 에러가 아니라 온보딩 성격의 빈 상태(전용 뷰 — 예약 탭과 공용).
                        // 새로고침 때 정책도 재조회 — 실패 폴백/구정책이 세션 내내 고착되지
                        // 않게(center_policy_provider 주석 참조).
                        ? EmptyPassesView(onRefresh: () {
                            ref.invalidate(centerPolicyProvider);
                            ref.invalidate(homeViewModelProvider);
                          })
                        : RiseErrorView(
                            message: e is Failure ? e.message : null,
                            onRetry: () {
                              ref.invalidate(centerPolicyProvider);
                              ref.invalidate(staffMapProvider);
                              ref.invalidate(homeViewModelProvider);
                            },
                          ),
                    data: (summary) => RefreshIndicator(
                      color: AppColors.red,
                      onRefresh: () async {
                        // 대표가 컷오프를 축소해도 재로그인 없이 pull-to-refresh로 반영
                        // — 안 하면 취소 버튼이 사일런트 데드엔드가 된다(정책 provider 주석).
                        ref.invalidate(centerPolicyProvider);
                        // 스태프 캐시도 동반 — 홈의 코치 이름·"(퇴사)" 표기는 이제
                        // 이 캐시에서 나오므로(staff_directory: 출처 단일화),
                        // 캐시를 버리고 뷰모델을 새로고침해야 라벨까지 새 값이 된다.
                        // 순서 무관: 뷰모델이 로드하며 캐시를 다시 읽는다.
                        ref.invalidate(staffMapProvider);
                        ref.read(homeViewModelProvider.notifier).refresh();
                      },
                      child: ListView(
                        // 콘텐츠가 화면보다 짧아도 pull-to-refresh 당김이 동작하게.
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                        children: [
                          PassSwitcherChips(
                            passes: summary.passes,
                            selectedId: summary.selectedPassId,
                            onSelect: (id) => ref.read(homeViewModelProvider.notifier).selectPass(id),
                          ),
                          const SizedBox(height: 4),
                          NextBookingCard(
                            booking: summary.nextBooking,
                            checkedInBookingId: checkedInBookingId,
                            cutoffHours: policy.cancelCutoffHours,
                            cutoffUnknown: policy.isFallback,
                            onCheckIn: () => _handleCheckIn(context, ref),
                          ),
                          // 담당 코치 — 서버가 이미 내려준 프로필을 홈에서 쓴다
                          // (staffMapProvider는 홈이 이미 watch 중이라 왕복 0).
                          HomeCoachCard(
                            trainerId: summary.selectedPass.trainerId,
                            trainerName: summary.selectedPass.trainerName,
                            trainerInactive: summary.selectedPass.trainerInactive,
                          ),
                          // 이 카드는 **오늘 날짜 문서 하나**를 읽고 쓴다 — 자정을
                          // 넘기면 낡은 판정이 아니라 아예 다른 문서를 보고 있는
                          // 셈이다(요일 스케줄에 따라 배정 항목까지 달라진다).
                          // 그래서 다른 카드들과 달리 자정에 **재조회**가 필요하다.
                          // 왜 여기서만 왕복을 쓰는지는
                          // [HomeViewModel.refreshIfDateRolled] 주석에 남겼다.
                          TimeBoundaryBuilder(
                            atMidnight: true,
                            builder: (context, now) {
                              _syncHomeworkDate(context, ref, summary, now);
                              return HomeworkChecklistCard(
                                items: summary.homeworkItems,
                                done: summary.homeworkDone,
                                total: summary.homeworkTotal,
                                checksFailed: summary.homeworkChecksFailed,
                                onToggle: (item) =>
                                    ref.read(homeViewModelProvider.notifier).toggleHomework(item),
                              );
                            },
                          ),
                          // 이 카드의 두 표시는 **날짜가 바뀌면 뜻이 달라진다**: 유효기간
                          // D-day(PassOption.daysUntilExpiry)와 "일시정지 중" 배지
                          // (activeHold). 둘 다 부를 때 DateFmt.todayKst()를 다시 읽는
                          // getter지만, 홈 탭은 indexedStack에 상주해서
                          // (core/router/app_router.dart) 아무도 리빌드해 주지 않는다 —
                          // 자정을 넘겨도 "D-1"이 그대로 남는다. 마지막 날을 놓치면 잔여
                          // 회차가 통째로 소멸하고 되돌릴 방법이 없으므로, 자정마다 이
                          // 카드만 다시 그린다(서버 왕복 0 — TimeBoundaryBuilder 주석).
                          TimeBoundaryBuilder(
                            atMidnight: true,
                            builder: (context, _) => RiseCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const RiseCardHeader(title: '내 회원권'),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      RemainingRing(
                                        remaining: summary.selectedPass.remaining,
                                        total: summary.selectedPass.totalSessions,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              // 담당 코치 미배정/미해석이면 " · " 꼬리를
                                              // 아예 생략(마이 탭 PassList와 동일 규칙).
                                              // 상품명이 비어도 같은 규칙 — joinDot이 빈
                                              // 조각을 버려 " · 정혜린"이 남지 않게 한다.
                                              // 퇴사 표기는 여기 붙이지 않는다 — 헤더와
                                              // 스위처 칩이 이미 말했다(화면당 1~2회 규약).
                                              CoachLabel.joinDot([
                                                summary.selectedPass.product,
                                                summary.selectedPass.trainerName,
                                              ]),
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '유효기간 ${DateFmt.isoDate(summary.selectedPass.validUntil)} (${summary.selectedPass.expiryLabel})',
                                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                // 홀딩 중이면 마이 탭과 동일 판정(PassHold)의 배지 노출.
                                                if (summary.selectedPass.activeHold case final hold?)
                                                  RiseBadge(
                                                    '일시정지 중 ~${hold.to.month}/${hold.to.day}',
                                                    variant: RiseBadgeVariant.warn,
                                                  ),
                                                // **조건 없이 항상 켜져 있던 배지였다.**
                                                // 문제가 둘: ① 늘 노란 경고라 정작
                                                // D-3에 아무 신호도 못 된다 ② "연장
                                                // 상담 가능"은 회원이 앱에서 갈 경로가
                                                // 없는 약속이었다. v2.20에서 그 경로
                                                // (재등록 요청)가 생겨, 경고가 뜰 때만
                                                // 옆에 손잡이를 함께 세운다 — 배지는
                                                // 여전히 사실만 말하고, 행동은 CTA가
                                                // 맡는다(상태/행동 분리).
                                                if (_passAlert(summary.selectedPass, policy)
                                                    case final alert?) ...[
                                                  RiseBadge(alert,
                                                      variant: RiseBadgeVariant.warn),
                                                  const ConsultRequestCta(compact: true),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 화면이 들고 있는 Home Work가 **오늘 것이 아니면** 다시 읽어 오게 한다.
  ///
  /// [TimeBoundaryBuilder]가 자정에(그리고 탭 복귀·앱 재개에) 이 build를 다시
  /// 돌려 주므로, 여기서 날짜 한 번 비교하는 것이 트리거 전부다.
  ///
  /// **프레임 뒤로 미루는 이유**: provider를 위젯 build 도중에 건드리면 Riverpod가
  /// "Tried to modify a provider while the widget tree was building"으로 막는다.
  /// 이 프레임은 (아직 어제인) 목록을 그대로 그리고, 재조회는 그 직후에 시작한다.
  void _syncHomeworkDate(BuildContext context, WidgetRef ref, HomeSummary summary, DateTime now) {
    if (summary.homeworkDate == DateTime(now.year, now.month, now.day)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 그 사이 로그아웃·라우트 교체로 화면이 사라졌을 수 있다.
      if (!context.mounted) return;
      ref.read(homeViewModelProvider.notifier).refreshIfDateRolled();
    });
  }

  /// 셀프 체크인 — 데스크 QR을 실제로 스캔한 뒤 그 원문을 서버로 보낸다(P44).
  ///
  /// 스캐너는 **루트 네비게이터**로 띄운다: 탭 셸 안쪽 네비게이터에 push하면
  /// 바텀탭이 남은 채로 프리뷰가 잘린다. 취소(null)면 아무 요청도 보내지 않는다.
  ///
  /// 잘못된 QR·시간창 밖은 서버가 400으로 거른다 — 그 문구(`{"error":...}`)를
  /// guardApi가 [RejectedFailure]로 옮겨 담으므로 여기서는 그대로 보여주기만 한다.
  Future<void> _handleCheckIn(BuildContext context, WidgetRef ref) async {
    final scanned = await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(),
        fullscreenDialog: true,
      ),
    );
    if (scanned == null || !context.mounted) return;

    final result = await ref.read(homeViewModelProvider.notifier).checkIn(scannedToken: scanned);
    if (!context.mounted) return;
    final (message, kind) = switch (result) {
      // 체크인은 출석 확인일 뿐 — 세션 차감(원장 -1)은 코치의 완료 처리 시점(P4).
      Ok() => ('출석 완료! 세션 차감은 수업 완료 처리 후 반영돼요', RiseSnackKind.ok),
      Err(:final failure) => (failure.message, RiseSnackKind.danger),
    };
    ScaffoldMessenger.of(context).showSnackBar(riseSnackBar(message, kind: kind));
  }
}

/// 회원권 카드의 경고 한 줄 — **말할 게 있을 때만** 돌려준다.
///
/// 유효기간을 먼저 본다: 기간이 끝나면 잔여 회차가 통째로 소멸하므로 되돌릴 수 없는
/// 쪽을 먼저 말해야 한다.
///
/// 임계값은 **센터가 정한 값**(policy.expiring_days)이다. 앱이 임의 상수를 쓰면 대표가
/// 설정 화면에서 바꾼 기준과 회원이 보는 경고가 갈린다 — 어드민 대시보드의 "만료임박"
/// 목록도 같은 값을 쓴다.
///
/// 회원이 앱에서 할 수 있는 행동이 없으므로 **행동을 지시하지 않는다.** 없는 경로를
/// 가리키느니 사실만 말하고 데스크에서 처리하게 두는 편이 정직하다.
String? _passAlert(PassOption pass, CenterPolicy policy) {
  final d = pass.daysUntilExpiry;
  if (d < 0) return '유효기간이 지났어요';
  if (d <= policy.expiringDays) {
    return d == 0 ? '오늘까지예요 · 잔여 ${pass.remaining}회' : 'D-$d · 잔여 ${pass.remaining}회';
  }
  if (pass.remaining <= 0) return '잔여 회차를 다 썼어요';
  if (pass.remaining <= _lowRemainingThreshold) return '잔여 ${pass.remaining}회 남았어요';
  return null;
}

/// 잔여 회차 경고 임계. 센터 정책에 대응 필드가 없어 앱 상수다 — 어드민 대시보드의
/// "잔여 부족" 목록 기준(3회 미만)과 맞췄다. 정책 필드가 생기면 그쪽으로 옮긴다.
const _lowRemainingThreshold = 3;

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.memberName, required this.summary});
  final String? memberName;
  final HomeSummary? summary;

  /// "담당 정혜린 코치" / 퇴사면 "담당 정혜린 코치 (퇴사)". 구분자는 붙이지 않는다
  /// — 앞 조각(회원 이름)이 없을 수도 있어 잇는 일은 [CoachLabel.joinDot]이 한다.
  ///
  /// 이름을 해석하지 못하면(미배정이거나 /v1/staff 미적중) null — 문구를 통째로
  /// 생략한다. 예전엔 `?? ''`라 "담당  코치"처럼 빈자리가 그대로 렌더됐고,
  /// trim 판정만 하고 원본을 보간해 " 정혜린 "이 "담당  정혜린  코치"로 샜다.
  ///
  /// 홈 탭의 **퇴사 표기 앵커** 두 곳 중 하나(다른 하나는 패스 스위처 칩).
  /// "담당 X 코치"는 이 화면에서 담당 코치가 누구인지 말하는 문장 그 자체라
  /// 여기 붙이고, 회원권 카드·다음 예약 카드의 부차적 언급엔 붙이지 않는다.
  String? _coachAnchor(HomeSummary? summary) {
    if (summary == null) return null;
    final pass = summary.selectedPass;
    final name = CoachLabel.nameOrNull(pass.trainerName);
    if (name == null) return null;
    return CoachLabel.tag('담당 $name 코치', inactive: pass.trainerInactive);
  }

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    // 이름은 정규화 후 판정 — 공백뿐인 이름("  ")도 미해석과 같게 센터명으로 떨어진다.
    final name = CoachLabel.nameOrNull(memberName);
    final who = name == null ? AppConfig.centerFullName : '$name 님';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 센터 이름 로고 — 세 조각 모두 비유연이라, 좁은 기기 + 큰 글꼴
                // 배율에서 이 Row가 먼저 터졌다(배지보다 이쪽이 원인이었다).
                // scaleDown은 **안 들어갈 때만** 축소한다: 지금의 모든 화면에서는
                // 1:1로 그대로 그려지고, 물리적으로 못 담을 때만 브랜드 이름을
                // 글자째 잘라내는 대신 통째로 줄인다(말줄임하면 "라이즈 컨디셔…").
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text('라이즈 ', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                      Text('컨디셔닝', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: AppColors.red)),
                      // 여기 있던 아래 화살표(chevronDown)를 뺐다. **펼칠 게 없는데
                      // 드롭다운처럼 생겼다** — 이 앱은 센터가 하나고 전환 기능이
                      // 없으며, 아이콘은 `const FittedBox` 안이라 탭 핸들러조차
                      // 없었다. 눌러도 아무 일 없는 어포던스는 회원에게 "이 앱은
                      // 반응이 없다"로 읽힌다(마이 탭의 "다른 센터 가입 요청"을
                      // 같은 이유로 이미 제거했다).
                    ],
                  ),
                ),
                Text(
                  // 회원 이름이 비면 센터명으로 대체하되 **담당 코치 앵커는 남긴다**
                  // — 예전엔 이름이 없으면 퇴사 표기까지 통째로 사라져, 이름을 못
                  // 받은 회원만 담당 코치가 바뀐 사실을 홈에서 못 보게 됐다.
                  CoachLabel.joinDot([who, _coachAnchor(summary)]),
                  style: AppTypography.headerSubtitle,
                ),
              ],
            ),
          ),
          if (summary != null)
            // Flexible — 배지 라벨은 상품명(서버 문자열) + 잔여라 길이 상한이 없다.
            // 비유연이면 헤더 Row가 RenderFlex 오버플로를 낸다. 다 들어갈 땐 지금과
            // 같은 자연 크기로 렌더되고, 넘칠 때만 배지 안에서 말줄임된다.
            Flexible(
              child: RiseBadge(
                // 상품명이 비면 " · 잔여 8"처럼 구분자가 매달린다 — 회원권 카드 줄과
                // 같은 규칙으로 빈 조각을 버린다.
                CoachLabel.joinDot([
                  summary.selectedPass.product,
                  '잔여 ${summary.selectedPass.remaining}',
                ]),
                variant: RiseBadgeVariant.red,
              ),
            ),
        ],
      ),
    );
  }
}
