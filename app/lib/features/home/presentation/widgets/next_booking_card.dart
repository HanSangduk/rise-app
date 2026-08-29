import 'package:flutter/material.dart';
import 'package:rise_member/core/config/app_config.dart';
import 'package:rise_member/core/router/tab_navigation.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/time_boundary_builder.dart';
import 'package:rise_member/features/home/domain/home_models.dart';

const _kindLabels = {'pt': '1:1 PT', 'group': '그룹', 'ot': 'OT'};

/// 목업 "다음 예약" 카드 — 오늘 배지, 셀프 체크인, 취소 비용 안내.
/// 무료 취소 마감 문구는 센터 정책 실값([cutoffHours], v1.4)으로 표기.
///
/// ## 이 카드는 시간이 흐르면 스스로 다시 그린다 (P51)
///
/// 체크인 창(시작 ±30분)·무료 취소 컷오프·'오늘' 배지는 전부 **지금 몇 시인가**에
/// 달려 있다. 예전엔 repository가 홈을 로드하는 순간 계산해 bool로 담아 보냈고,
/// 그래서 판정이 그 시점에 굳었다 — 18:26에 홈을 연 회원은 창이 열리는 18:30이
/// 지나 18:35가 돼도 회색 버튼과 "수업 시작 전후 30분에 열려요"를 봤다. 당겨서
/// 새로고침해야 한다는 걸 알 방법이 없으니 데스크로 갔다(셀프 체크인이 없애려던
/// 바로 그 왕복).
///
/// 지금은 [TimeBoundaryBuilder]가 경계 시각마다 이 카드만 다시 그린다:
///  · 경계는 예약에서 계산된다 — 창 열림/닫힘, 컷오프, 자정 둘.
///  · 재평가는 **로컬 계산이고 서버를 다시 부르지 않는다.** 홈 재조회는 5~6 왕복인데
///    바뀐 건 시계뿐이다. 그 사이 예약이 데스크에서 취소됐을 가능성은 남지만,
///    그 경우 체크인 POST를 서버가 400("시간창 안의 예약을 찾을 수 없음",
///    `findUpcomingBooking`)으로 정확히 거절하고 문구가 그대로 노출된다 — 회원이
///    실제로 누를 때 한 번만 왕복하는 쪽이, 예약 있는 모든 회원이 창이 열릴 때마다
///    홈을 통째로 다시 받는 쪽보다 싸고 결과도 같다. 앱 안에서 한 취소는 예약
///    탭이 이미 `homeViewModelProvider`를 invalidate한다(booking_view_model).
///  · 탭을 떠나면(TickerMode off) 타이머를 놓고, 돌아오거나 앱이 resumed되면
///    즉시 재평가한다(자세한 근거는 [TimeBoundaryBuilder] 주석).
class NextBookingCard extends StatelessWidget {
  const NextBookingCard({
    super.key,
    required this.booking,
    required this.onCheckIn,
    required this.cutoffHours,
    this.cutoffUnknown = false,
    this.checkedInBookingId,
  });

  final NextBooking? booking;
  final VoidCallback onCheckIn;

  /// 무료 취소 컷오프(policy.cancel_cutoff_hours) — 문구 표기와 판정
  /// ([NextBooking.isFreeCancelAt]) **양쪽**에 같은 값을 쓴다. 둘이 갈리면
  /// "24시간 전까지 무료"라 적어 두고 다른 기준으로 무료/차감을 가르게 된다.
  final int cutoffHours;

  /// [cutoffHours]가 **서버 값이 아니라 폴백**인가(`/v1/center` 조회 실패).
  ///
  /// 참이면 이 카드는 **시간을 말하지 않는다.** 폴백 24시간을 사실처럼 찍으면,
  /// 센터 실제 기준이 48시간일 때 그 문구를 믿고 30시간 전에 취소한 회원이
  /// 차감된다 — 앱이 한 약속 때문에 회원이 손해를 본다.
  final bool cutoffUnknown;

  /// 이번 세션에서 셀프 체크인에 성공한 예약 id — 일치하면 버튼을 "체크인 완료"로 잠근다.
  final String? checkedInBookingId;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    if (b == null) {
      return RiseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RiseCardHeader(title: '다음 예약'),
            // 이 카드는 "가장 빠른 예약"이 아니라 **선택된 회원권의 담당 코치** 예약만
            // 본다(home_repository_impl이 selected.trainerId로 거른다). 회원권이 둘
            // 이상이면 다른 코치 수업이 더 빨라도 여기엔 안 뜨므로, 빈 상태에서 그
            // 범위를 밝힌다 — "없어요"만 말하면 정말 아무 예약도 없다고 읽힌다.
            const Text(
              '이 회원권 담당 코치로 예정된 예약이 없어요',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 10),
            // **가라고 말했으면 데려다줘야 한다.** 종전 문구는 "예약 탭에서 잡아보세요"로
            // 끝나고 버튼이 없었다 — 홈에서 회원이 가장 자주 만나는 상태(예약 0건)가
            // 곧 막다른 길이었다. 경쟁 제품 조사에서도 홈에 예약 진입점을 둔 곳이
            // 없었다(Trainerize는 로깅과 섞인 "+" FAB, Everfit은 두 단계 아래) —
            // 있으면 그게 이 화면의 차이다.
            RiseButton(
              label: '예약하러 가기',
              expand: true,
              onPressed: () => goToTab(context, AppTab.booking),
            ),
          ],
        ),
      );
    }

    final checkedIn = b.id == checkedInBookingId;

    return TimeBoundaryBuilder(
      // 이 카드의 판정이 뒤집히는 시각 전부. 지금보다 뒤인 것 중 가장 이른 하나에만
      // 타이머가 걸리고, 그걸 지나면 다음 것으로 넘어간다.
      boundaries: [
        b.checkInOpensAt, // 회색 → 진한 빨강 + 안내 문구 사라짐
        b.checkInClosesAt, // 다시 회색 (서버도 이때부터 400)
        b.freeCancelUntil(cutoffHours), // "무료" → "1회 차감돼요"
      ],
      atMidnight: true, // '오늘' 배지 on/off

      builder: (context, now) => _card(context, b, now, checkedIn: checkedIn),
    );
  }

  Widget _card(BuildContext context, NextBooking b, DateTime now, {required bool checkedIn}) {
    // 세 판정 모두 이 프레임의 `now`에서 파생된다 — 스냅샷 필드가 아니다
    // ([NextBooking] 클래스 주석의 P51).
    final canCheckIn = b.canCheckInAt(now);
    final freeCancel = b.isFreeCancelAt(now, cutoffHours: cutoffHours);

    return RiseCard(
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiseCardHeader(
            title: '다음 예약',
            trailing: b.isTodayAt(now) ? const RiseBadge('오늘', variant: RiseBadgeVariant.red) : null,
          ),
          Text(
            // **오늘이 아니면 날짜를 반드시 붙인다.** 종전엔 시각만 찍어서
            // "09:00 · 1:1 PT"가 전부였다 — '오늘' 배지가 없는 순간 회원은 그게
            // 내일인지 다음 주인지 홈에서 알 방법이 없었다. 그러면서 바로 아래
            // 줄은 헤더가 이미 말한 센터명을 반복하고 있었다.
            b.isTodayAt(now)
                ? '${DateFmt.hhmm(b.startAt)} · ${_kindLabels[b.kind] ?? b.kind}'
                : '${DateFmt.monthDayWeekday(b.startAt)} ${DateFmt.hhmm(b.startAt)} · ${_kindLabels[b.kind] ?? b.kind}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            // 퇴사 표기는 붙이지 않는다: 다음 예약은 홈에서 선택된 패스와 같은
            // 코치로만 추려지므로(home_repository_impl의 trainerId 필터) 헤더의
            // "담당 X 코치 (퇴사)"가 이미 같은 사람을 가리킨다 — 여기 또 붙이면
            // 한 화면에서 같은 사실을 세 번 읽게 된다.
            // resolve()는 이름이 ""로 와도 " 코치"(앞이 빈 자리)가 되지 않게 한다.
            '${CoachLabel.resolve(b.trainerName)} 코치 · ${AppConfig.centerFullName}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RiseButton(
                label: checkedIn ? '체크인 완료' : '셀프 체크인 (데스크 QR 스캔)',
                small: true,
                onPressed: (!checkedIn && canCheckIn) ? onCheckIn : null,
              ),
              // 컷오프가 지나도 취소는 열려 있다 — 예전엔 여기에 자물쇠 + "취소 마감
              // (N시간 전)"을 띄웠는데, 서버는 취소를 막은 적이 없다(컷오프 경과는
              // 원장 차감일 뿐). 회원이 "이제 못 무른다"고 읽으면 남는 선택지는
              // 노쇼뿐이고 차감은 똑같은데 코치는 통보를 못 받는다. 그래서 마감이
              // 아니라 **대가**를 말하고, 액션은 그대로 예약 탭으로 보낸다.
              Text(
                // **모르면 숫자를 말하지 않는다.** 차감 문구 쪽은 폴백이어도 그대로
                // 두는데, 그건 시각 판정이 아니라 "지금 취소하면"이라는 사실이고
                // 서버가 최종 판정을 하기 때문이다.
                freeCancel
                    ? (cutoffUnknown
                        ? '취소 규정은 예약 탭에서 확인해주세요'
                        : '$cutoffHours시간 전까지 취소 가능(예약 탭)')
                    : '지금 취소하면 세션 1회가 차감돼요(예약 탭)',
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          ),
          if (!checkedIn && !canCheckIn)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '셀프 체크인은 수업 시작 전후 30분에 열려요',
                style: TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

