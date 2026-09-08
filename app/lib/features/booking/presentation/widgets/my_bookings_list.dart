import 'package:flutter/material.dart';
import 'package:rise_member/core/icons/rise_icon.dart';
import 'package:rise_member/core/icons/rise_icons.dart';
import 'package:rise_member/core/policy/center_policy.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_typography.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';

const _kindLabels = {'pt': '1:1', 'group': '그룹', 'ot': 'OT'};
const _statusLabels = {'completed': '완료', 'noshow': '노쇼', 'cancelled': '취소됨'};

/// 목업 "내 예약" 카드 — 고정 배지 + 확정 예약은 항상 취소할 수 있다(서버가 컷오프로
/// 취소를 막지 않는다 — [_BookingRow._trailing] 주석). 컷오프·용량 안내는 센터 정책
/// 실값([policy], GET /v1/center v1.4)으로 표기.
/// 취소 요청 중엔 해당 행 버튼을 비활성("취소 중…")해 이중 요청을 막는다(로컬 상태).
class MyBookingsList extends StatefulWidget {
  const MyBookingsList({
    super.key,
    required this.bookings,
    required this.onCancel,
    required this.policy,
  });

  final List<MyBooking> bookings;

  /// 취소 플로우(확인 다이얼로그 → DELETE) 전체를 감싸는 Future — 완료까지 행 비활성.
  final Future<void> Function(MyBooking) onCancel;
  final CenterPolicy policy;

  @override
  State<MyBookingsList> createState() => _MyBookingsListState();
}

class _MyBookingsListState extends State<MyBookingsList> {
  /// 취소 요청이 진행 중인 예약 id — 완료(성공/실패/다이얼로그 취소) 후 해제.
  String? _cancellingId;

  Future<void> _handleCancel(MyBooking booking) async {
    if (_cancellingId != null) return; // 다른 행 취소 진행 중엔 중복 시작 방지.
    setState(() => _cancellingId = booking.id);
    try {
      await widget.onCancel(booking);
    } finally {
      if (mounted) setState(() => _cancellingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 예약 시각은 센터(KST) 벽시계 표현 — "지금"도 같은 표현으로 읽어야 다가오는
    // 예약 필터와 취소 컷오프가 기기 타임존과 무관하게 같은 답을 낸다(DateFmt 주석).
    final now = DateFmt.nowKst();
    final upcoming = widget.bookings
        .where((b) => b.startAt.isAfter(now.subtract(const Duration(hours: 3))))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseCardHeader(title: '내 예약'),
          if (upcoming.isEmpty)
            const Text('예약된 일정이 없어요', style: TextStyle(fontSize: 11.5, color: AppColors.muted))
          else
            for (final b in upcoming)
              _BookingRow(
                booking: b,
                cancelling: _cancellingId == b.id,
                onCancel: _handleCancel,
              ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              // 컷오프 이후 취소도 **가능하다** — 무료가 아닐 뿐이다. 예전 문구는
              // "N시간 전까지 무료"에서 끊겨, 버튼이 사라진 이유가 "마감"인지
              // "차감"인지 말하지 않았다(그리고 서버는 마감한 적이 없다).
              //
              // **정책을 못 받았으면 숫자를 말하지 않는다**(P56 H1). 폴백 24시간·3팀은
              // 이 센터의 기준이 아니라 앱의 기본값이다 — 사실처럼 찍으면 센터 실제
              // 마감이 48시간일 때 그 문구를 믿고 30시간 전에 취소한 회원이 차감된다.
              // "차감된다"는 사실은 폴백이어도 그대로 말한다(시각 판정이 아니라 대가다).
              widget.policy.isFallback
                  ? '고정 = 매주 반복 예약(자동 확정). 센터의 취소 정책을 불러오지 못해 무료 취소 마감을 '
                      '확인할 수 없어요 — 마감이 지난 뒤 취소하면 세션 1회가 차감돼요.'
                  : '고정 = 매주 반복 예약(자동 확정). 시간당 최대 ${widget.policy.slotCapacity}팀 · '
                      '취소는 ${widget.policy.cancelCutoffHours}시간 전까지 무료 · 이후엔 세션 1회가 차감돼요.',
              style: AppTypography.note,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({
    required this.booking,
    required this.cancelling,
    required this.onCancel,
  });

  final MyBooking booking;

  /// 이 행의 취소 요청이 진행 중 — 버튼 비활성 + "취소 중…" 라벨.
  final bool cancelling;
  final ValueChanged<MyBooking> onCancel;

  @override
  Widget build(BuildContext context) {
    return RiseRow(
      child: Row(
        children: [
          Flexible(
            child: Text(
              // 이름을 해석하지 못하면 " · " 꼬리째 생략 — 예전엔 `?? ''`라
              // "1:1 · "처럼 구분자만 남았다. 조립도 joinDot에 맡긴다: 판정만
              // 유틸에 맡기고 원본을 다시 보간하면 " 정혜린 "의 공백이 되살아난다.
              // 퇴사 표기는 붙이지 않는다: 이미 잡힌 예약 목록이라 코치 고용
              // 상태보다 "언제/무엇"이 정보의 중심이고, 화면 앵커(상단 "내 코치"
              // 칩)가 이미 말했다. 이름 해석 자체는 계약대로 계속 유지된다.
              CoachLabel.joinDot([
                '${DateFmt.monthDayWeekday(booking.startAt)} ${DateFmt.hhmm(booking.startAt)}',
                _kindLabels[booking.kind] ?? booking.kind,
                booking.trainerName,
              ]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (booking.isRecurring) ...[
            const SizedBox(width: 5),
            const RiseIcon(RiseIcons.refresh, size: 11, color: AppColors.brand),
            const SizedBox(width: 2),
            const Text('고정', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brand)),
          ],
        ],
      ),
      trailing: _trailing(),
    );
  }

  /// 확정 예약은 **컷오프와 무관하게 항상 취소 버튼**을 준다.
  ///
  /// 예전엔 컷오프가 지나면 탭 타깃 없는 "확정" 배지만 남겨 취소를 막았다. 그런데
  /// 서버는 취소를 한 번도 막은 적이 없다(`CancelBooking`: "취소 자체는 항상
  /// 허용한다 — 막으면 노쇼로 위장할 유인만 커짐"). 컷오프 경과는 거부가 아니라
  /// 원장 차감(정책상 최초 1회 유예)일 뿐이다. 앱이 그 문을 닫으면 회원에게 남는
  /// 선택지는 노쇼뿐이고, 차감은 똑같은데 코치는 통보조차 못 받는다.
  ///
  /// 대신 결과를 정확히 알리고 확인을 받는다 — 컷오프 판정
  /// ([BookingRules.isFreeCancel])은 확인 다이얼로그 문구를 가르는 데 쓰인다
  /// (booking_screen의 `_cancel`).
  Widget _trailing() {
    if (booking.isWaitlist) return const RiseBadge('대기', variant: RiseBadgeVariant.warn);
    if (!booking.isConfirmed) {
      return RiseBadge(_statusLabels[booking.status] ?? booking.status, variant: RiseBadgeVariant.muted);
    }
    return RiseButton(
      label: cancelling ? '취소 중…' : '취소',
      style: RiseButtonStyleKind.outline,
      small: true,
      onPressed: cancelling ? null : () => onCancel(booking),
    );
  }
}
