// 날짜 스크러버(P31).
//
// 람의 지적: *"타임라인 쌓이면 아래 프로그레스바로 비교하면서 볼 수 있게 해줬었잖아,
// 드래그하면서? 그런거 없어졌나?"* — 맞는 지적이고, 그 슬라이더는 **한 번도 동작한 적이
// 없다.** 목업(`목업_회원앱_라이즈_2026-08-14.html:245`)의 `<input type="range">`에
// 핸들러가 없었고, Flutter로 옮긴 뒤에도 `_slider`는 자기 값만 읽고 썼다(두 사진은 고정
// 50:50 `Expanded`). 나는 그걸 **제거**했는데, 없앨 게 아니라 동작하게 만들었어야 했다.
//
// 이 스위트가 잠그는 것은 **"슬라이더가 있다"가 아니라 "끌면 사진이 바뀐다"**이다.
// 종전 테스트가 `find.byType(Slider)`의 존재로 비교 UI를 판정하는 바람에 죽은 컨트롤이
// P31까지 살아남았다 — 같은 실수를 되풀이하지 않으려고 **타일의 ValueKey가 실제로
// 바뀌는지**를 본다.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/core/widgets/rise_chip.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_timeline.dart';

void main() {
  BodyPhotoEntry photo(String pose, int day, {int year = 2026, int month = 8}) =>
      BodyPhotoEntry(
        id: '$pose-$year$month$day',
        memberId: 'm1',
        pose: pose,
        direction: BodyDirection.front,
        date: DateTime(year, month, day),
        blurred: false,
        storagePath: 'members/m1/body/$pose-$year$month$day.jpg',
      );

  Future<void> pump(WidgetTester tester, List<BodyPhotoEntry> photos,
      {BodyPhotoLoader? loader}) async {
    // 기본 테스트 표면(800×600)은 이 카드에 맞지 않는다 — 타일이 3:4라 폭이 넓으면
    // 그만큼 높아져서 스크러버가 폴드 밖으로 나가고 드래그가 빗나간다. 실기기(384dp)
    // 폭으로 맞춰야 화면에서 벌어지는 일을 검사하는 게 된다.
    tester.view.physicalSize = const Size(384, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (loader != null) bodyPhotoLoaderProvider.overrideWithValue(loader),
        ],
        child: MaterialApp(
          home: Scaffold(
            // 실제 부모와 같은 세로 스크롤러 안에 둔다 — `SingleChildScrollView`로
            // 두면 스크롤 탈취 회귀를 못 잡는다(`records_screen`은 ListView다).
            body: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
              children: [
                BodyPhotoTimelineCard(album: BodyPhotoAlbum.from(photos)),
                // 기록 탭엔 이 카드 아래로 인바디 카드들이 더 있다. 스크롤이 실제로
                // 가능한 상태여야 "슬라이더가 세로 스크롤을 빼앗는가"를 검사할 수 있다.
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 같은 State를 유지한 채 앨범만 갈아끼운다(= 서버 갱신이 도착한 상황).
  /// `pump`를 다시 부르면 위젯 트리가 새로 생겨 `initState`가 다시 돌아버려
  /// **검사하려는 결함이 재현되지 않는다.**
  Future<void> pumpAlbum(WidgetTester tester, List<BodyPhotoEntry> photos) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
              children: [
                BodyPhotoTimelineCard(album: BodyPhotoAlbum.from(photos)),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 「기준」을 고르는 날짜 칩. 같은 날짜 문자열이 스크러버 양 끝 라벨과 타일 pill에도
  /// 뜨므로 `find.text`만 쓰면 finder가 모호해진다.
  Finder dateChip(String label) => find.widgetWithText(RiseChip, label);

  /// 지금 화면에 뜬 사진 타일의 키 목록(왼쪽=기준, 오른쪽=비교).
  List<String> tileKeys(WidgetTester tester) => tester
      .widgetList(find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('body-photo-tile-')))
      .map((w) => (w.key! as ValueKey<String>).value)
      .toList();

  group('스크러버가 실제로 사진을 바꾼다', () {
    testWidgets('끌면 「비교」쪽 타일이 다른 사진으로 교체된다', (tester) async {
      // 이게 이 스위트의 존재 이유다. 종전 구현에서는 슬라이더를 끝까지 밀어도
      // 두 타일의 키가 그대로였다 — 값만 바뀌고 화면은 그대로였기 때문이다.
      await pump(tester, [
        photo('stand', 1),
        photo('stand', 8),
        photo('stand', 15),
      ]);

      final before = tileKeys(tester);
      expect(before.length, 2);

      // 최신(8/15)에서 시작하므로 왼쪽 끝으로 밀면 가장 오래된 사진이 와야 한다.
      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pump();

      final after = tileKeys(tester);
      expect(after.first, before.first, reason: '「기준」은 스크러버가 건드리지 않는다');
      expect(after.last, isNot(before.last), reason: '끌었는데 비교 사진이 그대로다');
    });

    testWidgets('첫 진입은 가장 오래된 사진 ↔ 최신 사진', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 8), photo('stand', 15)]);

      final keys = tileKeys(tester);
      expect(keys.first, endsWith('stand-202681'), reason: '기준 = 최초 촬영');
      expect(keys.last, endsWith('stand-2026815'), reason: '비교 = 최신');
    });

    testWidgets('사진이 1장이면 스크러버를 그리지 않는다', (tester) async {
      // 끌 곳이 없는 슬라이더는 정확히 종전에 지운 그 죽은 컨트롤이다.
      await pump(tester, [photo('stand', 1)]);
      expect(find.byType(Slider), findsNothing);
      expect(find.textContaining('2장 이상 필요해요'), findsOneWidget);
    });

    testWidgets('노치가 사진 수만큼만 있다 — 사진 사이를 보간하지 않는다', (tester) async {
      // 연속값이면 손잡이가 사진과 사진 사이에 설 수 있는데, 그 위치가 가리키는
      // 사진은 존재하지 않는다.
      await pump(tester, [photo('stand', 1), photo('stand', 8), photo('stand', 15)]);

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, 2, reason: '사진 3장이면 구간은 2개다');
      expect(slider.min, 0);
      expect(slider.max, 2);
    });
  });

  group('새 사진이 들어오면 비교가 그리로 옮겨간다', () {
    testWidgets('촬영 후 목록이 갱신되면 방금 찍은 사진이 「비교」에 온다', (tester) async {
      // **실기기에서 드러난 결함이다.** 촬영하고 돌아왔더니 손잡이가 왼쪽 끝에
      // 붙은 채 좌우 둘 다 예전 사진이었다 — `initState`가 데이터 도착 전의 개수로
      // 인덱스를 잡았고, 새 데이터가 와도 다시 잡지 않았다. 방금 찍은 사진을 보러
      // 온 회원에게 그 사진이 안 보이는 게 이 화면 최악의 실패다.
      await pump(tester, [photo('stand', 1)]);
      expect(find.byType(Slider), findsNothing, reason: '1장이면 비교가 성립하지 않는다');

      await pumpAlbum(tester, [photo('stand', 1), photo('stand', 27)]);

      expect(tileKeys(tester).last, endsWith('stand-2026827'),
          reason: '방금 찍은 사진이 비교 자리에 와야 한다');
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 1, reason: '손잡이도 새 사진 자리로 가야 한다');
    });

    testWidgets('사진이 늘지 않은 갱신은 보던 자리를 건드리지 않는다', (tester) async {
      // 회원이 일부러 과거로 훑어 둔 자리를 백그라운드 새로고침이 걷어차면 안 된다.
      final album = [photo('stand', 1), photo('stand', 8), photo('stand', 15)];
      await pump(tester, album);
      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pump();
      final scrubbed = tileKeys(tester).last;

      await pumpAlbum(tester, album);

      expect(tileKeys(tester).last, scrubbed, reason: '보던 자리가 튕겼다');
    });
  });

  group('기준과 비교의 소유가 갈린다', () {
    testWidgets('날짜 칩은 「기준」만 바꾼다 — 비교는 그대로', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 8), photo('stand', 15)]);
      final before = tileKeys(tester);

      await tester.tap(dateChip('8/8'));
      await tester.pump();

      final after = tileKeys(tester);
      expect(after.first, isNot(before.first), reason: '칩을 눌렀으면 기준이 바뀐다');
      expect(after.last, before.last, reason: '칩이 비교쪽까지 건드리면 안 된다');
    });

    testWidgets('기준을 비교와 같은 날짜로 옮기면 그 사실을 말한다 — 조용히 자기 자신과 비교하지 않는다', (tester) async {
      // **종전 구현의 결함이 여기 있었다.** 한 핸들러가 두 값을 다 건드려서
      // (`_before = after; _after = i`) 지금 「비교」인 칩을 누르면 둘 다 같은 값이
      // 됐고, **화면은 아무 말도 하지 않았다.** 사진 1장일 때 막아 둔 "자기 자신과의
      // 비교"가 2장 이상에서 탭 한 번으로 되살아난 것이다.
      //
      // 지금은 소유가 갈려 그 상태가 **의도했을 때만** 만들어지고(위 테스트가 잠근다),
      // 만들어지면 화면이 말한다. 막지 않는 이유는 §4-4와 같다 — 막으면 "고장 났다"로
      // 읽힌다.
      await pump(tester, [photo('stand', 1), photo('stand', 8)]);
      expect(find.textContaining('기준과 같은 사진'), findsNothing);

      // 지금 「비교」는 8/8. 그 날짜를 기준으로 고르면 둘이 같아진다.
      await tester.tap(dateChip('8/8'));
      await tester.pump();

      final keys = tileKeys(tester);
      expect(keys.first, keys.last);
      expect(find.textContaining('기준과 같은 사진'), findsOneWidget,
          reason: '같은 사진 두 장을 말없이 나란히 놓으면 회원은 앱이 멈춘 줄 안다');
    });

    testWidgets('스크러버가 기준 위를 지나가는 건 막지 않되 말해준다', (tester) async {
      // 막으면 손잡이가 그 지점에서 튕겨 "고장 났다"로 읽힌다.
      await pump(tester, [photo('stand', 1), photo('stand', 8)]);
      expect(find.textContaining('기준과 같은 사진'), findsNothing);

      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pump();

      final keys = tileKeys(tester);
      expect(keys.first, keys.last, reason: '기준(8/1)까지 밀었으면 같은 사진이 맞다');
      expect(find.textContaining('기준과 같은 사진'), findsOneWidget);
    });
  });

  group('상태 줄 — 두 날짜의 간격을 말한다', () {
    testWidgets('며칠 만의 변화인지 붙는다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 29)]);
      expect(find.textContaining('28일 뒤'), findsOneWidget);
    });

    testWidgets('과거로 훑으면 「전」이라고 말한다 — 「후」로 쓰면 거짓이 된다', (tester) async {
      // 「전/후」 라벨을 쓰지 않는 이유가 여기 있다. 스크러버는 양방향이라
      // "후"가 "전"보다 이전 날짜가 되는 순간이 정상 경로에 있다.
      await pump(tester, [photo('stand', 1), photo('stand', 15), photo('stand', 29)]);

      // 기준을 최신(8/29)으로 옮기면 비교(8/29)와 같아지므로, 먼저 기준을 옮기고
      // 스크러버를 과거로 민다.
      await tester.tap(dateChip('8/29'));
      await tester.pump();
      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pump();

      expect(find.textContaining('28일 전'), findsOneWidget);
      expect(find.textContaining('28일 뒤'), findsNothing);
    });
  });

  group('사진이 잘리지 않는다', () {
    testWidgets('타일은 3:4 프레임 — 고정 높이면 사진마다 비율이 달라진다', (tester) async {
      // 320dp에서 타일 폭은 129dp다. 종전 `height: 130` 고정이면 거의 정사각이라
      // 3:4 사진의 세로 24.4%가 잘렸다 — 촬영 격자가 기준으로 삼은 어깨선·골반선·발이
      // 바로 그 잘려나간 자리에 있다.
      await pump(tester, [photo('stand', 1), photo('stand', 8)]);

      final frames = tester.widgetList<AspectRatio>(find.descendant(
        of: find.byType(BodyPhotoTimelineCard),
        matching: find.byType(AspectRatio),
      ));
      expect(frames, isNotEmpty, reason: '고정 높이면 비율이 사진마다 달라진다');
      expect(frames.every((f) => f.aspectRatio == 3 / 4), isTrue);
    });

    testWidgets('실제로 그릴 때 contain이다 — cover는 두 사진을 서로 다르게 잘라낸다', (tester) async {
      // 프레임만 3:4로 잡고 `cover`로 채우면 잘리는 건 똑같다. 비율이 다른 두 장이
      // **서로 다른 만큼** 잘리면 그 자체가 없는 차이를 만든다 — 이 화면이 절대
      // 하면 안 되는 일이다. 레터박스 띠는 몸의 변화로 오해될 수 없다.
      await pump(tester, [photo('stand', 1), photo('stand', 8)], loader: _FakeLoader());

      final images = tester.widgetList<Image>(find.descendant(
        of: find.byType(BodyPhotoTimelineCard),
        matching: find.byType(Image),
      ));
      expect(images, hasLength(2), reason: '두 장이 다 그려져야 비교다');
      expect(images.every((i) => i.fit == BoxFit.contain), isTrue);
    });
  });

  group('블링크 비교 — 이미 본 사진은 즉시 뜬다', () {
    testWidgets('캐시에 있으면 스피너를 거치지 않는다', (tester) async {
      // 스크러버의 핵심 사용법은 손잡이를 좌우로 까딱해 두 날짜를 번갈아 보는 것이다.
      // 노치를 넘을 때마다 `FutureBuilder`가 한 프레임 스피너를 그리면 **눈이 좇아야
      // 할 차이가 깜빡임에 묻혀** 비교 자체가 성립하지 않는다.
      final loader = _FakeLoader();
      await pump(tester, [photo('stand', 1), photo('stand', 8)], loader: loader);

      // pump 한 번 = 한 프레임. 여기서 스피너가 보이면 실기기에서도 번쩍인다.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(loader.awaited, isEmpty, reason: '캐시 히트인데 비동기 경로를 탔다');
    });

    testWidgets('캐시에 없으면 스피너를 보여준다 — 빈 칸으로 위장하지 않는다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 8)],
          loader: _FakeLoader(cached: false));
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    });
  });

  group('해를 넘긴 타임라인', () {
    testWidgets('연도가 다르면 날짜에 연도가 붙는다', (tester) async {
      // 1년 넘게 다닌 회원의 `8/14`가 두 개면 어느 해인지 알 방법이 없다.
      await pump(tester, [
        photo('stand', 14, year: 2025),
        photo('stand', 14, year: 2026),
      ]);
      expect(find.textContaining("'25"), findsWidgets);
      expect(find.textContaining("'26"), findsWidgets);
    });

    testWidgets('한 해 안이면 연도를 붙이지 않는다 — 좁은 칩에 낭비다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 8)]);
      expect(find.textContaining("'26"), findsNothing);
      expect(find.text('8/1'), findsWidgets);
    });
  });

  group('세로 스크롤을 빼앗지 않는다', () {
    testWidgets('카드 위에서 세로로 끌면 페이지가 스크롤된다', (tester) async {
      // 세로 드래그를 새로 넣으면 아레나가 축으로 갈라 주지 못해 동률이 되고,
      // 그때는 더 깊은 자식이 이겨 **사진 위에서 페이지 스크롤이 죽는다.**
      // 스크러버가 가로여야 하는 이유가 이것이다.
      await pump(tester, List.generate(6, (i) => photo('stand', 1 + i * 3)));

      final scrollable = find.byType(Scrollable).first;
      final before = tester.widget<Scrollable>(scrollable).controller?.offset ??
          tester.state<ScrollableState>(scrollable).position.pixels;

      await tester.drag(find.byType(Slider), const Offset(0, -300));
      await tester.pump();

      final after = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(after, greaterThan(before),
          reason: '슬라이더 위에서 세로로 끌었는데 페이지가 안 움직였다');
    });
  });

  group('없는 곳을 가리키지 않는다', () {
    testWidgets('"촬영 탭"이라고 말하지 않는다 — 탭이 아니라 가운데 버튼이다', (tester) async {
      // `app_shell.dart`가 명시한다: "촬영은 탭이 아니다(P21)". 탭은 4개고 촬영은
      // 그 사이의 빨간 원이라 선택 상태를 갖지 않는다. 없는 탭을 찾아 하단바를
      // 훑게 만드는 안내는 안 하느니만 못하다.
      await pump(tester, const <BodyPhotoEntry>[]);
      expect(find.textContaining('촬영 탭'), findsNothing);
      expect(find.textContaining('가운데'), findsOneWidget);
    });

    testWidgets('겹쳐 보기를 약속하지 않는다', (tester) async {
      // 두 사진은 정합돼 있지 않다(pitch·거리 어느 것도 강제·저장하지 않는다).
      // 2.5m에서 20cm 앞으로 서면 실루엣이 8.7% 커지는데 한 달치 실제 변화는 5%
      // 남짓이라, 겹쳐 놓으면 **오차가 신호보다 크다.**
      await pump(tester, [photo('stand', 1), photo('stand', 8)]);
      expect(find.textContaining('촬영 거리'), findsOneWidget);
      expect(find.textContaining('겹치지 않고'), findsOneWidget);
    });
  });
}

/// 실제 바이트를 주는 로더. Firebase 없이 사진 렌더 경로를 지난다.
///
/// [cached]가 true면 [peek]이 바로 바이트를 준다 = 이미 본 사진. 스크러버가 노치를
/// 넘을 때 이 경로가 **비동기 한 틱도 타지 않아야** 블링크 비교가 성립한다.
class _FakeLoader implements BodyPhotoLoader {
  _FakeLoader({this.cached = true});
  final bool cached;

  /// 비동기 경로를 탄 경로들 — 캐시 히트인데 여기 값이 쌓이면 설계가 깨진 것이다.
  final awaited = <String>[];

  /// 1×1 투명 PNG(디코더가 실제로 받아들이는 최소 바이트).
  static final _png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  final evicted = <String>[];

  @override
  void clear() {}

  @override
  void evict(String storagePath) => evicted.add(storagePath);

  @override
  Uint8List? peek(String storagePath) => cached ? _png : null;

  @override
  Future<Result<Uint8List>> load(String storagePath) async {
    awaited.add(storagePath);
    if (!cached) {
      // 영원히 안 끝나는 요청 = 로딩 상태 그대로. 스피너를 검사할 수 있다.
      return Completer<Result<Uint8List>>().future;
    }
    return Ok(_png);
  }
}
