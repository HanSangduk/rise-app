import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/theme/app_theme.dart';
import 'package:rise_member/core/utils/date_format.dart';
import 'package:rise_member/core/widgets/rise_button.dart';
import 'package:rise_member/features/booking/domain/booking_models.dart';
import 'package:rise_member/features/booking/presentation/widgets/slot_list.dart';

// 계약 v2.0 — 퇴사한 담당 코치로 새 예약을 잡을 수 없게 막는 규칙이 "내 회원권 전체"
// 모드에만 걸려 있던 문제.
//
// ShowMyCoachOnly.build()가 true라 **회원이 처음 보는 화면은 "내 코치" 모드**인데,
// 그쪽은 담당 패스 하나로 고정이라 isSelectable 필터가 없다. 그래서 퇴사 코치의
// 슬롯이 Bookable 상태 그대로, 살아 있는 "예약" 버튼째 렌더됐다 — 서버가 400으로
// 거부할 예약을 권한 셈이고 행은 코치를 완전히 현직처럼 보여줬다.
//
// 고친 방향: 행을 숨기지 않는다(숨기면 이유도 모른 채 빈 화면을 본다). 행은 남기고
// 예약 버튼을 비활성("예약 불가")으로, 이유와 다음 행동은 목록 상단 안내가 한 번만.
void main() {
  // 오늘 슬롯은 "지남" 분기에 걸릴 수 있어 항상 내일 날짜로 만든다.
  //
  // **기준축은 KST여야 한다.** SlotList는 "지남"을 `DateFmt.nowKst()`로 판정하고
  // 슬롯 시각도 KST 벽시계 표현이다(DateFmt 클래스 주석의 시간축 규약). 픽스처만
  // `DateTime.now()`(기기 로컬)로 만들면 KST보다 뒤에 있는 지역(하와이 등)에서는
  // 로컬의 "내일"이 KST의 "오늘"과 겹쳐, 오전 슬롯이 전부 "지남"으로 렌더된다 —
  // 예약 버튼도 상태 칩도 사라져 이 파일 전체가 특정 시간대에서만 빨간불이 된다.
  final tomorrow = DateFmt.todayKst().add(const Duration(days: 1));

  Slot slot({int hour = 10, List<SlotTeam> teams = const []}) => Slot(
        slotKey: DateFmt.toSlotKey(tomorrow, hour),
        capacity: 3,
        teams: teams,
      );

  BookablePass pass({
    String passId = 'p1',
    String trainerId = 't1',
    String? trainerName = '정혜린',
    bool trainerInactive = false,
    String status = 'active',
    int remaining = 5,
    int openBookings = 0,
    Set<String> offdays = const {},
  }) {
    return BookablePass(
      passId: passId,
      trainerId: trainerId,
      trainerName: trainerName,
      trainerInactive: trainerInactive,
      trainerOffdays: offdays,
      product: 'PT 20회',
      validFrom: DateTime(2026, 1, 1),
      validUntil: DateTime(2030, 12, 31),
      status: status,
      remaining: remaining,
      openBookings: openBookings,
    );
  }

  final booked = <String>[];

  Future<void> pumpList(
    WidgetTester tester, {
    required List<Slot> slots,
    required List<BookablePass> passes,
    bool showMyCoachOnly = true,
    DateTime? selectedDate,
  }) async {
    booked.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SlotList(
              selectedDate: selectedDate ?? tomorrow,
              slots: slots,
              myPasses: passes,
              primaryPassId: passes.first.passId,
              myMemberId: 'm1',
              showMyCoachOnly: showMyCoachOnly,
              onBook: (slotKey, passId) => booked.add('$slotKey/$passId'),
              onCoachTap: (_, __) {},
            ),
          ),
        ),
      ),
    );
  }

  /// 라벨이 [label]인 RiseButton들의 "눌리는가" 목록.
  List<bool> buttonsEnabled(WidgetTester tester, String label) => tester
      .widgetList<RiseButton>(
        find.ancestor(of: find.text(label), matching: find.byType(RiseButton)),
      )
      .map((b) => b.onPressed != null)
      .toList();

  group('내 코치 모드 — 퇴사한 담당 코치', () {
    testWidgets('예약 버튼이 죽고 행은 그대로 남는다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11)],
        passes: [pass(trainerInactive: true)],
      );

      // 살아 있는 "예약" 버튼은 하나도 없어야 한다(서버가 거부할 예약 권유 금지).
      expect(find.text('예약'), findsNothing);
      // 그렇다고 행을 숨기지도 않는다 — 시간과 잔여는 그대로 보인다.
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('· 잔여 3/3팀'), findsNWidgets(2));
      // 버튼 자리는 비활성 "예약 불가"(NotYetValid·PassExpiredForSlot와 같은 형식).
      expect(find.text('예약 불가'), findsNWidgets(2));
      expect(buttonsEnabled(tester, '예약 불가'), [isFalse, isFalse]);
    });

    testWidgets('이유와 다음 행동을 안내한다 — 목록 전체에 한 번만', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11), slot(hour: 12)],
        passes: [pass(trainerInactive: true)],
      );

      expect(find.textContaining('정혜린 코치가 지금은 센터에서 활동하지 않아'), findsOneWidget);
      expect(find.textContaining('센터에 문의해주세요'), findsOneWidget);
    });

    testWidgets('다른 회원권으로 예약할 수 있으면 그쪽으로 안내한다', (tester) async {
      // "예약을 잡을 수 없어요"는 이 경우 사실이 아니다 — 칩 하나만 바꾸면 된다.
      await pumpList(
        tester,
        slots: [slot()],
        passes: [
          pass(trainerInactive: true),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오'),
        ],
      );

      expect(find.textContaining('"내 회원권 전체"에서 다른 회원권으로'), findsOneWidget);
      expect(find.textContaining('센터에 문의해주세요'), findsNothing);
      // 그래도 이 모드의 행들은 여전히 예약 불가(담당 패스는 퇴사 코치의 것).
      expect(find.text('예약'), findsNothing);
    });

    testWidgets('이름을 해석하지 못해도 "null 코치"가 아니라 "담당 코치"', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [pass(trainerName: null, trainerInactive: true)],
      );

      expect(find.textContaining('담당 코치가 지금은'), findsOneWidget);
    });

    testWidgets('열린 슬롯이 없는 날짜에도 이유는 보인다', (tester) async {
      await pumpList(tester, slots: [], passes: [pass(trainerInactive: true)]);

      expect(find.text('이 날짜엔 열린 슬롯이 없어요'), findsOneWidget);
      expect(find.textContaining('활동하지 않아'), findsOneWidget);
    });

    testWidgets('이미 잡힌 내 예약은 건드리지 않는다(확정 그대로)', (tester) async {
      // 계약 v2.0: 필터는 "새 예약 선택지"에만 적용하고 기존 예약은 그대로 둔다.
      await pumpList(
        tester,
        slots: [
          slot(
            hour: 10,
            teams: [
              const SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'm1', kind: 'pt'),
            ],
          ),
        ],
        passes: [pass(trainerInactive: true)],
      );

      expect(find.text('확정'), findsOneWidget);
      expect(find.text('· 내 예약'), findsOneWidget);
      expect(find.text('예약 불가'), findsNothing);
    });
  });

  group('현직 코치 — 정상 예약 흐름은 그대로', () {
    testWidgets('"예약" 버튼이 살아 있고 탭하면 그 패스로 예약이 시작된다', (tester) async {
      await pumpList(tester, slots: [slot(hour: 10)], passes: [pass()]);

      expect(find.text('예약'), findsOneWidget);
      expect(buttonsEnabled(tester, '예약'), [isTrue]);
      expect(find.text('예약 불가'), findsNothing);
      expect(find.textContaining('활동하지 않아'), findsNothing);

      await tester.tap(find.text('예약'));
      await tester.pump();

      expect(booked, ['${DateFmt.toSlotKey(tomorrow, 10)}/p1']);
    });

    testWidgets('코치 수업중 등 기존 비활성 상태 표기도 그대로', (tester) async {
      await pumpList(
        tester,
        slots: [
          slot(
            hour: 10,
            teams: [
              const SlotTeam(bookingId: 'b9', trainerId: 't1', memberId: '', kind: 'pt'),
            ],
          ),
        ],
        passes: [pass()],
      );

      expect(find.text('코치 수업중'), findsOneWidget);
      expect(find.textContaining('정혜린 코치가 이 시간 수업 중이에요'), findsOneWidget);
    });
  });

  group('내 회원권 전체 모드', () {
    testWidgets('선택 가능한 패스가 하나도 없으면 이유를 말한다', (tester) async {
      // 필터가 목록을 비우는 것만으로는 부족했다 — 잔여 숫자만 적힌 회색 목록이
      // 되어 회원은 왜 예약이 안 되는지 알 수 없었다.
      await pumpList(
        tester,
        slots: [slot()],
        passes: [pass(trainerInactive: true)],
        showMyCoachOnly: false,
      );

      expect(find.textContaining('정혜린 코치가 지금은 센터에서 활동하지 않아'), findsOneWidget);
      expect(find.text('예약'), findsNothing);
    });

    testWidgets('퇴사 코치가 여럿이면 한 명만 지목하지 않는다', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [
          pass(trainerInactive: true),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', trainerInactive: true),
        ],
        showMyCoachOnly: false,
      );

      expect(find.textContaining('담당 코치가 지금은'), findsOneWidget);
      expect(find.textContaining('정혜린 코치가'), findsNothing);
    });

    testWidgets('현직 패스가 하나라도 있으면 안내 없이 기존 그대로 예약된다', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [
          pass(trainerInactive: true),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오'),
        ],
        showMyCoachOnly: false,
      );

      expect(find.textContaining('활동하지 않아'), findsNothing);
      expect(find.text('예약'), findsOneWidget);
      expect(buttonsEnabled(tester, '예약'), [isTrue]);
      // 태그도 현직 코치 것만 — 퇴사자는 선택지에서 빠진다(isSelectable).
      expect(find.text('김태오 가능'), findsOneWidget);
      expect(find.textContaining('정혜린'), findsNothing);
    });

    testWidgets('퇴사와 무관한 이유로 목록이 비면 퇴사 안내를 하지 않는다', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [pass(status: 'expired')],
        showMyCoachOnly: false,
      );

      expect(find.textContaining('활동하지 않아'), findsNothing);
    });
  });

  // 잔여 0은 예외가 아니라 **모든 회원의 종착 상태**다: 백엔드엔 패스를 expired로
  // 넘기는 코드가 없어서 20회를 다 써도 유효기간이 남는 한 status는 계속 active다.
  // 그래서 예전엔 회원 전원이 언젠가 "눌리는데 서버가 100% 거부하는 예약 버튼"을
  // 만났다(400 "잔여 세션이 없어요"). 퇴사 코치와 같은 처방을 적용한다.
  group('잔여 0인 회원권', () {
    testWidgets('내 코치 모드 — 예약 버튼이 죽고 잔여 0회를 행에 적는다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11)],
        passes: [pass(remaining: 0)],
      );

      expect(find.text('예약'), findsNothing);
      expect(find.text('예약 불가'), findsNWidgets(2));
      expect(buttonsEnabled(tester, '예약 불가'), [isFalse, isFalse]);
      // "잔여 3/3팀"(슬롯 팀 수)과 헷갈리지 않게 "세션"이라고 못박는다.
      expect(find.text('· 잔여 세션 0회'), findsNWidgets(2));
      // 행은 숨기지 않는다 — 시간은 그대로 보인다.
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('이유와 다음 행동(재등록 문의)을 목록 상단에서 한 번만 말한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11), slot(hour: 12)],
        passes: [pass(remaining: 0)],
      );

      expect(find.textContaining('남은 세션을 모두 사용해서'), findsOneWidget);
      expect(find.textContaining('센터에 문의해주세요'), findsOneWidget);
    });

    testWidgets('열린 슬롯이 없는 날짜에도 이유는 보인다 — 날짜를 옮겨도 안 된다', (tester) async {
      await pumpList(tester, slots: [], passes: [pass(remaining: 0)]);

      expect(find.text('이 날짜엔 열린 슬롯이 없어요'), findsOneWidget);
      expect(find.textContaining('남은 세션을 모두 사용해서'), findsOneWidget);
    });

    testWidgets('다른 회원권에 잔여가 있으면 그쪽으로 안내한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [
          pass(remaining: 0),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', remaining: 3),
        ],
      );

      expect(find.textContaining('"내 회원권 전체"에서 다른 회원권으로'), findsOneWidget);
      expect(find.textContaining('센터에 문의해주세요'), findsNothing);
    });

    testWidgets('이미 잡힌 내 예약은 확정 그대로 — 잔여 0으로 덮지 않는다', (tester) async {
      await pumpList(
        tester,
        slots: [
          slot(hour: 10, teams: [
            const SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'm1', kind: 'pt'),
          ]),
        ],
        passes: [pass(remaining: 0)],
      );

      expect(find.text('확정'), findsOneWidget);
      expect(find.text('· 내 예약'), findsOneWidget);
    });

    testWidgets('내 회원권 전체 모드 — 잔여 0 패스는 선택지에서 빠지고 이유를 말한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [pass(remaining: 0)],
        showMyCoachOnly: false,
      );

      expect(find.text('예약'), findsNothing);
      expect(find.textContaining('남은 세션을 모두 사용해서'), findsOneWidget);
      // 퇴사와 잔여 0을 섞어 말하지 않는다.
      expect(find.textContaining('활동하지 않아'), findsNothing);
    });

    testWidgets('퇴사와 잔여 0이 겹치면 안내는 하나만 — 퇴사가 먼저', (tester) async {
      await pumpList(
        tester,
        slots: [slot()],
        passes: [pass(remaining: 0, trainerInactive: true)],
      );

      expect(find.textContaining('활동하지 않아'), findsOneWidget);
      expect(find.textContaining('남은 세션을 모두 사용해서'), findsNothing);
    });
  });

  // 서버는 슬롯이 비어 있어도 담당 코치 휴무일이면 400 "담당 코치의 휴무일이에요"로
  // 거부한다(v1.4). 앱은 offdays를 파싱조차 하지 않아 휴무일 슬롯이 정상 "예약 가능"
  // 으로 보였고, 회원은 확정 시트까지 간 뒤에야 이유 모를 400을 받았다.
  group('담당 코치 휴무일', () {
    testWidgets('휴무일 슬롯은 예약 버튼 대신 "코치 휴무" 칩', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11)],
        passes: [pass(offdays: {DateFmt.isoDate(tomorrow)})],
      );

      expect(find.text('예약'), findsNothing);
      expect(find.text('코치 휴무'), findsNWidgets(2));
    });

    testWidgets('이유와 다음 행동(날짜 변경)을 상단에서 한 번만 말한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11)],
        passes: [pass(offdays: {DateFmt.isoDate(tomorrow)})],
      );

      expect(find.textContaining('정혜린 코치가 이 날은 휴무예요'), findsOneWidget);
      expect(find.textContaining('다른 날짜를 선택해주세요'), findsOneWidget);
    });

    testWidgets('휴무가 아닌 날짜는 평소대로 예약된다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        // 휴무는 어제 — 오늘 목록에 영향을 주면 안 된다.
        passes: [pass(offdays: {DateFmt.isoDate(tomorrow.subtract(const Duration(days: 1)))})],
      );

      expect(find.text('예약'), findsOneWidget);
      expect(buttonsEnabled(tester, '예약'), [isTrue]);
      expect(find.textContaining('휴무'), findsNothing);
    });

    testWidgets('유효기간이 함께 걸린 날엔 휴무를 이유로 내세우지 않는다 — 행과 같은 이유만', (tester) async {
      // 상단 안내가 조건을 손으로 다시 쓰면, 행은 "8/10까지"라 하고 상단은 "휴무"라
      // 하는 식으로 한 화면이 두 이유를 말하게 된다(판정은 규칙 엔진 한 곳에서).
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [
          BookablePass(
            passId: 'p1',
            trainerId: 't1',
            trainerName: '정혜린',
            trainerOffdays: {DateFmt.isoDate(tomorrow)},
            product: 'PT 20회',
            validFrom: DateTime(2026, 1, 1),
            validUntil: DateTime(2026, 8, 10), // 이미 만료된 기간
            status: 'active',
            remaining: 5,
            openBookings: 0,
          ),
        ],
      );

      expect(find.textContaining('휴무'), findsNothing);
      expect(find.text('8/10까지'), findsOneWidget);
    });

    testWidgets('내 회원권 전체 모드 — 상단 안내 대신 코치별 태그로 말한다', (tester) async {
      // 휴무는 코치별 사정이라 여러 패스를 함께 보는 모드에선 한 문장으로 뭉칠 수 없다.
      await pumpList(
        tester,
        slots: [slot()],
        passes: [
          pass(offdays: {DateFmt.isoDate(tomorrow)}),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오'),
        ],
        showMyCoachOnly: false,
      );

      expect(find.text('정혜린 휴무'), findsOneWidget);
      expect(find.text('김태오 가능'), findsOneWidget);
      expect(find.textContaining('이 날은 휴무예요'), findsNothing);
      // 휴무가 아닌 코치로는 그대로 예약된다.
      expect(find.text('예약'), findsOneWidget);
    });
  });

  // P13 H1 — 서버 예약 예산: `잔여 − 이 패스의 confirmed 예약 수`. 잔여는 완료
  // 시점에만 차감되므로(P4) `remaining > 0`이어도 거부된다. 잔여 숫자가 멀쩡히
  // 보이는 상태라 잔여 0보다 더 헷갈리고, **다음 행동이 정반대다**(재등록이
  // 아니라 기존 예약 취소).
  group('잔여는 남았는데 이미 다 잡아 둔 회원권', () {
    testWidgets('예약 버튼이 죽고, 행이 두 숫자를 함께 말한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10), slot(hour: 11)],
        passes: [pass(remaining: 2, openBookings: 2)],
      );

      expect(find.text('예약'), findsNothing);
      // "잔여 2회인데 왜 안 되지"가 기본 반응이라 원인(예약 2건)을 나란히 보여준다.
      expect(find.text('· 잔여 2회 · 예약 2건'), findsNWidgets(2));
      expect(buttonsEnabled(tester, '예약 불가'), [isFalse, isFalse]);
    });

    testWidgets('다음 행동은 재등록이 아니라 기존 예약 취소', (tester) async {
      // 잔여 0 문구("재등록은 센터에 문의")를 여기 쓰면 이미 가진 회차를 두고
      // 돈을 더 내라는 안내가 된다.
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [pass(remaining: 2, openBookings: 2)],
      );

      expect(find.textContaining('남은 2회를 이미 잡아 둔 예약 2건이 모두 채웠어요'), findsOneWidget);
      expect(find.textContaining('기존 예약을 취소하면'), findsOneWidget);
      expect(find.textContaining('재등록'), findsNothing);
      expect(find.textContaining('남은 세션을 모두 사용해서'), findsNothing);
    });

    testWidgets('잔여 0은 종전 문구 그대로 — 두 상태를 뭉치지 않는다', (tester) async {
      await pumpList(tester, slots: [slot(hour: 10)], passes: [pass(remaining: 0)]);

      expect(find.textContaining('재등록은 센터에 문의해주세요'), findsOneWidget);
      expect(find.textContaining('기존 예약을 취소하면'), findsNothing);
      expect(find.text('· 잔여 세션 0회'), findsOneWidget);
    });

    testWidgets('예산이 남은 다른 회원권이 있으면 그쪽으로 안내한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [
          pass(remaining: 2, openBookings: 2),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', remaining: 3, openBookings: 1),
        ],
      );

      expect(find.textContaining('"내 회원권 전체"에서 다른 회원권으로'), findsOneWidget);
      expect(find.textContaining('기존 예약을 취소하면'), findsNothing);
    });

    testWidgets('다른 회원권도 다 잡아 뒀으면 그쪽을 권하지 않는다', (tester) async {
      // isSelectable만 보면 예산 0인 패스도 "선택 가능"이라 여기서 갈린다 —
      // 안내대로 칩을 바꾼 회원이 거기서 또 거부당한다.
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [
          pass(remaining: 2, openBookings: 2),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', remaining: 4, openBookings: 4),
        ],
      );

      expect(find.textContaining('"내 회원권 전체"에서 다른 회원권으로'), findsNothing);
      expect(find.textContaining('기존 예약을 취소하면'), findsOneWidget);
    });

    testWidgets('내 회원권 전체 — 코치별 태그로 말하고, 막힌 게 여럿이면 숫자는 뭉치지 않는다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [
          pass(remaining: 2, openBookings: 2),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', remaining: 4, openBookings: 4),
        ],
        showMyCoachOnly: false,
      );

      expect(find.text('정혜린 예약 다 잡음'), findsOneWidget);
      expect(find.text('김태오 예약 다 잡음'), findsOneWidget);
      expect(find.text('예약'), findsNothing);
      // 패스마다 숫자가 달라 하나를 고르면 나머지에 거짓이 된다 — 숫자 없이 안내.
      expect(find.textContaining('이미 잡아 둔 예약이 남은 세션을 모두 채웠어요'), findsOneWidget);
    });

    testWidgets('내 회원권 전체 — 잔여 0과 함께 막혔으면 풀기 어려운 쪽(잔여 0)을 먼저 말한다', (tester) async {
      // "막힌 게 있는가"를 isSelectable로 판정하면 예산 0인 패스가 "선택 가능"으로
      // 세어져 잔여 0 안내가 통째로 삼켜진다 — 재등록이 필요한 회원에게 "기존
      // 예약을 취소하세요"라고 말하게 된다.
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [
          pass(remaining: 0),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', remaining: 4, openBookings: 4),
        ],
        showMyCoachOnly: false,
      );

      expect(find.textContaining('재등록은 센터에 문의해주세요'), findsOneWidget);
      expect(find.textContaining('기존 예약을 취소하면'), findsNothing);
    });

    testWidgets('내 회원권 전체 — 퇴사와 함께 막혔으면 퇴사를 먼저 말한다', (tester) async {
      await pumpList(
        tester,
        slots: [slot(hour: 10)],
        passes: [
          pass(trainerInactive: true),
          pass(passId: 'p2', trainerId: 't2', trainerName: '김태오', remaining: 4, openBookings: 4),
        ],
        showMyCoachOnly: false,
      );

      expect(find.textContaining('센터에 문의해주세요'), findsOneWidget);
      expect(find.textContaining('활동하지 않아'), findsOneWidget);
      expect(find.textContaining('기존 예약을 취소하면'), findsNothing);
    });

    testWidgets('내 회원권 전체 — 다 잡아 뒀어도 이미 잡힌 내 예약은 "확정" 그대로', (tester) async {
      // 이 패스를 isSelectable에서 걸러 버리면 목록이 비어(passes.isEmpty) 확정
      // 배지가 통째로 사라진다 — 예약을 다 잡았다는 이유로 예약이 안 보이는 화면.
      await pumpList(
        tester,
        slots: [
          slot(
            hour: 10,
            teams: [
              const SlotTeam(bookingId: 'b1', trainerId: 't1', memberId: 'm1', kind: 'pt'),
            ],
          ),
        ],
        passes: [pass(remaining: 2, openBookings: 2)],
        showMyCoachOnly: false,
      );

      expect(find.text('확정'), findsOneWidget);
      expect(find.text('· 내 예약'), findsOneWidget);
    });
  });

  // 서버는 예약도 홀딩도 active 상태 패스만 받는다. 환불된 패스는 유효기간이 남아
  // 있을 수 있어, 그대로 두면 "잔여 0"과 똑같이 100% 실패하는 버튼이 뜬다.
  group('환불·만료된 회원권', () {
    testWidgets('환불 패스가 대표면 예약 버튼 대신 "환불됨" 비활성 라벨', (tester) async {
      await pumpList(tester, slots: [slot()], passes: [pass(status: 'refunded')]);

      expect(find.text('예약'), findsNothing);
      expect(find.text('환불됨'), findsOneWidget);
      expect(buttonsEnabled(tester, '환불됨'), [isFalse]);
    });

    testWidgets('만료 패스는 "만료"', (tester) async {
      await pumpList(tester, slots: [slot()], passes: [pass(status: 'expired')]);

      expect(find.text('만료'), findsOneWidget);
      expect(buttonsEnabled(tester, '만료'), [isFalse]);
    });
  });

  // P51의 같은 클래스 — "지남"은 그린 순간의 시각으로 굳으면 안 된다.
  //
  // 이 목록은 StatelessWidget이고 예약 탭은 indexedStack에 상주하므로
  // (core/router/app_router.dart) 아무도 리빌드해 주지 않는다. 13:55에 열어 둔
  // 화면이 14:05에도 14:00 슬롯에 "예약" 버튼을 들고 있으면, 그 클릭은 **실제로
  // confirmed 예약이 된다** — 서버에도 BookingRules.evaluate에도 "지금"을 보는
  // 분기가 없기 때문이다. 참석할 수 없는 수업 하나가 노쇼로 세션 1회를 먹고,
  // countOpenBookings가 그걸 세므로 예약 예산까지 잠식한다.
  //
  // 시각은 `withClock`으로 고정한다(DateFmt.nowKst()가 clock.now()를 읽는다).
  // UTC로 주입하고 KST로 기대하므로 TZ 독립이다.
  group('"지남" — 시간이 흐르면 스스로 넘어간다', () {
    /// KST 벽시계 [h]시에 해당하는 절대 시각.
    DateTime kstAt(int h, int m) => DateTime.utc(2026, 8, 23, h - 9, m);

    /// withClock 고정 시각과 같은 날(2026-08-23)의 슬롯.
    Slot todaySlot(int hour) =>
        Slot(slotKey: DateFmt.toSlotKey(DateTime(2026, 8, 23), hour), capacity: 3);

    Future<void> pumpToday(WidgetTester tester, List<Slot> slots) => pumpList(
          tester,
          slots: slots,
          passes: [pass()],
          selectedDate: DateTime(2026, 8, 23),
        );

    testWidgets('아직 안 온 슬롯은 예약 버튼, 이미 지난 슬롯은 "지남" 칩', (tester) async {
      await withClock(Clock.fixed(kstAt(13, 55)), () async {
        await pumpToday(tester, [todaySlot(13), todaySlot(14)]);

        expect(find.text('지남'), findsOneWidget); // 13시만
        expect(buttonsEnabled(tester, '예약'), [isTrue]); // 14시
      });
    });

    testWidgets('13:55에 열어 두고 14:05가 되면 14시 행이 스스로 "지남"이 된다', (tester) async {
      var fake = kstAt(13, 55);

      await withClock(Clock(() => fake), () async {
        await pumpToday(tester, [todaySlot(14), todaySlot(15)]);
        expect(buttonsEnabled(tester, '예약'), [isTrue, isTrue]);
        expect(find.text('지남'), findsNothing);

        // 회원은 다른 탭에 갔다 오지도, 당겨서 새로고침하지도 않는다.
        fake = kstAt(14, 5);
        await tester.pump(const Duration(minutes: 10));

        expect(find.text('지남'), findsOneWidget,
            reason: '살아 있는 "예약" 버튼으로 지난 슬롯을 잡으면 서버가 받아 준다 — 노쇼 1회 차감으로 끝난다');
        expect(buttonsEnabled(tester, '예약'), [isTrue], reason: '15시는 아직 멀쩡해야 한다');
      });
    });

    testWidgets('다른 날짜를 보는 동안에는 경계가 없다 — 헛되이 깨우지 않는다', (tester) async {
      var fake = kstAt(13, 55);
      final future = DateTime(2026, 8, 30);

      await withClock(Clock(() => fake), () async {
        await pumpList(
          tester,
          slots: [Slot(slotKey: DateFmt.toSlotKey(future, 10), capacity: 3)],
          passes: [pass()],
          selectedDate: future,
        );
        expect(buttonsEnabled(tester, '예약'), [isTrue]);

        fake = kstAt(23, 0);
        await tester.pump(const Duration(hours: 9));

        expect(buttonsEnabled(tester, '예약'), [isTrue]);
        expect(find.text('지남'), findsNothing);
      });
    });
  });
}
