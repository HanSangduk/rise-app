import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rise_member/core/api/dto/staff_dto.dart';
import 'package:rise_member/core/api/staff_directory.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/policy/center_policy_provider.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/session/session_provider.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/empty_passes_view.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/core/widgets/rise_error_view.dart';
import 'package:rise_member/core/widgets/rise_snack_bar.dart';
import 'package:rise_member/core/widgets/time_boundary_builder.dart';
import 'package:rise_member/core/widgets/trainer_avatar.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';
import 'package:rise_member/features/booking/presentation/booking_view_model.dart';
import 'package:rise_member/features/booking/presentation/widgets/booking_confirm_sheet.dart';
import 'package:rise_member/features/booking/presentation/widgets/date_strip.dart';
import 'package:rise_member/features/booking/presentation/widgets/my_bookings_list.dart';
import 'package:rise_member/features/booking/presentation/widgets/slot_list.dart';
import 'package:rise_member/features/booking/presentation/widgets/trainer_profile_sheet.dart';
import 'package:rise_member/features/home/presentation/home_view_model.dart';

/// 예약 탭 — 내 코치/전체 토글 · 날짜 스트립 · 슬롯 리스트 · 내 예약(목업 t-book).
class BookingScreen extends ConsumerWidget {
  const BookingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingViewModelProvider);
    final showMyCoachOnly = ref.watch(showMyCoachOnlyProvider);
    final memberId = ref.watch(sessionProvider)?.memberId ?? '';
    final policy = ref.watch(centerPolicyProvider).value ?? CenterPolicy.fallback;
    // 코치 프로필(P05) — 스태프 캐시를 화면 로드와 병행으로 워밍해두고, 칩/태그
    // 탭 시점엔 조회만 한다(탭당 네트워크 호출 0). 미적중 시 이름만으로 폴백.
    final staffMap = ref.watch(staffMapProvider).value;

    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(title: const Text('예약')),
      // 자정을 넘기면 이 탭은 **통째로 못 쓰는 화면**이 된다: 선택 날짜가 어제로
      // 남아 날짜 칩이 하나도 선택되지 않고 슬롯 13칸이 전부 "지남"으로 그려진다
      // (`SelectedBookingDate` 주석 — 앱을 껐다 켜기 전엔 안 풀렸다).
      //
      // 본문 전체를 감싸는 이유는 세 가지가 같은 자정에 함께 맞아야 하기 때문이다:
      //  ① 선택 날짜를 오늘로 당긴다(아래 [_rolloverSelectedDate]).
      //  ② `DateStrip`이 새 "오늘"부터 14일을 다시 그린다.
      //  ③ `MyBookingsList`의 다가오는 예약 필터가 새 `now`로 다시 걸린다.
      // 로딩·에러 상태에서도 돌아야 해서 `async.when` **바깥**에 둔다.
      body: TimeBoundaryBuilder(
        atMidnight: true,
        builder: (context, now) {
          _rolloverSelectedDate(context, ref, now);
          return async.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.red)),
            error: (e, _) => e is EmptyPassesFailure
                // 회원권 0개는 에러가 아니라 온보딩 성격의 빈 상태 — 홈과 동일한 전용 뷰.
                // booking build는 homeViewModelProvider.future를 watch하므로 booking만
                // invalidate하면 홈이 캐시한 에러/빈 상태를 그대로 재수령한다(네트워크 0회)
                // — 홈을 함께 invalidate해야 실제 재조회가 일어난다(booking은 watch
                // 연쇄로 자동 재빌드). 정책도 함께 재조회(컷오프 변경 반영 — provider 주석 참조).
                ? EmptyPassesView(
                    onRefresh: () {
                      ref.invalidate(centerPolicyProvider);
                      ref.invalidate(homeViewModelProvider);
                      ref.invalidate(bookingViewModelProvider);
                    },
                  )
                : RiseErrorView(
                    message: e is Failure ? e.message : null,
                    // 에러가 홈 캐시에서 온 경우도 동일 — 홈·정책 동반 invalidate.
                    // 스태프 캐시도 함께 — 실패(AsyncError)가 화면 구독으로 살아있는 동안
                    // 고착되지 않게 재조회(staff_directory 주석 참조).
                    onRetry: () {
                      ref.invalidate(centerPolicyProvider);
                      ref.invalidate(staffMapProvider);
                      ref.invalidate(homeViewModelProvider);
                      ref.invalidate(bookingViewModelProvider);
                    },
                  ),
            data: (data) {
              // "내 코치" 칩이 쓰는 담당 코치 상태 — 이름 미해석(null/"")과 퇴사를
              // 한 번만 판정해 칩 라벨·아바타·"코치 소개" 링크가 같은 답을 쓰게 한다.
              // 이름은 정규화된 값(nameOrNull)만 쓴다 — 원본을 다시 보간하면
              // " 정혜린 "이 "내 코치 ( 정혜린  · 퇴사)"로 새어 나온다(CoachLabel 주석).
              final coachName = CoachLabel.nameOrNull(data.primaryPass.trainerName);
              final primaryInactive = data.primaryPass.trainerInactive;
              return RefreshIndicator(
                color: AppColors.red,
                onRefresh: () async {
                  // 취소 버튼(컷오프)이 이 탭에 있으므로 pull-to-refresh 때 정책도 재조회
                  // — 대표가 컷오프를 바꿔도 재로그인 없이 반영(center_policy_provider 주석).
                  // 스태프 캐시도 동반 재조회 — 실패 고착 해소 + 프로필 변경 반영.
                  //
                  // 홈도 함께 — 이 탭의 "내 코치 (…)" 칩·아바타·프로필 시트가 쓰는
                  // 담당 코치 정보는 booking이 아니라 **홈 요약**(myPasses)에서 온다.
                  // booking만 새로 고치면 홈이 캐시한 옛 요약을 그대로 다시 받아
                  // (booking build가 homeViewModelProvider.future를 watch한다) 스태프
                  // 캐시를 버려 봐야 칩 라벨은 그대로다 — 위 onRetry/EmptyPasses 경로와 같은 이유.
                  ref.invalidate(centerPolicyProvider);
                  ref.invalidate(staffMapProvider);
                  ref.invalidate(homeViewModelProvider);
                  ref.read(bookingViewModelProvider.notifier).refresh();
                },
                child: ListView(
                  // 콘텐츠가 화면보다 짧아도 pull-to-refresh 당김이 동작하게.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RiseChip(
                          // 미배정/미해석이면 빈 괄호 "내 코치 ()" 대신 "내 코치"만.
                          // (이름이 ""로 와도 같은 처리 — 예전 null 검사만으론 못 걸렀다.)
                          //
                          // 예약 탭의 **퇴사 표기 앵커** — "내 코치 (정혜린 · 퇴사)".
                          // 괄호가 이미 있어 tag()의 "(퇴사)"를 쓰면 괄호가 중첩되므로
                          // 좁은 자리용 inline() 표기를 쓴다. 슬롯 태그·내 예약 목록엔
                          // 붙이지 않는다(같은 화면 반복 방지).
                          label: coachName == null
                              ? '내 코치'
                              : '내 코치 (${CoachLabel.inline(coachName, inactive: primaryInactive)})',
                          // 코치 프로필 발견성(P05 보완) — 담당 코치가 있으면 칩에 소형
                          // 아바타. 캐시 미적중이면 이름 이니셜 폴백(TrainerAvatar).
                          leading: coachName == null
                              ? null
                              : TrainerAvatar(
                                  // 캐시의 이름이 ""면 폴백으로 넘어가야 하므로 ??가 아니라
                                  // resolve()로 판정한다(빈 이름 → 이니셜 "?" 방지).
                                  name: CoachLabel.resolve(
                                    staffMap?[data.primaryPass.trainerId]?.name,
                                    fallback: coachName,
                                  ),
                                  photoUrl:
                                      staffMap?[data.primaryPass.trainerId]?.profile.photoUrl ?? '',
                                  colorHex: staffMap?[data.primaryPass.trainerId]?.color,
                                  size: 16,
                                  inactive: primaryInactive,
                                ),
                          selected: showMyCoachOnly,
                          // 첫 탭 = 필터 전환(기존 동작 유지), 이미 선택된 상태에서 다시 탭
                          // = 담당 코치 프로필 시트(P05) — 칩 하나로 두 동작을 겹치지 않게.
                          onTap: () {
                            if (!showMyCoachOnly) {
                              ref.read(showMyCoachOnlyProvider.notifier).set(true);
                              return;
                            }
                            _openProfile(
                              context,
                              staffMap,
                              data.primaryPass.trainerId,
                              data.primaryPass.trainerName,
                              inactive: primaryInactive,
                            );
                          },
                        ),
                        RiseChip(
                          // "전체 코치"가 아니라 "내 패스들 전부로 보기"가 실의미
                          // (POST /v1/bookings는 pass_id로 코치가 정해진다).
                          label: '내 회원권 전체',
                          selected: !showMyCoachOnly,
                          onTap: () => ref.read(showMyCoachOnlyProvider.notifier).set(false),
                        ),
                        // 재탭 제스처만으로는 프로필 진입을 알 수 없어 명시적 버튼도 제공
                        // (P05 발견성). 미배정/미해석이면 생략(칩 라벨과 같은 판정).
                        // 퇴사한 코치도 링크는 남긴다 — 프로필 시트가 "퇴사" 안내를 하는
                        // 유일한 자리라 여기서 막으면 회원이 이유를 알 길이 없어진다.
                        if (coachName != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openProfile(
                              context,
                              staffMap,
                              data.primaryPass.trainerId,
                              data.primaryPass.trainerName,
                              inactive: primaryInactive,
                            ),
                            child: const Padding(
                              // 칩 줄에 나란히 선 텍스트 링크 — 히트만 44dp로.
                              padding: EdgeInsets.fromLTRB(2, 13, 8, 13),
                              child: Text(
                                '코치 소개',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    DateStrip(
                      selected: data.selectedDate,
                      onSelect: (d) => ref.read(bookingViewModelProvider.notifier).selectDate(d),
                    ),
                    const SizedBox(height: 8),
                    SlotList(
                      selectedDate: data.selectedDate,
                      slots: data.slots,
                      myPasses: data.myPasses,
                      primaryPassId: data.primaryPassId,
                      myMemberId: memberId,
                      showMyCoachOnly: showMyCoachOnly,
                      onBook: (slotKey, passId) =>
                          _openConfirm(context, data, slotKey, passId, staffMap),
                      onCoachTap: (trainerId, trainerName) => _openProfile(
                        context,
                        staffMap,
                        trainerId,
                        trainerName,
                        // 태그의 코치는 내 패스들에서 온다 — 같은 도메인 플래그로 판정
                        // (캐시가 뭐라 하든 화면 안에서 답이 갈리지 않게).
                        inactive: data.trainerInactiveOf(trainerId),
                      ),
                    ),
                    MyBookingsList(
                      bookings: data.myBookings,
                      onCancel: (booking) => _cancel(context, ref, booking),
                      policy: policy,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 자정을 넘겨 선택 날짜가 과거가 됐으면 오늘로 당긴다
  /// ([SelectedBookingDate.rolloverToToday] — 왜 앞으로만 미는지 포함).
  ///
  /// **프레임 뒤로 미루는 이유**: provider를 위젯 build 도중에 쓰면 Riverpod가
  /// "Tried to modify a provider while the widget tree was building"으로 막는다.
  /// 서버 왕복은 날짜가 실제로 어긋났을 때만 일어난다 — 미래 날짜를 보고 있으면
  /// 상태가 그대로라 뷰모델도 다시 빌드되지 않는다.
  void _rolloverSelectedDate(BuildContext context, WidgetRef ref, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (!ref.read(selectedBookingDateProvider).isBefore(today)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 그 사이 로그아웃·라우트 교체로 화면이 사라졌을 수 있다.
      if (!context.mounted) return;
      ref.read(selectedBookingDateProvider.notifier).rolloverToToday();
    });
  }

  void _openConfirm(
    BuildContext context,
    BookingScreenData data,
    String slotKey,
    String passId,
    Map<String, StaffDto>? staffMap,
  ) {
    BookablePass pass = data.primaryPass;
    for (final p in data.myPasses) {
      if (p.passId == passId) pass = p;
    }
    final cachedTrainer = staffMap?[pass.trainerId];
    showBookingConfirmSheet(
      context,
      slotKey: slotKey,
      passId: passId,
      timeLabel:
          '${DateFmt.monthDayWeekday(DateFmt.slotKeyToDateTime(slotKey))} ${DateFmt.hhmm(DateFmt.slotKeyToDateTime(slotKey))}',
      // 확정 시트는 예약 탭과 별개 표면이라 여기서도 퇴사를 말한다 — 오히려
      // "누구 수업인지" 마지막으로 확인하는 자리라 빠지면 안 된다.
      // (두 모드 모두 퇴사 코치로는 여기까지 오지 못하게 막혔지만 — 전체 보기는
      //  isSelectable 필터, 내 코치는 비활성 "예약 불가" 행 — 서버 응답과 화면
      //  사이의 레이스까지 감안해 마지막 방어선으로 표기는 남긴다.)
      trainerLabel: CoachLabel.tag(
        '${CoachLabel.resolve(pass.trainerName)} 코치',
        inactive: pass.trainerInactive,
      ),
      productLabel: pass.product,
      // 코치 소형 아바타(P05) — 캐시 미적중이면 시트가 아바타 없이 기존 그대로.
      // 캐시 DTO의 재직 상태는 화면의 진실(도메인 플래그)로 맞춰 넘긴다 — 예전엔
      // 라벨만 "(퇴사)"이고 그 옆 아바타는 총천연색이었다(_withDomainStatus 주석).
      trainer: cachedTrainer == null
          ? null
          : _withDomainStatus(cachedTrainer, pass.trainerInactive),
    );
  }

  /// 코치 프로필 시트(P05) — 스태프 캐시에서 즉시 조회. 캐시 미적중이면 이름만 채운
  /// 빈 프로필로 열되, staffMap 자체가 없을 때(로딩 전/로드 실패)는 "미등록"이 아니라
  /// "미로드"이므로 시트가 재시도 안내 문구로 구분하게 플래그를 넘긴다.
  /// (staffMap이 있는데 uid만 없는 경우는 디렉토리 기준 실제 미등재 — 기존 문구 유지.)
  ///
  /// [inactive] — 이 화면이 아는 퇴사 여부(도메인 플래그). 캐시 DTO/폴백 DTO의
  /// status를 여기에 맞춰 열어야 칩이 "(퇴사)"라고 말한 코치의 시트가 퇴사를
  /// 설명한다. 모르면 null(캐시가 말하는 대로 — [_withDomainStatus] 주석).
  void _openProfile(
    BuildContext context,
    Map<String, StaffDto>? staffMap,
    String trainerId,
    String? fallbackName, {
    required bool? inactive,
  }) {
    // 폴백 StaffDto는 status 기본값이 active — 캐시도 없고 도메인 플래그도 모르면
    // 퇴사 여부를 알 수 없고, 모르는 걸 "퇴사"로 단정하는 쪽이 훨씬 나쁘다
    // (계약 v2.0 승격 규약과 같은 방향). 시트는 profileUnavailable로
    // "불러오지 못했어요"를 안내한다.
    final cached =
        staffMap?[trainerId] ??
        StaffDto(uid: trainerId, name: CoachLabel.resolve(fallbackName, fallback: '담당 코치'));
    showTrainerProfileSheet(
      context,
      staff: _withDomainStatus(cached, inactive),
      profileUnavailable: staffMap == null,
    );
  }

  /// 캐시 [StaffDto]의 재직 상태를 화면의 진실(도메인 플래그)로 맞춘다.
  /// [inactive]가 null이면(= 도메인이 이 코치를 모르면) 캐시 값을 그대로 둔다.
  ///
  /// **왜 도메인 플래그가 진실인가** — 예전엔 같은 사실을 서로 다른 **두 출처**에서
  /// 읽었다: repository가 `StaffDirectory.fetchAll()`로 직접 뜬 값과, 15분 TTL
  /// [staffMapProvider] 캐시의 `StaffDto.status`. 둘 다 GET /v1/staff이지만 경로가
  /// 달라 한 화면 안에서 모순됐다 — 라벨은 "정혜린 코치 (퇴사)"인데 옆 아바타는
  /// 총천연색, 칩은 "(퇴사)"인데 그 칩이 여는 프로필 시트는 퇴사를 한마디도 못 하고
  /// "아직 소개가 등록되지 않았어요"로 떨어졌다.
  ///
  /// 지금은 repository도 [staffMapReaderProvider]를 거쳐 **같은 캐시**를 읽는다
  /// (출처 단일화). 그래도 이 보정을 남겨 두는 이유는 두 값을 읽는 **시점**이
  /// 다르기 때문이다: 도메인 플래그는 뷰모델이 로드한 순간의 스냅샷이고, `staffMap`은
  /// 위젯이 그리는 순간의 캐시다. 그 사이에 TTL 만료·invalidate가 끼면 한 프레임
  /// 안에서 다시 어긋날 수 있다. 그때 어느 쪽으로 통일할지가 이 함수다:
  ///  · 도메인 플래그를 택한다 — 라벨·아바타·시트가 **한 화면에서 한 답**만 말하는
  ///    쪽이, 그중 하나만 몇 초 더 신선한 것보다 낫다. 뒤이은 pull-to-refresh가
  ///    둘을 함께 새로 읽어 정렬시킨다.
  ///  · 스태프 조회가 실패하면 플래그는 false(= "모른다"의 폴백)가 된다. 그때는
  ///    이름도 함께 해석되지 않아 코치 문구 자체가 사라지므로 "현직"이라고 말하는
  ///    자리가 생기지 않고, 캐시도 없어 시트는 [profileUnavailable]로 안내한다
  ///    (판단 근거는 staff_directory의 [staffMapReaderProvider] 주석).
  /// 캐시는 사진·색·직함·소개 같은 표시용 부가 정보만 담당한다.
  StaffDto _withDomainStatus(StaffDto staff, bool? inactive) =>
      inactive == null ? staff : staff.copyWith(status: inactive ? 'inactive' : 'active');

  /// 예약 취소 — **컷오프와 무관하게 항상 실행 가능**하고, 컷오프가 지났으면 그
  /// 결과(세션 1회 차감)를 확인 문구로 정확히 말한다.
  ///
  /// 서버는 취소를 막지 않는다(`CancelBooking`: "취소 자체는 항상 허용한다 — 막으면
  /// 노쇼로 위장할 유인만 커짐"). 컷오프 경과 취소는 노쇼와 **같은 원장 처리**를
  /// 받는다: delta -1, 단 정책(grace_once)이 켜져 있고 이 패스에 noshow/noshow_waived
  /// 이력이 아직 없으면 최초 1회는 delta 0으로 유예된다.
  ///
  /// **유예가 남았는지는 단정하지 않는다** — 그 판정은 원장 이력(GET /v1/ledger)에
  /// 달려 있는데 예약 탭은 원장을 로드하지 않는다(마이 탭 몫). 그래서 "유예돼요"가
  /// 아니라 "최초 1회는 유예돼요 / 이미 받았다면 이번엔 차감돼요"로 두 경우를 다
  /// 말하고, 확인은 마이 탭 이용내역으로 안내한다. 정책이 유예를 끄면 그 문장 자체를
  /// 빼서 없는 유예를 약속하지 않는다.
  Future<void> _cancel(BuildContext context, WidgetRef ref, MyBooking booking) async {
    final policy = ref.read(centerPolicyProvider).value ?? CenterPolicy.fallback;
    final when = '${DateFmt.monthDayWeekday(booking.startAt)} ${DateFmt.hhmm(booking.startAt)}';
    final confirmed = await showDialog<bool>(
      context: context,
      // 컷오프 판정을 **다이얼로그를 여는 순간에 굳히지 않는다**. 이 화면에서 굳는
      // 판정 중 유일하게 돈이 걸린 자리다: 열어 둔 채 컷오프를 넘기면 회원은
      // "그냥 취소할까요?"만 읽고 확인하는데, 서버는 그 시각 기준으로 세션 1회를
      // 차감한다. 경계는 컷오프 시각 하나뿐이라 그때 한 번만 다시 그리면 된다
      // (TimeBoundaryBuilder — 서버 왕복 0).
      builder: (dialogContext) => TimeBoundaryBuilder(
        boundaries: [booking.startAt.subtract(Duration(hours: policy.cancelCutoffHours))],
        builder: (context, now) {
          // 예약 시각은 센터(KST) 벽시계 표현 — "지금"도 같은 표현으로 읽는다
          // (DateFmt 규약). `now`는 이 프레임의 DateFmt.nowKst()다.
          final free = BookingRules.isFreeCancel(
            startAt: booking.startAt,
            now: now,
            cutoffHours: policy.cancelCutoffHours,
          );
          return AlertDialog(
            title: const Text('예약 취소'),
            content: Text(
              free
                  ? '$when 예약을 취소할까요?'
                  : '$when 예약을 취소할까요?\n\n'
                      '취소 마감(${policy.cancelCutoffHours}시간 전)이 지나 지금 취소하면 '
                      '노쇼와 같이 세션 1회가 차감돼요.'
                      '${policy.graceOnce ? ' 최초 1회는 유예되지만, 이미 유예를 받았다면 이번엔 차감돼요.' : ''}'
                      '\n차감 여부는 마이 탭 이용내역에서 확인할 수 있어요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('아니요'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('취소하기'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(bookingViewModelProvider.notifier).cancel(booking.id);
    if (!context.mounted) return;
    final (message, kind) = switch (result) {
      Ok() => ('예약을 취소했어요', RiseSnackKind.ok),
      Err(:final failure) => (failure.message, RiseSnackKind.danger),
    };
    ScaffoldMessenger.of(context).showSnackBar(riseSnackBar(message, kind: kind));
  }
}
