import 'package:flutter/material.dart';
import 'package:rise_member/core/theme/app_colors.dart';
import 'package:rise_member/core/theme/app_radius.dart';
import 'package:rise_member/core/utils/coach_label.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_badge.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/core/widgets/rise_card.dart';
import 'package:rise_member/core/widgets/time_boundary_builder.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/domain/booking_rules.dart';

typedef OnBookSlot = void Function(String slotKey, String passId);

/// 전체 보기 코치 태그 탭 → 프로필 시트(P05). 이름은 staff 캐시 미적중 시 폴백 표기용.
typedef OnCoachTap = void Function(String trainerId, String? trainerName);

/// 슬롯 리스트 — "내 코치" 모드는 패스 1개 기준 [BookingRules] 상태를 그대로,
/// "전체 코치" 모드는 내가 가진 모든 패스 각각에 대해 평가해 요약한다
/// (POST /v1/bookings는 트레이너가 아니라 pass_id로 코치가 정해지므로
/// "전체 코치 보기" = "어떤 내 패스로 예약할지 보기"와 같다).
class SlotList extends StatelessWidget {
  const SlotList({
    super.key,
    required this.selectedDate,
    required this.slots,
    required this.myPasses,
    required this.primaryPassId,
    required this.myMemberId,
    required this.showMyCoachOnly,
    required this.onBook,
    required this.onCoachTap,
  });

  /// 목록이 보여주는 날짜 — 휴무일 안내처럼 **슬롯이 없는 날에도** 말해야 하는
  /// 판정에 필요하다([slots]가 비면 날짜를 유추할 수 없다).
  final DateTime selectedDate;
  final List<Slot> slots;
  final List<BookablePass> myPasses;
  final String primaryPassId;
  final String myMemberId;
  final bool showMyCoachOnly;
  final OnBookSlot onBook;
  final OnCoachTap onCoachTap;

  BookablePass get _primaryPass =>
      myPasses.firstWhere((p) => p.passId == primaryPassId, orElse: () => myPasses.first);

  /// 퇴사한 담당 코치 때문에 이 목록으로 새 예약을 잡을 수 없으면 그 코치 이름,
  /// 아니면 null. 이름을 해석 못 했으면 "담당"(→ "담당 코치가 …").
  ///
  /// 두 모드가 같은 막다른 길에 서로 다른 이유로 도달한다:
  ///  · "내 코치" — 담당 패스 하나로 고정이라 [BookablePass.isSelectable] 필터가
  ///    아예 없다. 그래서 퇴사 코치의 슬롯이 살아 있는 "예약" 버튼째 그려졌고,
  ///    서버가 400으로 거부할 예약을 권했다(회원이 처음 보는 화면이 이쪽이다).
  ///  · "내 회원권 전체" — 필터가 선택지를 비워 주지만, 이유를 말하지 않으면
  ///    잔여 숫자만 적힌 회색 목록이 된다.
  /// 어느 쪽이든 행을 숨기지는 않는다 — 숨기면 회원은 빈 화면만 보고 왜 예약이
  /// 안 되는지, 다음에 뭘 해야 하는지 알 길이 없다.
  /// 다른 회원권으로는 아직 예약할 수 있는가 — 안내 문구의 다음 행동이 갈린다
  /// ("센터에 문의" vs "내 회원권 전체에서 다른 회원권으로"). 없는 선택지를
  /// 권하지도, 있는 선택지를 감추지도 않기 위해 실제 패스 목록으로 판정한다.
  ///
  /// [BookablePass.canBookNew]로 본다(isSelectable이 아니라) — 잔여만큼 이미 다
  /// 잡아 둔 패스는 목록엔 남지만 서버가 새 예약을 거부한다. 그걸 "다른 회원권"
  /// 이라고 권하면 회원은 안내대로 칩을 바꾸고 또 거부당한다.
  bool get _hasOtherBookablePass =>
      myPasses.any((p) => p.canBookNew && p.passId != _primaryPass.passId);

  String? get _blockingRetiredCoach {
    if (showMyCoachOnly) {
      final pass = _primaryPass;
      return pass.trainerInactive ? CoachLabel.resolve(pass.trainerName) : null;
    }
    // 새 예약을 만들 수 있는 패스가 하나라도 있으면 막힌 상태가 아니다.
    if (myPasses.any((p) => p.canBookNew)) return null;
    final names = {
      for (final p in myPasses)
        if (p.trainerInactive) CoachLabel.resolve(p.trainerName),
    };
    if (names.isEmpty) return null; // 만료/환불 등 퇴사와 무관한 이유로 빈 목록.
    // 퇴사한 코치가 여럿이면 한 명만 지목하지 않고 "담당 코치가 …"로 뭉친다.
    return names.length == 1 ? names.first : '담당';
  }

  /// 잔여 세션 소진으로 새 예약이 막혔는가 — [_blockingRetiredCoach]와 같은 모양의
  /// 판정이다. 퇴사와 달리 이건 **모든 회원이 언젠가 도달하는 종착 상태**다:
  /// 백엔드엔 패스를 expired로 넘기는 코드가 없어서, 20회를 다 써도 유효기간이
  /// 남는 한 status는 계속 active로 온다.
  bool get _blockedByNoRemaining {
    if (showMyCoachOnly) {
      final pass = _primaryPass;
      return pass.isUsable && !pass.hasRemaining;
    }
    if (myPasses.any((p) => p.canBookNew)) return false;
    return myPasses.any((p) => p.isUsable && !p.hasRemaining);
  }

  /// 잔여는 남았는데 **이미 잡아 둔 예약이 그 잔여를 전부 물고 있어** 막혔는가
  /// (서버 400 "이미 잡힌 예약 N건이 잔여 M회를 채웠어요", P13 H1).
  ///
  /// [_blockedByNoRemaining]과 배타적이다 — 잔여가 0이면 그쪽이 먼저 참이 된다.
  /// 둘을 뭉치지 않는 이유는 다음 행동이 정반대이기 때문이다: 잔여 0은 재등록,
  /// 이쪽은 **기존 예약 취소**. 이미 회차를 가진 회원에게 "재등록해주세요"라고
  /// 하면 돈을 더 내라는 안내가 된다.
  /// 여러 개면 숫자를 말하지 않는다 — 패스마다 잔여·예약 수가 다른데 하나를 골라
  /// 말하면 나머지에 대해 거짓이 되고, 합치면 어느 쪽 숫자도 아닌 값이 된다.
  List<BookablePass> get _allBookedPasses {
    bool blocked(BookablePass p) => p.isUsable && p.hasRemaining && !p.hasBookingBudget;
    if (showMyCoachOnly) {
      return blocked(_primaryPass) ? [_primaryPass] : const [];
    }
    if (myPasses.any((p) => p.canBookNew)) return const [];
    return myPasses.where(blocked).toList();
  }

  /// 담당 코치가 **이 날짜에** 휴무라 하루가 통째로 막혔으면 그 코치 이름.
  ///
  /// "내 코치" 모드에서만 안내한다 — 휴무는 코치별 사정이라 여러 패스를 함께 보는
  /// "내 회원권 전체"에선 한 문장으로 뭉칠 수 없고, 그쪽은 코치 태그가 패스마다
  /// "○○ 휴무"로 말한다. 다른 제약과 달리 **날짜만 바꾸면 풀리므로** 다음 행동도
  /// 그쪽을 가리킨다.
  ///
  /// 판정은 행과 **같은 규칙 엔진**에 묻는다(빈 슬롯 하나를 가정해 evaluate). 조건을
  /// 여기서 다시 손으로 쓰면, 유효기간·홀딩이 함께 걸린 날에 행은 "8/10까지"라 하고
  /// 상단은 "휴무"라 하는 식으로 한 화면이 두 이유를 말하게 된다.
  String? get _offdayCoach {
    if (!showMyCoachOnly) return null;
    final probe = BookingRules.evaluate(
      slot: Slot(slotKey: DateFmt.toSlotKey(selectedDate, BookingRules.openHour)),
      pass: _primaryPass,
      // 하루 단위 안내라 "내 예약" 여부는 의미가 없다(그 슬롯만의 사정).
      myMemberId: '',
    );
    return probe is TrainerOffday ? CoachLabel.resolve(_primaryPass.trainerName) : null;
  }

  /// 목록 맨 위 안내는 **한 번에 하나만**. 우선순위는 "풀기 어려운 것"부터다 —
  /// 퇴사(센터 문의) → 잔여 0(재등록) → 예약 다 잡음(기존 예약 취소) →
  /// 휴무(날짜 변경). 여러 개를 겹쳐 띄우면 정작 다음에 뭘 해야 하는지가 흐려진다.
  ///
  /// "예약 다 잡음"이 잔여 0보다 뒤인 이유: 회원 스스로 이 탭 아래 "내 예약"에서
  /// 바로 풀 수 있는 상태라 재등록(센터 문의)보다 가볍다. 둘은 애초에 배타적이라
  /// (잔여 0이면 예산도 0) 순서가 실제로 갈리는 건 여러 패스가 서로 다른 이유로
  /// 막힌 "내 회원권 전체" 뷰뿐이다.
  Widget? get _blockNotice {
    if (_blockingRetiredCoach case final coach?) {
      return _RetiredCoachNotice(coach, hasOtherPass: _hasOtherBookablePass);
    }
    if (_blockedByNoRemaining) {
      return _NoRemainingNotice(hasOtherPass: _hasOtherBookablePass);
    }
    if (_allBookedPasses case final blocked when blocked.isNotEmpty) {
      return _AllBookedNotice(
        pass: blocked.length == 1 ? blocked.first : null,
        hasOtherPass: _hasOtherBookablePass,
      );
    }
    if (_offdayCoach case final coach?) return _OffdayNotice(coach);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // "지남" 판정은 **시간이 흐르면 스스로 바뀌어야 한다**(P51의 같은 클래스).
    // 이 목록은 StatelessWidget이고 예약 탭은 indexedStack에 상주하므로
    // (core/router/app_router.dart), 13:55에 열어 둔 화면은 아무도 리빌드해 주지
    // 않으면 14:05에도 14:00 슬롯에 살아 있는 "예약" 버튼을 보여준다.
    // **여기선 서버가 받아 준다** — `CreateBooking`에도 `BookingRules.evaluate`에도
    // "지금"을 보는 분기가 없어서(이 파일 아래 "서버도 별도 거부 예정" 주석), 그
    // 클릭은 실제로 confirmed 예약이 되고 회원은 참석할 수 없는 수업 하나를
    // 노쇼로 날린다(세션 1회 차감 + 그만큼 예약 예산까지 잠식).
    //
    // 경계는 슬롯 시작 시각들 자체다 — 각 슬롯이 시작하는 순간 그 행만 "지남"으로
    // 넘어가면 된다. 서버 왕복 0.
    return TimeBoundaryBuilder(
      boundaries: [for (final s in slots) s.startAt],
      builder: _build,
    );
  }

  Widget _build(BuildContext context, DateTime now) {
    final notice = _blockNotice;
    // 슬롯 시각은 센터(KST) 벽시계 표현이라 "지금"도 같은 표현으로 읽는다 —
    // DateTime.now()로 비교하면 해외 체류·기기 시계 오설정에서 "지남" 판정이
    // 오프셋 차만큼 조용히 틀린다(DateFmt 클래스 주석의 시간축 규약).
    // `now`는 TimeBoundaryBuilder가 넘겨주는 이 프레임의 DateFmt.nowKst()다.
    return Column(
      children: [
        // 이유는 목록 맨 위에서 **한 번만** 말한다 — 행마다 반복하면 하루 13칸이
        // 같은 문장으로 도배된다(퇴사 표기 노이즈 규약, CoachLabel 주석).
        // 슬롯이 없는 날짜에도 남긴다 — 날짜를 옮겨도 안 된다는 걸 알려야 한다.
        if (notice != null) notice,
        if (slots.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              // 카드 안 빈 상태 한 줄은 앱 전체가 11.5 — 여기만 12였다(J2).
              child: Text('이 날짜엔 열린 슬롯이 없어요', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
          )
        else
          for (final slot in slots)
            // 지난 시간 슬롯은 모드/상태와 무관하게 예약 불가 — 비활성 "지남" 칩만.
            // (서버도 별도 거부 예정 — 클라이언트는 UX 차단.)
            if (slot.startAt.isBefore(now))
              _SlotRow(
                time: DateFmt.hhmm(slot.startAt),
                trailing: const RiseBadge('지남', variant: RiseBadgeVariant.muted),
                dim: true,
              )
            else if (showMyCoachOnly)
              _MyCoachSlotRow(slot: slot, pass: _primaryPass, myMemberId: myMemberId, onBook: onBook)
            else
              _AllCoachSlotRow(
                slot: slot,
                // 새 예약의 코치 선택지 — 퇴사한 코치의 패스는 뺀다(계약 v2.0).
                // 서버가 거부할 수업을 권하지 않기 위함이고, **이미 잡힌 예약**은
                // 이 목록과 무관하므로(MyBookingsList가 따로 렌더) 이름 해석은
                // 그대로 유지된다. 선택지가 0개가 되면 아래 passes.isEmpty 분기가
                // "잔여 n/m팀"만 있는 비활성 행으로 떨어지고, 그 이유는 목록 상단
                // 안내가 말한다(_blockingRetiredCoach).
                passes: myPasses.where((p) => p.isSelectable).toList(),
                myMemberId: myMemberId,
                onBook: onBook,
                onCoachTap: onCoachTap,
              ),
      ],
    );
  }
}

class _MyCoachSlotRow extends StatelessWidget {
  const _MyCoachSlotRow({
    required this.slot,
    required this.pass,
    required this.myMemberId,
    required this.onBook,
  });

  final Slot slot;
  final BookablePass pass;
  final String myMemberId;
  final OnBookSlot onBook;

  @override
  Widget build(BuildContext context) {
    final state = BookingRules.evaluate(slot: slot, pass: pass, myMemberId: myMemberId);
    final time = DateFmt.hhmm(slot.startAt);

    // 담당 코치가 퇴사했으면 이 패스로는 서버가 예약을 거부한다(계약 v2.0,
    // BookablePass.isSelectable). "내 코치" 모드엔 그 필터가 없어 예전엔 Bookable
    // 상태가 살아 있는 "예약" 버튼으로 그려졌다 — 행은 그대로 두되 버튼을 비활성화한다.
    // 라벨이 곧 상태인 비활성 버튼 형식은 NotYetValid·PassExpiredForSlot와 같고,
    // "왜"는 목록 상단 안내(_RetiredCoachNotice)가 한 번만 말한다.
    //
    // 살아 있는 버튼이 있던 건 Bookable뿐이지만 다른 상태도 함께 덮는다: 코치가
    // 없는데 "코치 수업중"·"3/3 만석"처럼 시간대 사정을 말하면 "다른 시간엔 될지도"
    // 라는 헛된 기대를 남긴다. 이 패스로는 어느 칸도 안 되고 이유는 하나다.
    // 이미 잡힌 예약(AlreadyBookedByMe)은 건드리지 않는다 — 계약대로 그대로 유효하다.
    if (pass.trainerInactive && state is! AlreadyBookedByMe) {
      return _SlotRow(
        time: time,
        subtitle: '잔여 ${slot.remaining}/${slot.capacity}팀',
        trailing: const RiseButton(
          label: '예약 불가',
          style: RiseButtonStyleKind.outline,
          small: true,
          onPressed: null,
        ),
        dim: true,
      );
    }

    return switch (state) {
      AlreadyBookedByMe() => _SlotRow(
          time: time,
          subtitle: '내 예약',
          trailing: const RiseBadge('확정', variant: RiseBadgeVariant.ok),
        ),
      Bookable(:final remaining, :final capacity) => _SlotRow(
          time: time,
          subtitle: '잔여 $remaining/$capacity팀',
          trailing: RiseButton(label: '예약', small: true, onPressed: () => onBook(slot.slotKey, pass.passId)),
        ),
      CoachBusy() => _SlotRow(
          time: time,
          subtitle: '잔여 ${slot.remaining}/${slot.capacity}팀',
          // 퇴사 표기는 붙이지 않는다 — 이 화면의 앵커는 상단 "내 코치 (…)" 칩이고,
          // 슬롯마다 반복하면 목록 전체가 "(퇴사)"로 도배된다.
          note: '${CoachLabel.resolve(pass.trainerName)} 코치가 이 시간 수업 중이에요',
          trailing: const RiseBadge('코치 수업중', variant: RiseBadgeVariant.muted),
          dim: true,
        ),
      // v1 제품 결정: 대기(waitlist) 신청 제거 — 백엔드에 생성 경로가 없고(만석=409),
      // 알림 없는 자동 승격은 노쇼 함정. 만석은 비활성 칩으로만 표시.
      SlotFull() => _SlotRow(
          time: time,
          trailing: RiseBadge('${slot.capacity}/${slot.capacity} 만석', variant: RiseBadgeVariant.danger),
          dim: true,
        ),
      NotYetValid(:final validFrom) => _SlotRow(
          time: time,
          trailing: RiseButton(
            label: '${validFrom.month}/${validFrom.day}부터',
            style: RiseButtonStyleKind.outline,
            small: true,
            onPressed: null,
          ),
          dim: true,
        ),
      PassExpiredForSlot(:final validUntil) => _SlotRow(
          time: time,
          trailing: RiseButton(
            label: '${validUntil.month}/${validUntil.day}까지',
            style: RiseButtonStyleKind.outline,
            small: true,
            onPressed: null,
          ),
          dim: true,
        ),
      // 홀드 구간에 걸친 슬롯 — 서버가 거부할 예약을 사전 차단(비활성 칩).
      PassOnHoldForSlot() => _SlotRow(
          time: time,
          trailing: const RiseBadge('일시정지 중', variant: RiseBadgeVariant.warn),
          dim: true,
        ),
      // 환불·만료 등으로 서버가 받지 않는 패스 — 라벨이 곧 상태인 비활성 버튼.
      PassNotUsable(:final status) => _SlotRow(
          time: time,
          trailing: RiseButton(
            label: _passStatusLabel(status),
            style: RiseButtonStyleKind.outline,
            small: true,
            onPressed: null,
          ),
          dim: true,
        ),
      // 잔여 0 — 서버가 100% 거부한다. 잔여 팀 수(3/3팀)와 헷갈리지 않게
      // "세션"이라고 못박고, 다음 행동은 상단 안내가 한 번만 말한다.
      NoRemainingSessions() => _SlotRow(
          time: time,
          subtitle: '잔여 세션 0회',
          trailing: const RiseButton(
            label: '예약 불가',
            style: RiseButtonStyleKind.outline,
            small: true,
            onPressed: null,
          ),
          dim: true,
        ),
      // 잔여는 남았는데 이미 잡아 둔 예약이 그만큼을 물고 있다 — 서버도 400이다.
      // 잔여 숫자가 멀쩡히 보이는 상태라 "왜 안 되지"가 되기 쉬워, 행에서 두 숫자를
      // 나란히 보여 준다("잔여 2회 · 예약 2건"). 다음 행동(기존 예약 취소)은
      // 상단 안내가 한 번만 말한다.
      AllRemainingBooked(:final remaining, :final openBookings) => _SlotRow(
          time: time,
          subtitle: '잔여 $remaining회 · 예약 $openBookings건',
          trailing: const RiseButton(
            label: '예약 불가',
            style: RiseButtonStyleKind.outline,
            small: true,
            onPressed: null,
          ),
          dim: true,
        ),
      // 담당 코치 휴무일 — 슬롯이 비어 있어도 서버가 거부한다(v1.4).
      TrainerOffday() => _SlotRow(
          time: time,
          trailing: const RiseBadge('코치 휴무', variant: RiseBadgeVariant.muted),
          dim: true,
        ),
    };
  }

  /// 예약을 받지 않는 패스 상태의 짧은 라벨. 모르는 값은 사실만 말한다
  /// (계약에 새 status가 추가돼도 행이 깨지지 않게 — my_models.statusLabel과 같은 규약).
  static String _passStatusLabel(String status) => switch (status) {
        'expired' => '만료',
        'refunded' => '환불됨',
        _ => '예약 불가',
      };
}

class _AllCoachSlotRow extends StatelessWidget {
  const _AllCoachSlotRow({
    required this.slot,
    required this.passes,
    required this.myMemberId,
    required this.onBook,
    required this.onCoachTap,
  });

  final Slot slot;
  final List<BookablePass> passes;
  final String myMemberId;
  final OnBookSlot onBook;
  final OnCoachTap onCoachTap;

  @override
  Widget build(BuildContext context) {
    final time = DateFmt.hhmm(slot.startAt);
    if (passes.isEmpty) {
      return _SlotRow(time: time, subtitle: '잔여 ${slot.remaining}/${slot.capacity}팀', dim: true);
    }

    final evaluations = [
      for (final p in passes) (p, BookingRules.evaluate(slot: slot, pass: p, myMemberId: myMemberId)),
    ];

    final alreadyBooked = evaluations.where((e) => e.$2 is AlreadyBookedByMe);
    if (alreadyBooked.isNotEmpty) {
      return _SlotRow(time: time, subtitle: '내 예약', trailing: const RiseBadge('확정', variant: RiseBadgeVariant.ok));
    }

    final tags = [for (final (p, state) in evaluations) _tagFor(p, state)];
    final bookable = evaluations.where((e) => e.$2 is Bookable);

    if (bookable.isNotEmpty) {
      final bookPass = bookable.first.$1;
      return RiseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$time · 잔여 ${slot.remaining}/${slot.capacity}팀',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
                RiseButton(label: '예약', small: true, onPressed: () => onBook(slot.slotKey, bookPass.passId)),
              ],
            ),
            const SizedBox(height: 6),
            // spacing 0 — 태그 자체의 히트 패딩(8px)이 간격을 만든다(_tagFor 주석).
            Wrap(children: tags),
          ],
        ),
      );
    }

    if (slot.isFull) {
      // v1 제품 결정: 만석 슬롯의 대기 신청 제거(내 코치 뷰와 동일) — 비활성 칩만.
      return _SlotRow(
        time: time,
        trailing: RiseBadge('${slot.capacity}/${slot.capacity} 만석', variant: RiseBadgeVariant.danger),
        dim: true,
      );
    }

    return Opacity(
      opacity: 0.8,
      child: RiseCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$time · 잔여 ${slot.remaining}/${slot.capacity}팀',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
            const SizedBox(height: 5),
            // spacing 0 — 태그 자체의 히트 패딩(8px)이 간격을 만든다(_tagFor 주석).
            Wrap(children: tags),
          ],
        ),
      ),
    );
  }

  Widget _tagFor(BookablePass p, SlotBookState state) {
    // 이 목록엔 "선택 가능한" 패스만 들어온다(isSelectable 필터: 현직 코치 + active +
    // 잔여>0) — 퇴사·잔여 0·환불 표기는 여기 도달하지 않는다. **예약 예산 소진
    // (AllRemainingBooked)은 예외로 도달한다** — 그 조건은 일부러 isSelectable에
    // 넣지 않았다(BookablePass 주석). 나머지 도달 불가 상태도 switch가 전부 덮는
    // 이유는 필터와 판정이 따로 진화할 때 조용히 어긋나지 않게 하기 위해서다
    // (도달하면 사실을 그대로 말한다).
    // resolve()는 이름이 ""로 와도 배지가 " 가능"처럼 앞이 비지 않게 한다.
    final name = CoachLabel.resolve(p.trainerName, fallback: '코치');
    final badge = switch (state) {
      Bookable() => RiseBadge('$name 가능', variant: RiseBadgeVariant.blue),
      CoachBusy() => RiseBadge('$name 수업중', variant: RiseBadgeVariant.muted),
      NotYetValid(:final validFrom) =>
        RiseBadge('$name ${validFrom.month}/${validFrom.day}부터', variant: RiseBadgeVariant.muted),
      PassExpiredForSlot(:final validUntil) =>
        RiseBadge('$name ${validUntil.month}/${validUntil.day}까지', variant: RiseBadgeVariant.muted),
      SlotFull() => RiseBadge('$name 만석', variant: RiseBadgeVariant.muted),
      AlreadyBookedByMe() => RiseBadge('$name 확정', variant: RiseBadgeVariant.ok),
      PassOnHoldForSlot() => RiseBadge('$name 일시정지 중', variant: RiseBadgeVariant.muted),
      // 담당 코치 휴무일 — 코치마다 다르므로 상단 안내로 뭉치지 않고 태그로 말한다.
      TrainerOffday() => RiseBadge('$name 휴무', variant: RiseBadgeVariant.muted),
      NoRemainingSessions() => RiseBadge('$name 잔여 0회', variant: RiseBadgeVariant.muted),
      // 이 상태는 필터를 통과해 **실제로 여기 도달한다** — isSelectable이 일부러
      // 거르지 않기 때문이다(BookablePass.isSelectable 주석: 걸러 버리면 이 회원이
      // 이미 잡아 둔 예약의 "확정" 배지까지 사라진다). "잔여 0회"와 다른 말을
      // 써야 한다 — 회차는 남아 있고 자리만 다 잡아 둔 상태다.
      AllRemainingBooked() => RiseBadge('$name 예약 다 잡음', variant: RiseBadgeVariant.muted),
      PassNotUsable() => RiseBadge('$name 예약 불가', variant: RiseBadgeVariant.muted),
    };
    // 코치 태그 탭 → 프로필 시트(P05). 예약 여부와 무관한 정보 조회라 전 상태에서 탭 허용.
    // 히트 영역만 상하좌우 8px 패딩으로 확대(44dp 근접) — 배지 시각 크기는 그대로.
    // 태그 간 간격은 이 투명 패딩이 대신 만들므로 Wrap spacing은 0.
    return InkWell(
      onTap: () => onCoachTap(p.trainerId, p.trainerName),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: badge,
      ),
    );
  }
}

/// 담당 코치 퇴사로 새 예약이 막힌 이유 + 다음 행동을 목록 맨 위에서 한 번 말한다.
/// 문구는 프로필 시트의 퇴사 안내와 같은 결로 맞춘다("새 담당 코치는 센터에 문의").
///
/// [hasOtherPass] — 다른 회원권으로는 아직 예약할 수 있는 상태. 그땐 "예약을 잡을
/// 수 없어요"가 사실이 아니므로(칩 하나만 바꾸면 된다) 다음 행동을 그쪽으로 돌린다.
class _RetiredCoachNotice extends StatelessWidget {
  const _RetiredCoachNotice(this.coachName, {required this.hasOtherPass});

  final String coachName;
  final bool hasOtherPass;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 배지 문구는 프로필 시트의 퇴사 배지와 같은 단어를 쓴다 — 행의 비활성
          // 버튼("예약 불가")과 겹치지 않게, 여기선 "왜"에 해당하는 사실만 말한다.
          const RiseBadge('퇴사', variant: RiseBadgeVariant.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasOtherPass
                  ? '$coachName 코치가 지금은 센터에서 활동하지 않아 이 회원권으로는 예약할 수 없어요 '
                      '— "내 회원권 전체"에서 다른 회원권으로 예약해주세요'
                  : '$coachName 코치가 지금은 센터에서 활동하지 않아 새 예약을 잡을 수 없어요 '
                      '— 새 담당 코치는 센터에 문의해주세요',
              style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 잔여 세션 소진으로 새 예약이 막힌 이유 + 다음 행동. 형식은 [_RetiredCoachNotice]와
/// 같은 결로 맞춘다 — "서버가 거부할 예약을 권하지 않는다"는 같은 원칙의 자리다.
///
/// 코치 이름을 부르지 않는 이유: 잔여는 회원권의 사정이지 코치의 사정이 아니다
/// (담당을 바꿔도 풀리지 않는다).
class _NoRemainingNotice extends StatelessWidget {
  const _NoRemainingNotice({required this.hasOtherPass});

  /// 다른 회원권으로는 아직 예약할 수 있는 상태 — 그땐 "예약을 잡을 수 없어요"가
  /// 사실이 아니므로(칩 하나만 바꾸면 된다) 다음 행동을 그쪽으로 돌린다.
  final bool hasOtherPass;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseBadge('잔여 0회', variant: RiseBadgeVariant.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasOtherPass
                  ? '이 회원권은 남은 세션을 모두 사용해서 예약할 수 없어요 '
                      '— "내 회원권 전체"에서 다른 회원권으로 예약해주세요'
                  : '남은 세션을 모두 사용해서 새 예약을 잡을 수 없어요 '
                      '— 재등록은 센터에 문의해주세요',
              style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// "잔여는 남았는데 이미 다 잡아 뒀다" 안내 — 서버 400 "이미 잡힌 예약 N건이 잔여
/// M회를 채웠어요 — 기존 예약을 정리하거나 회차를 추가해주세요"(P13 H1).
///
/// **[_NoRemainingNotice]와 다른 문구를 쓰는 게 이 위젯의 존재 이유다.** 잔여 0은
/// 재등록 말고 길이 없지만, 이쪽은 회원이 **이 화면 아래 "내 예약"에서 한 건
/// 취소하면 바로 풀린다**. 여기에 "재등록은 센터에 문의해주세요"를 띄우면 이미
/// 가진 회차를 두고 돈을 더 내라는 안내가 된다.
///
/// 잔여 숫자는 예약을 잡아도 줄지 않으므로(완료 시점 차감, P4) 회원 눈엔
/// "잔여 2회인데 예약이 안 됨"으로 보인다 — 그래서 두 숫자를 함께 말한다.
/// [pass]가 null이면(막힌 회원권이 여럿) 숫자 없이 상황만 말한다.
class _AllBookedNotice extends StatelessWidget {
  const _AllBookedNotice({required this.pass, required this.hasOtherPass});

  final BookablePass? pass;

  /// 다른 회원권으로는 아직 예약을 **만들 수 있는** 상태(canBookNew) — 그땐
  /// 다음 행동을 그쪽으로 돌린다.
  final bool hasOtherPass;

  @override
  Widget build(BuildContext context) {
    final counts = pass == null
        ? '이미 잡아 둔 예약이 남은 세션을 모두 채웠어요'
        : '남은 ${pass!.remaining}회를 이미 잡아 둔 예약 ${pass!.openBookings}건이 모두 채웠어요';
    return RiseCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseBadge('예약 다 잡음', variant: RiseBadgeVariant.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasOtherPass
                  ? '$counts — "내 회원권 전체"에서 다른 회원권으로 예약해주세요'
                  : '$counts — 아래 "내 예약"에서 기존 예약을 취소하면 다른 시간으로 다시 잡을 수 있어요',
              style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 담당 코치 휴무일 안내 — 서버 400 "담당 코치의 휴무일이에요"와 같은 뜻이되,
/// 회원이 다음에 할 수 있는 일(날짜 변경)까지 말한다. 다른 안내와 달리 **하루짜리**
/// 제약이라 "잡을 수 없어요"가 아니라 "이 날은"이라고 범위를 좁혀 말한다.
class _OffdayNotice extends StatelessWidget {
  const _OffdayNotice(this.coachName);

  final String coachName;

  @override
  Widget build(BuildContext context) {
    return RiseCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RiseBadge('휴무', variant: RiseBadgeVariant.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$coachName 코치가 이 날은 휴무예요 — 다른 날짜를 선택해주세요',
              style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.time,
    this.subtitle,
    this.note,
    this.trailing,
    this.dim = false,
  });

  final String time;
  final String? subtitle;
  final String? note;
  final Widget? trailing;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dim ? 0.8 : 1,
      child: RiseCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(time, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text('· $subtitle', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(note!, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
