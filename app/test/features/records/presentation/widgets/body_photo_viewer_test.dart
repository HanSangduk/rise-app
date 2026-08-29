// 체형사진 뷰어(P31).
//
// 람의 지적: *"데이터 있으면 눌러서 내 체형분석 사진 보면 좋을거 같은데 그런것도
// 없는건가?"* — 없었다. 타일은 129dp라 회원이 보려는 어깨선 기울기·허리 윤곽이
// 그 크기에선 판독되지 않는다. 어드민에는 라이트박스가 있는데(`BodyPhotoLightbox`)
// 정작 자기 몸을 찍은 회원 앱에만 없었다.
//
// 삭제도 여기 붙는다 — 지울지 말지는 **크게 보고 나서** 정해진다.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise_member/core/result/failure.dart';
import 'package:rise_member/core/result/result.dart';
import 'package:rise_member/features/bodycheck/data/body_check_repository_provider.dart';
import 'package:rise_member/features/bodycheck/data/body_photo_loader.dart';
import 'package:rise_member/features/bodycheck/domain/body_check_repository.dart';
import 'package:rise_member/features/bodycheck/domain/bodycheck_models.dart';
import 'package:rise_member/features/records/domain/records_models.dart';
import 'package:rise_member/features/records/presentation/widgets/body_photo_timeline.dart';

void main() {
  BodyPhotoEntry photo(String pose, int day) => BodyPhotoEntry(
        id: '$pose-$day',
        memberId: 'm1',
        pose: pose,
        direction: BodyDirection.front,
        date: DateTime(2026, 8, day),
        blurred: false,
        storagePath: 'members/m1/body/$pose-$day.jpg',
      );

  late _FakeRepo repo;
  late int refreshes;

  Future<void> pump(
    WidgetTester tester,
    List<BodyPhotoEntry> photos, {
    bool canDelete = true,
    bool loadFails = false,
  }) async {
    tester.view.physicalSize = const Size(384, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repo = _FakeRepo();
    refreshes = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bodyPhotoLoaderProvider.overrideWithValue(_FakeLoader(fail: loadFails)),
          bodyCheckRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                BodyPhotoTimelineCard(
                  album: BodyPhotoAlbum.from(photos),
                  onPhotoDeleted: canDelete ? () => refreshes++ : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 「비교」쪽(오른쪽) 타일을 누른다.
  Future<void> openViewer(WidgetTester tester) async {
    await tester.tap(find.byType(Image).last);
    await tester.pumpAndSettle();
  }

  group('탭하면 크게 열린다', () {
    testWidgets('타일을 누르면 뷰어가 뜬다 — 날짜는 연도까지', (tester) async {
      // 뷰어는 타임라인 문맥 밖이라 `8/14`만으론 어느 해인지 알 수 없다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      expect(find.textContaining('2026년'), findsNothing);

      await openViewer(tester);

      expect(find.text('2026년 8월 14일'), findsOneWidget);
      expect(find.text('차렷'), findsWidgets, reason: '어떤 포즈인지 따라와야 한다');
    });

    testWidgets('크롬은 화면 위쪽에 붙는다 — 가운데로 내려오지 않는다', (tester) async {
      // **실기기에서만 드러난 결함이다.** `Expanded` 안 `Column`이 기본
      // `MainAxisSize.max`라 `Stack`의 느슨한 제약에서 화면 높이를 다 먹었고,
      // 부모 `Row`가 전체 높이가 되면서 `crossAxisAlignment: center` 때문에
      // 닫기·삭제 버튼이 **사진 한가운데**에 떠 있었다. 날짜 텍스트는 위에
      // 그대로 있어서 스크린샷을 보기 전엔 알 수 없었다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);

      final screen = tester.getSize(find.byType(MaterialApp)).height;
      for (final tip in ['닫기', '삭제']) {
        final y = tester.getCenter(find.byTooltip(tip)).dy;
        expect(y, lessThan(screen * 0.2), reason: '$tip 버튼이 화면 위쪽에 없다');
      }
    });

    testWidgets('닫으면 타임라인으로 돌아온다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);

      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();

      expect(find.text('2026년 8월 14일'), findsNothing);
      expect(find.text('체형 분석 타임라인'), findsOneWidget);
    });

    testWidgets('로딩·실패 타일은 열리지 않는다', (tester) async {
      // 빈 뷰어가 뜨면 회원은 사진이 사라진 걸로 읽는다. 실패 타일엔 이미
      // "다시 시도"가 있어서 할 일이 따로 있다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)], loadFails: true);
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNothing, reason: '실패 타일엔 열 사진이 없다');
      expect(find.text('다시 시도'), findsNWidgets(2));

      // 실패 타일을 눌러도 뷰어가 열리지 않는다.
      await tester.tap(find.textContaining('사진을 불러오지 못했어요').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('닫기'), findsNothing, reason: '빈 뷰어가 열렸다');
    });

    testWidgets('기준과 비교가 같은 사진이어도 Hero 태그가 충돌하지 않는다', (tester) async {
      // 스크러버가 기준 위를 지나가는 건 **정상 경로**다(막으면 손잡이가 튕겨
      // "고장 났다"로 읽힌다). 태그를 경로만으로 만들면 같은 태그가 화면에 둘이 되어
      // Flutter가 assert를 던진다 — 슬롯을 함께 넣어 막는다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);

      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.textContaining('기준과 같은 사진'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Hero 태그가 중복됐다');

      // 그 상태에서 열어도 정상 동작해야 한다.
      await openViewer(tester);
      expect(find.text('2026년 8월 1일'), findsOneWidget);
    });
  });

  group('삭제 — 되돌릴 수 없다고 말한다', () {
    testWidgets('확인 문구가 즉시·완전 파기를 말한다', (tester) async {
      // 회원 삭제는 서버가 즉시 완전 파기하고 복원 경로가 **없다**(스태프 삭제만
      // 30일 유예). "나중에 복구할 수 있다"고 읽히면 그 자체로 거짓 고지다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);

      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();

      expect(find.textContaining('되돌릴 수 없어요'), findsOneWidget);
      expect(find.textContaining('센터에도 남지 않아요'), findsOneWidget);
      // "다시 찍으면 된다"는 위로는 넣지 않는다 — 다시 찍을 수 있는 건 오늘의
      // 몸이지 그날의 몸이 아니다.
      expect(find.textContaining('다시 찍'), findsNothing);
    });

    testWidgets('취소하면 아무 요청도 나가지 않는다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);
      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(repo.deleted, isEmpty);
      expect(find.text('2026년 8월 14일'), findsOneWidget, reason: '뷰어는 열려 있어야 한다');
    });

    testWidgets('확정하면 지우고 목록을 다시 받는다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);
      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(repo.deleted, ['stand-14']);
      expect(refreshes, 1, reason: '갱신하지 않으면 지운 사진이 화면에 그대로 남는다');
      expect(find.text('2026년 8월 14일'), findsNothing, reason: '뷰어가 닫혀야 한다');
    });

    testWidgets('삭제가 실패하면 뷰어를 닫지 않고 이유를 말한다', (tester) async {
      // 닫아 버리면 회원은 지워진 줄 안다. 서버 문구를 그대로 띄우고 남는다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      repo.failure = const NetworkFailure('네트워크를 확인해주세요');
      await openViewer(tester);
      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(refreshes, 0);
      expect(find.text('2026년 8월 14일'), findsOneWidget, reason: '실패했는데 닫혔다');
      // 스낵바가 **서버 문구를 그대로** 띄운다(앱이 고쳐 쓰지 않는다).
      // `findsWidgets`인 이유: ScaffoldMessenger가 애니메이션용 사본을 만들어
      // 전환 중 SnackBar 노드가 둘이 된다 — 개수는 이 테스트의 관심사가 아니다.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('네트워크를 확인해주세요'),
        ),
        findsWidgets,
      );
    });

    testWidgets('삭제 요청에 storagePath를 함께 보낸다 — 캐시를 비울 열쇠다', (tester) async {
      // **캐시가 실제로 비워지는지는 여기서 검사하지 않는다** — 가짜 리포지토리를
      // 쓰므로 진짜 evict 호출을 지워도 이 테스트는 통과한다(뮤테이션으로 확인했다).
      // 그 계약은 가 실제
      // 리포지토리로 잠근다. 여기서 잠그는 건 뷰어의 몫 — 경로를 빠뜨리지 않는 것.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);
      await tester.tap(find.byTooltip('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(repo.evicted, ['members/m1/body/stand-14.jpg']);
    });

    testWidgets('목록을 갱신할 방법이 없으면 삭제 버튼을 띄우지 않는다', (tester) async {
      await pump(tester, [photo('stand', 1), photo('stand', 14)], canDelete: false);
      await openViewer(tester);
      expect(find.byTooltip('삭제'), findsNothing);
      expect(find.byTooltip('닫기'), findsOneWidget);
    });
  });

  group('내보내기 경로를 열지 않는다', () {
    testWidgets('공유·저장 버튼이 없다', (tester) async {
      // 이 앱은 민감정보를 `no-store`로 올리고 토큰 URL을 일부러 배제했다
      // (`body_photo_loader` 헤더). 내보내기 버튼은 그 설계를 한 번에 무효로 만든다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);

      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.byIcon(Icons.download), findsNothing);
      expect(find.byIcon(Icons.save_alt), findsNothing);
      expect(find.textContaining('공유'), findsNothing);
      expect(find.textContaining('저장'), findsNothing);
    });

    testWidgets('열람 범위를 서버 판정과 같은 말로 알린다', (tester) async {
      // 서버 `checkBodyPhotoAccess`: 본인 · 담당 코치 · 대표, 스태프는 민감정보
      // 동의가 유효한 동안만. 사진을 크게 보는 순간이 회원이 "이거 누가 보지?"를
      // 가장 강하게 떠올리는 자리다.
      await pump(tester, [photo('stand', 1), photo('stand', 14)]);
      await openViewer(tester);

      expect(find.textContaining('담당 코치'), findsOneWidget);
      expect(find.textContaining('동의를 끄면'), findsOneWidget);
    });
  });
}

class _FakeRepo implements BodyCheckRepository {
  final deleted = <String>[];
  final evicted = <String>[];
  Failure? failure;

  @override
  Future<Result<void>> deletePhoto({required String id, String? storagePath}) async {
    if (failure != null) return Err(failure!);
    deleted.add(id);
    if (storagePath != null) evicted.add(storagePath);
    return const Ok(null);
  }

  @override
  Future<Result<List<BodyPhotoEntry>>> fetchPhotos(String memberId) async =>
      const Ok([]);

  @override
  Future<Result<BodyPhotoEntry>> uploadPhoto({
    required String memberId,
    required String pose,
    required BodyDirection direction,
    required DateTime date,
    required String storagePath,
  }) =>
      throw UnimplementedError();
}

class _FakeLoader implements BodyPhotoLoader {
  _FakeLoader({this.fail = false});
  final bool fail;

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
  Uint8List? peek(String storagePath) => fail ? null : _png;

  @override
  Future<Result<Uint8List>> load(String storagePath) async => fail
      ? const Err(NetworkFailure('사진을 불러오지 못했어요'))
      : Ok(_png);
}
