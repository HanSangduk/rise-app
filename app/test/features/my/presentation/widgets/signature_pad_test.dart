// 자필 서명 패드(P44 결정 1·5) — 유효성 판정·지우기·PNG 내보내기·정규화 보존.
//
// 고정하는 계약:
//  · 유효성 = 획 ≥1 + 바운딩 박스(가로·세로 큰 쪽)가 패드 폭의 15% 이상 — 실제
//    표식은 전부 통과하고 점 하나·스친 자국만 걸리는 관대한 하한(결정 5).
//  · 내보내기 = 투명 배경 PNG, 픽셀 밀도 devicePixelRatio(상한 2x), 40KB 초과 시
//    0.7배 재렌더 최대 3회(출력 320×140 픽셀 바닥).
//  · 점은 패드 크기 비율(0~1)로 저장 — 리사이즈(회전)가 획을 지우지 못한다.
//    절대 좌표 저장이 회전에서 전부 잃는 것이 signature_pad JS 계열의 함정이다.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/features/my/presentation/widgets/signature_pad.dart';

import '../../../../support/font_loader.dart';

/// PNG 시그니처 8바이트 — "디코드 가능한 PNG"의 첫 관문.
const pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  setUpAll(loadPretendard);

  Future<void> pumpPad(
    WidgetTester tester,
    SignaturePadController controller, {
    double width = 340,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Pretendard'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SignaturePad(controller: controller),
            ),
          ),
        ),
      ),
    );
  }

  // 캔버스(패드 사각형) — [다시 쓰기]가 아니라 그리는 영역을 정확히 집는다.
  Finder canvas() => find.descendant(
      of: find.byType(SignaturePad), matching: find.byType(CustomPaint));

  Future<void> draw(WidgetTester tester, Offset delta, {Offset from = Offset.zero}) async {
    await tester.dragFrom(tester.getCenter(canvas()) + from, delta);
    await tester.pump();
  }

  group('유효성 — 획 1 + 바운딩 박스 하한(패드 폭 15%, 결정 5)', () {
    testWidgets('빈 패드는 무효 + 힌트가 떠 있다', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      expect(c.isValid, isFalse);
      expect(find.text('여기에 서명해 주세요'), findsOneWidget);
    });

    testWidgets('실제 표식(폭 15% 이상 드래그)이면 유효 — 힌트는 사라진다', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      // 340dp 패드의 15% = 51dp — 120dp 획은 여유 있게 넘는다.
      await draw(tester, const Offset(120, 15));

      expect(c.strokeCount, 1);
      expect(c.isValid, isTrue);
      expect(find.text('여기에 서명해 주세요'), findsNothing);
    });

    testWidgets('점 하나(탭)는 획으로 잡히지만 무효 — 스친 자국을 서명으로 치지 않는다', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      await tester.tapAt(tester.getCenter(canvas()));
      await tester.pump();

      expect(c.strokeCount, 1, reason: '탭도 점 획으로 기록은 된다(라운드 캡 점)');
      expect(c.isValid, isFalse, reason: '바운딩 박스 0 — 하한(15%)에 걸려야 한다');
    });

    testWidgets('짧은 자국(15% 미만)도 무효 — 세로로 큰 획은 세로 변으로 통과한다', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      await draw(tester, const Offset(30, 0)); // 30dp < 51dp
      expect(c.isValid, isFalse);

      // 세로 60dp 획 — 가로는 좁아도 실제 표식(예: "ㅣ" 같은 흘림)이다.
      await draw(tester, const Offset(0, 60));
      expect(c.isValid, isTrue, reason: '큰 쪽 변 기준 — 세로 획도 표식이다');
    });

    testWidgets('[다시 쓰기] — 전부 지워져 무효로 돌아가고 힌트가 다시 뜬다', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      await draw(tester, const Offset(120, 10));
      expect(c.isValid, isTrue);

      await tester.tap(find.text('다시 쓰기'));
      await tester.pump();

      expect(c.isEmpty, isTrue);
      expect(c.isValid, isFalse);
      expect(find.text('여기에 서명해 주세요'), findsOneWidget);
    });

    testWidgets('[다시 쓰기]의 터치 영역은 44dp 이상(P73)', (tester) async {
      // 오획을 지우는 유일한 길이다 — 글자 상자(≈36dp)만 누르면 서명 화면에서 가장 놓치기 쉬운
      // 버튼이 된다(`touch_target_test`의 기준과 같은 44dp).
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      final hit = tester.getSize(
        find.ancestor(of: find.text('다시 쓰기'), matching: find.byType(GestureDetector)).first,
      );
      expect(hit.height, greaterThanOrEqualTo(44));
    });
  });

  group('PNG 내보내기(결정 2) — 투명 배경 · 밀도 상한 2x · 40KB 상한', () {
    testWidgets('디코드 가능한 PNG, dpr 상한 2x 치수, 상한 이하, 배경 투명', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c); // 340×180
      await draw(tester, const Offset(140, 30));
      await draw(tester, const Offset(-80, 40), from: const Offset(20, -20));

      final bytes =
          await tester.runAsync(() => c.toPngBytes(devicePixelRatio: 3.0));
      expect(bytes, isNotNull);
      expect(bytes!.sublist(0, 8), pngMagic);
      expect(bytes.lengthInBytes, lessThanOrEqualTo(40 * 1024));
      // 실측 기록(P44 결정 2의 5~18KB 창 검증용) — 실패 조건은 아니다.
      debugPrint('signature export bytes: ${bytes.lengthInBytes}');

      final image = await tester.runAsync(() => decodeImageFromList(bytes));
      // dpr 3.0 → 상한 2x: 340×180 dp → 680×360 px.
      expect(image!.width, 680);
      expect(image.height, 360);

      // 투명 배경 — 원점 픽셀 알파 0(획은 캔버스 중앙 근처에만 있다).
      final rgba = await tester
          .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
      expect(rgba!.getUint8(3), 0, reason: '배경을 칠했다면 투명 PNG 계약 위반');
    });

    testWidgets('상한 초과 시 축소 재렌더 — 최대 3회 · 바닥 320×140 · 그래도 바이트는 돌려준다', (tester) async {
      // 운영 상한(40KB)은 균일 잉크 획으로는 도달 불가다 — 합성 노이즈 획
      // 1,600개도 3KB대(프로브 실측: 400개 7.8KB → 1,600개 2.3KB, 채움이 늘수록
      // 오히려 준다). 그래서 루프는 테스트 시임(maxBytes)으로 결정적으로 밟는다.
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c);

      final rng = math.Random(42);
      for (var s = 0; s < 40; s++) {
        c.debugAddStroke([
          for (var p = 0; p < 24; p++) Offset(rng.nextDouble(), rng.nextDouble()),
        ]);
      }

      final bytes = await tester.runAsync(
          () => c.toPngBytes(devicePixelRatio: 2.0, maxBytes: 1000));
      expect(bytes!.sublist(0, 8), pngMagic);
      expect(c.debugLastExportRerenders, inInclusiveRange(1, 3),
          reason: '1KB 상한은 반드시 축소 루프를 태워야 한다');

      final image = await tester.runAsync(() => decodeImageFromList(bytes));
      // 바닥 존중 — 축소가 계속돼도 320×140 픽셀 아래로는 내려가지 않는다.
      expect(image!.width, greaterThanOrEqualTo(320));
      expect(image.height, greaterThanOrEqualTo(140));
      // 바닥·횟수 제한 때문에 상한을 못 맞출 수 있다 — 그래도 서명을 버리지 않고
      // 바이트를 돌려주는 것이 계약이다(빈 결과·예외 금지).
      expect(bytes, isNotEmpty);

      // 운영 상한 상수 자체도 고정 — 시임 기본값이 40KB에서 움직이면 잡는다.
      expect(SignaturePadController.maxExportBytes, 40 * 1024);
    });
  });

  group('정규화 저장 — 리사이즈(회전)가 획을 지우지 못한다(P44 리서치의 함정)', () {
    testWidgets('패드 폭이 바뀌어도 점(정규화 좌표)은 그대로고 유효성도 산다', (tester) async {
      final c = SignaturePadController();
      addTearDown(c.dispose);
      await pumpPad(tester, c, width: 340);
      await draw(tester, const Offset(120, 20));
      expect(c.isValid, isTrue);
      final before = [
        for (final s in c.debugStrokes) [for (final p in s) p],
      ];

      // 회전/리사이즈 재현 — 같은 컨트롤러로 다른 폭에 다시 레이아웃.
      await pumpPad(tester, c, width: 240);
      await tester.pump();

      final after = c.debugStrokes;
      expect(after.length, before.length);
      for (var s = 0; s < before.length; s++) {
        expect(after[s], before[s], reason: '정규화 점 자체는 크기와 무관해야 한다');
      }
      // 비율 판정이라 새 폭(240dp, 15% = 36dp)에서도 같은 획이 유효하다.
      expect(c.isValid, isTrue);

      // 내보내기는 새 레이아웃 크기 기준 — 240×180 dp → 480×360 px(2x).
      final bytes =
          await tester.runAsync(() => c.toPngBytes(devicePixelRatio: 2.0));
      final image = await tester.runAsync(() => decodeImageFromList(bytes!));
      expect(image!.width, 480);
      expect(image.height, 360);
    });
  });
}
