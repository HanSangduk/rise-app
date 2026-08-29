import 'package:flutter/material.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';

const _weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];

/// 목업 날짜 스트립 — "금 14 · 토 15 · 일 16 …" 가로 스크롤(오늘부터 14일).
class DateStrip extends StatelessWidget {
  const DateStrip({super.key, required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    // "오늘"은 센터(KST) 기준 — 기기 로컬 날짜로 시작하면 해외 체류 시 스트립이
    // 하루 어긋나고, 기본 선택일(SelectedBookingDate)과 칩 목록이 서로 안 맞는다.
    final base = DateFmt.todayKst();
    final days = List.generate(14, (i) => base.add(Duration(days: i)));

    // 예약 흐름의 주 내비게이션 — 날짜 칩은 44dp 히트가 필요하다(RiseChip이 상하
    // 9의 투명 패딩으로 만든다).
    //
    // 높이를 고정하지 않는 이유: 가로 ListView는 자식에 cross축 **tight** 제약을
    // 준다 — 고정 높이가 곧 칩 높이가 되어, 히트 패딩 18을 뺀 나머지로 알약이
    // 눌리고 글자가 알약 밖으로 새어 나온다(Pretendard 10.5px 기준 알약 자연
    // 높이는 29 + 하단 마진 4 = 33이라 고정 44로는 담기지 않는다). 내용에 맞춰
    // 높이가 정해지게 두면 알약은 목업 `.chip`의 자연 크기 그대로 남고
    // 히트 영역만 커진다 — 폰트가 바뀌어도 다시 눌리지 않는다.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in days)
            RiseChip(
              label: '${_weekdayKo[d.weekday - 1]} ${d.day}',
              selected: _isSameDay(d, selected),
              onTap: () => onSelect(d),
            ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
